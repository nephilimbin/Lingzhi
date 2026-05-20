import asyncio
import os
import time
import traceback
from typing import TYPE_CHECKING, List, Union

from config.logger import setup_logging
from core.context.event_bus import Event
from core.context.event_types import EventTypes
from core.models.message_models import AudioFormat, MessageInfo, PlaybackMode, PlaybackState
from core.utils.audio_opus_handler import OpusDecoder
from core.utils.audio_pcm_handler import PcmHandler
from core.utils.util import remove_punctuation_and_length, set_unique_id
import numpy as np

# 使用TYPE_CHECKING来避免循环导入
if TYPE_CHECKING:
    from core.session.session_context import SessionContext

TAG = __name__


class AudioBytesParseHandler:
    """
    音频字节解析处理器 - 负责处理音频数据流的解析和语音识别。

    该处理器是AI助手音频输入系统的核心组件，专门处理实时音频数据的接收、
    解析、语音活动检测和语音识别转换。支持流式和非流式两种ASR处理模式。

    核心功能:
        - 音频事件订阅和异步处理
        - 多种音频格式解析（Opus、PCM、Ndarray）
        - 语音活动检测（VAD）和静音判断
        - 流式和非流式ASR处理策略选择
        - 音频数据保存和管理
        - 任务取消和状态管理
        - WebRTC预览任务取消

    处理流程:
        音频事件接收 → 格式解析 → VAD检测 → ASR识别 → 结果处理 → 对话集成

    设计模式:
        - 观察者模式: 订阅和处理音频字节解析事件
        - 策略模式: 根据ASR支持情况选择流式或非流式处理策略
        - 状态模式: 管理不同的音频处理状态（首次语音、语音结束等）
    注意事项:
        - 所有方法都是异步的，需要在协程环境中使用
        - 处理器会在初始化时自动订阅音频字节解析事件
        - 支持任务取消机制，可在外部中断音频处理
        - 静音检测阈值通过配置文件设置
    """

    def __init__(self, context: "SessionContext"):
        """
        初始化音频字节解析处理器。
        :param context: 会话上下文对象
        """
        self.logger = setup_logging()
        self.context = context
        self.event_bus = context.event_bus
        self.session_request_id = ""
        # 订阅音频相关事件
        self._subscribe_to_events()
        # 从配置中获取静音阈值
        self.silence_threshold_ms = self.context.session_runtime_config.session_vad_config.silence_threshold_ms
        self.current_input_audio_format = None
        # 初始化音频处理器
        self.pcm_handler = PcmHandler()
        self.opus_decoder = OpusDecoder()
        self.transcript_text = ""

    def _subscribe_to_events(self):
        """
        订阅音频消息相关事件。
        """
        try:
            # 检查事件总线是否可用，然后订阅音频字节解析事件
            if self.event_bus:
                self.event_bus.subscribe(EventTypes.AUDIO_BYTES_PARSE_REQUESTED, self.handle_audio_bytes_event)
        except Exception:
            # 事件订阅失败时记录错误日志，但不影响处理器初始化
            self.logger.bind(tag=TAG).error(f"订阅音频消息相关事件失败: {traceback.format_exc()}")

    async def handle_audio_bytes_event(self, event: Event):
        """
        事件驱动的音频处理方法。
        :param event: 音频字节解析事件
        """
        try:
            # 从事件中提取消息信息并获取当前会话请求ID
            request_message_info: MessageInfo = event.data
            self.session_request_id = self.context.state_manager.current_session_request_id

            # 从会话中获取音频源数据并解析为PCM格式
            audio_source = request_message_info.session.audio_source
            audio_pcm_frames = self._parse_input_audio_data(audio_source)

            # 验证音频数据有效性，None表示解析失败
            if audio_pcm_frames is None:
                self.logger.bind(tag=TAG).info(f"音频数据解析失败: {audio_pcm_frames}")
                return

            # 创建异步音频处理任务并支持取消机制
            try:
                task = asyncio.create_task(self.handle(audio_pcm_frames))

                # 通过取消管理器注册任务，支持外部取消操作
                cancellable_task = await self.context.cancellation_manager.register_task(
                    session_id=self.context.session_id,
                    task=task,
                    task_type=self.context.cancellation_manager.task_types.AUDIO_ASR_MONITOR_TASK,
                )

                # 执行音频处理任务
                await task
                # 清理：取消已注册的可取消任务
                if cancellable_task:
                    cancellable_task.cancel()

            except asyncio.CancelledError:
                # 任务被外部取消，记录取消事件
                self.logger.bind(tag=TAG).error("音频处理任务被取消")

        except Exception as e:
            self.logger.bind(tag=TAG).error(f"事件驱动音频处理错误: {e}", exc_info=True)

    async def handle(self, audio_data):
        """
        执行处理音频数据的方法。
        :param audio_data: 音频数据
        """
        try:
            # 从状态管理器获取当前的音频处理相关状态
            client_listen_mode = self.context.state_manager.client_listen_mode  # 客户端监听模式
            client_have_voice = self.context.state_manager.client_have_voice  # 是否检测到人声
            client_voice_stop = self.context.state_manager.client_voice_stop  # 用户是否停止说话

            # 使用VAD（语音活动检测）检查当前音频帧是否包含人声
            vad_have_voice = self.context.vad.is_vad(self.context, audio_data)

            # 实时对话模式：处理静音检测和语音停止判断
            if client_listen_mode == PlaybackMode.AUTO:
                # 检测条件：之前有人声 + 当前无人声 + 有最后人声时间记录
                if (
                    client_have_voice
                    and not vad_have_voice
                    and self.context.state_manager.client_have_voice_last_time != 0
                ):
                    # 计算从最后一次人声到现在的静音持续时间（毫秒）
                    stop_duration = time.time() * 1000 - self.context.state_manager.client_have_voice_last_time
                    self.logger.bind(tag=TAG).debug(f"静音持续时间: {stop_duration}ms")
                    # 如果静音时间超过阈值，判定用户已停止说话
                    if stop_duration >= self.silence_threshold_ms:
                        self.context.state_manager.client_voice_stop = True
                        client_voice_stop = True

            # 处理首次检测到人声的情况
            if not self.context.state_manager.client_first_have_voice:
                if vad_have_voice:
                    # 首次检测到人声，标记状态并进行初始化处理
                    self.context.state_manager.client_first_have_voice = True
                    # 如果是WebRTC传输，需要取消之前可能存在的预览任务
                    if self.context.state_manager.input_audio_transport_type == "webrtc":
                        await self._cancel_preview_tasks()
                    # 保留最近的音频帧，解决ASR句首丢字问题（保留缓冲）
                    self.context.state_manager.keep_latest_asr_audio(count=10)
                else:
                    # 无人声时进行内存管理：如果音频队列过长，保留较新的部分
                    if len(self.context.state_manager.asr_audio_queue) > 100:
                        self.context.state_manager.keep_latest_asr_audio(count=50)

            # 用户开始说话并且检查到有人声
            if vad_have_voice and client_have_voice:
                # 记录客户最后有人声时间
                self.context.state_manager.client_have_voice_last_time = time.time() * 1000

            # 如有任务在执行则返回不重复处理
            if self.context.state_manager.asr_processing_triggered:
                return

            # 根据音频流式或非流式区分处理方式
            try:
                task = asyncio.create_task(self._process_speech_to_text(client_voice_stop, audio_data))

                # 直接使用CancellationManager注册任务
                cancellable_task = await self.context.cancellation_manager.register_task(
                    session_id=self.context.session_id,
                    task=task,
                    task_type=self.context.cancellation_manager.task_types.AUDIO_ASR_PROCESS_TASK,
                )

                # 执行音频处理任务
                await task
                # 取消注册的任务
                if cancellable_task:
                    cancellable_task.cancel()

            except asyncio.CancelledError:
                self.logger.bind(tag=TAG).info("ASR音频处理任务被取消")

            # 用户停止说话后的处理逻辑
            if client_voice_stop:
                # 异步保存完整的音频数据为WAV文件（用于调试和记录）
                # 注意：asr_audio_queue中保存的是PCM格式音频数据
                saved_pcm_list = self.context.state_manager.asr_audio_queue.copy()
                asyncio.create_task(self._save_pcm_to_wav_async(saved_pcm_list))

                # 重置ASR相关状态，为下次语音输入做准备
                self.context.state_manager.reset_asr_task_states()

                # 自动模式下需要重新开启监听循环
                if self.context.state_manager.client_listen_mode == PlaybackMode.AUTO:
                    self.context.state_manager.restart_auto_mode_asr_task_states()

                # 处理完整的语音识别结果，发送到对话处理器
                await self._process_transcript_result(self.transcript_text)
        except Exception as e:
            self.logger.bind(tag=TAG).error(f"事件驱动音频处理错误: {e}, 追踪:{traceback.format_exc()}")

    async def _process_speech_to_text(self, client_voice_stop: bool, audio_data: bytes):
        """
        处理音频转文本任务。
        :param client_voice_stop: 是否是用户停止说话
        :param audio_data: 音频数据
        """
        if self.context.asr.is_support_stream_mode():
            await self._process_streaming_audio(client_voice_stop, audio_data)
        else:
            await self._process_non_streaming_audio(client_voice_stop, audio_data)

    async def _process_streaming_audio(self, client_voice_stop, audio_data):
        """
        处理流式音频ASR请求。
        :param client_voice_stop: 用户是否停止说话
        :param audio_data: 音频数据
        """
        try:
            if client_voice_stop:
                # 标记ASR已触发
                self.context.state_manager.asr_processing_triggered = True
                # 正确关闭ASR识别器，防止下次启动时冲突
                if hasattr(self.context.asr, "close"):
                    try:
                        self.context.asr.close()
                        self.logger.bind(tag=TAG).debug("已关闭旧ASR识别器")
                    except Exception as e:
                        self.logger.bind(tag=TAG).error(f"关闭ASR识别器时出现异常: {e}")

                self.transcript_text = f"{''.join([t['text'] for t in self.context.state_manager.asr_transcript_text])}"
                # return transcript_text

            # 收录音频字节
            self.context.state_manager.append_asr_audio(audio_data)
            # 音频识别转文本
            asr_response = await self.context.asr.speech_to_text(audio_data)
            transcription_text = asr_response.text
            transcription_is_final = asr_response.is_final
            sentence_id = asr_response.sentence_id or 0

            if transcription_text:
                # 判断是否是新句子（基于sentence_id）
                transcription_dict = {
                    "text": transcription_text,
                    "sentence_id": sentence_id,
                    "is_sentence_end": transcription_is_final,
                }
                is_new_sentence = (
                    not self.context.state_manager.asr_transcript_text
                    or self.context.state_manager.asr_transcript_text[-1].get("sentence_id", -1) != sentence_id
                )
                if transcription_is_final:
                    # 最终结果处理
                    if is_new_sentence:
                        self.context.state_manager.asr_transcript_text.append(transcription_dict)
                    else:
                        self.context.state_manager.asr_transcript_text[-1] = transcription_dict
                else:
                    # 临时结果处理
                    if is_new_sentence:
                        self.context.state_manager.asr_transcript_text.append(transcription_dict)
                    else:
                        self.context.state_manager.asr_transcript_text[-1] = transcription_dict
                # 发送流式识别结果
                transcript_merged_text = (
                    f"{''.join([t['text'] for t in self.context.state_manager.asr_transcript_text])}"
                )
                await self.context.output_processor.send_stt_message(
                    transcript_merged_text, session_request_id=self.session_request_id
                )

        except Exception:
            self.logger.bind(tag=TAG).error(f"流式音频处理错误{traceback.format_exc()}. ")

    async def _process_non_streaming_audio(self, client_voice_stop, audio_data):
        """
        处理非流式音频ASR请求。
        :param client_voice_stop: 用户是否停止说话
        :param audio_data: 音频数据
        """
        # 通过StateManager添加音频数据
        self.context.state_manager.append_asr_audio(audio_data)

        # 检查是否说话停止
        if not client_voice_stop:
            return

        # 标记ASR已触发
        self.context.state_manager.asr_processing_triggered = True

        # 获取音频数据
        asr_audio = self.context.state_manager.asr_audio_queue
        # 音频太短了，无法识别
        try:
            if len(asr_audio) < 15:
                await self.context.output_processor.send_stt_message("", session_request_id=self.session_request_id)
                await self.context.output_processor.send_tts_state_message(
                    state=PlaybackState.END, session_request_id=self.session_request_id
                )
                return
            # 对于非流式模式，直接传递音频数据列表给ASR提供者处理
            asr_response = await self.context.asr.speech_to_text(list(asr_audio))
            asr_text = asr_response.text
            self.context.state_manager.asr_transcript_text.append({"text": asr_text, "sentence_id": 0})

            # 处理ASR转录结果
            self.transcript_text = f"{''.join([t['text'] for t in self.context.state_manager.asr_transcript_text])}"
            # self.logger.bind(tag=TAG).debug(f"ASR非流式识别文本: {self.transcript_text}")

        except Exception as asr_err:
            self.logger.bind(tag=TAG).error(f"ASR识别错误: {asr_err}", exc_info=True)

    async def _no_voice_close_connect(self):
        """
        处理长时间静音导致的连接关闭逻辑。
        """

        # 通过StateManager管理无声音时间
        # TODO: 需要优化，因为有时候会话已经结束，但是没有声音，也会关闭连接，需要再次启动的唤醒操作
        try:
            # 如果上次没有声音的时间是0，则更新为当前时间
            if self.context.state_manager.client_no_voice_last_time == 0.0:
                self.context.state_manager.update_state(
                    client_no_voice_last_time=time.time() * 1000,
                )
            else:
                # 计算无声音时间
                no_voice_time = time.time() * 1000 - self.context.state_manager.client_no_voice_last_time
                tts_silent_timeout_shutdown_duration = (
                    self.context.session_runtime_config.session_tts_config.tts_silent_timeout_shutdown_duration
                )
                # 如果超过无声音时间，则关闭连接
                if (
                    not self.context.state_manager.close_after_chat
                    and no_voice_time > 1000 * tts_silent_timeout_shutdown_duration
                ):
                    # 更新状态
                    updates = {
                        "close_after_chat": True,
                    }
                    self.context.state_manager.update_state(**updates)
                    # 使用对话编排器处理超时提示
                    # prompt = """请你以"时间过得真快"为开头，用富有感情、依依不舍的话来结束这场对话吧。"""
                    # await self.context.chat_processor.process_client_input(prompt, source="timeout")
        except Exception as e:
            self.logger.bind(tag=TAG).error(f"无声音关闭连接逻辑处理错误: {e}", exc_info=True)

    async def _process_transcript_result(self, text):
        """
        处理语音转录结果。
        :param text: 转录的文本内容
        """
        self.logger.bind(tag=TAG).info(f"用户说话结束，语音识别结果:{text}")
        try:
            # 检查ASR结果是否有效
            if text is None or not isinstance(text, str):
                self.logger.bind(tag=TAG).warning(f"ASR返回无效结果: {text}")
                text_len = 0
            else:
                text_len, _ = remove_punctuation_and_length(text)
            # 如果文本长度大于0，则发送文本到前端chat页面
            if text_len > 0:
                # 发送stt识别结果到前端页面
                await self.context.output_processor.send_stt_message(text, session_request_id=self.session_request_id)
                await self.context.chat_processor.process_client_chat(
                    text,
                    source="audio",
                    session_request_id=self.session_request_id,
                )
            else:
                await self.context.output_processor.send_stt_message("", session_request_id=self.session_request_id)
                await self.context.output_processor.send_tts_state_message(
                    state=PlaybackState.END, session_request_id=self.session_request_id
                )
        except Exception:
            self.logger.bind(tag=TAG).error(f"处理ASR结果错误: {traceback.format_exc()}")

    async def _save_pcm_to_wav_async(self, pcm_list: List[bytes]) -> None:
        """
        异步保存音频文件到后台，不阻塞主进程。
        :param pcm_list: PCM音频数据列表
        """

        try:
            # 生成文件名
            timestamp = int(time.time())
            model_name = getattr(self.context.asr, "model_name", "unknown")
            filename = f"asr_{timestamp}_{model_name}_{self.session_request_id}.wav"
            # 获取会话目录，在会话目录下创建 asr 子目录
            # 如果 client_session_dir 为空，则使用默认值
            if self.context.client_session_dir:
                asr_output_dir = os.path.join(self.context.client_session_dir, "asr")
            else:
                asr_output_dir = "./data/asr_audio"
            # 确保目录路径有效，创建必要的目录结构
            os.makedirs(asr_output_dir, exist_ok=True)
            saved_path = os.path.join(asr_output_dir, filename)
            # 异步保存音频文件
            complete_pcm_data = b"".join(pcm_list)
            self.pcm_handler.save_pcm_to_file(complete_pcm_data, saved_path)

        except Exception:
            self.logger.bind(tag=TAG).error(f"创建音频保存任务失败: {traceback.format_exc()}")

    def _parse_input_audio_data(self, audio_data: Union[bytes, np.ndarray]) -> bytes:
        """
        解析输入音频流转为pcm格式。
        :param audio_data: 输入音频数据
        :return: pcm格式音频数据
        """
        try:
            # 获取音频数据类型和内容
            if self.context.state_manager.input_audio_has_started:
                input_audio_format = self.context.state_manager.input_audio_format
                input_audio_sample_rate = self.context.state_manager.input_audio_sample_rate
                input_audio_channels = self.context.state_manager.input_audio_channels
                input_audio_frame_duration = self.context.state_manager.input_audio_frame_duration
                # 检查音频参数是否为空
                if not input_audio_format:
                    raise ValueError("输入音频参数为空，无法准确解析，请设置对应的音频参数")
                else:
                    self.current_input_audio_format = input_audio_format

                # 创建音频解析器
                if input_audio_format == AudioFormat.OPUS:
                    if (input_audio_sample_rate, input_audio_channels, input_audio_frame_duration) != (16000, 1, 60):
                        raise ValueError(
                            f"Opus音频参数错误: 采样率={input_audio_sample_rate}Hz(期望16000), "
                            f"通道={input_audio_channels}(期望1), "
                            f"帧时长={input_audio_frame_duration}ms(期望60)"
                        )
                elif input_audio_format == AudioFormat.NDARRAY:
                    if (input_audio_sample_rate) != (16000):
                        raise ValueError(f"ndarray音频数组参数错误: 采样率={input_audio_sample_rate}Hz(期望16000)")
                elif input_audio_format == AudioFormat.PCM:
                    pass
                else:
                    # 没有可解析的输入音频格式
                    raise ValueError(f"不支持的输入音频格式: {input_audio_format}")
                # 关闭输入音频控制，避免重复创建输入音频校验逻辑
                self.context.state_manager.input_audio_has_started = False

            # 处理音频内容
            pcm_frames = ""
            if self.current_input_audio_format == AudioFormat.OPUS:
                # 解码opus为pcm
                pcm_frames = self.opus_decoder.decode_pcm_stream(audio_data)
            elif self.current_input_audio_format == AudioFormat.NDARRAY:
                # 确保音频非空
                if audio_data.size == 0:
                    return ""
                # 确保音频数据都是一维格式
                if len(audio_data.shape) > 1:
                    audio_data = audio_data.flatten()

                try:
                    # 确保16位PCM
                    if audio_data.dtype != np.int16:
                        if audio_data.dtype in [np.float32, np.float64]:
                            audio_data = (audio_data * 32767).astype(np.int16)
                        elif audio_data.dtype == np.int32:
                            audio_data = (audio_data // 65536).astype(np.int16)
                        else:
                            audio_data = audio_data.astype(np.int16)

                    # Ensure little-endian byte order
                    pcm_frames = audio_data.tobytes(order="C")
                except Exception:
                    self.logger.error(f"❌ Ndarray转PCM格式异常:{traceback.format_exc()}")
                    pcm_frames = b""

            return pcm_frames
        except Exception:
            self.logger.bind(tag=TAG).error(f"解析输入音频时发生错误: {traceback.format_exc()}")
            raise

    async def _cancel_preview_tasks(self):
        """
        取消预览任务，为新语音输入做准备。
        """
        try:
            self.logger.bind(tag=TAG).info("=========================收到JSON消息===========================")
            self.logger.bind(tag=TAG).info("检测到新语音开始，取消旧任务")

            # 清理相关状态
            await self.context.output_processor.send_tts_stop_message(self.session_request_id)
            self.context.state_manager.reset_llm_task_states()
            self.context.tts_pipeline.stop_tts_pipeline_threads()

            # 发布客户端静音事件，让CancellationManager处理音频输出相关任务取消
            await self.event_bus.publish(
                Event(
                    event_type=EventTypes.SESSION_TASKS_CANCEL_REQUESTED,
                    session_id=self.context.session_id,
                    data={
                        "task_types": [
                            self.context.cancellation_manager.task_types.AUDIO_ASR_PROCESS_TASK,
                            self.context.cancellation_manager.task_types.TEXT_READ_TASK,
                            self.context.cancellation_manager.task_types.AUDIO_TTS_PROCESS_TASK,
                            self.context.cancellation_manager.task_types.AUDIO_TTS_OUTPUT_TASK,
                        ],
                    },
                )
            )

            # 重新设置新轮次请求id
            current_session_request_id = set_unique_id("test")
            self.context.state_manager.update_current_session_request_id(current_session_request_id)

        except Exception as e:
            self.logger.bind(tag=TAG).error(f"取消旧任务时出错: {e}")
