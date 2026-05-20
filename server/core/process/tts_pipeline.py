import asyncio
import os
import queue
import threading
import time
import traceback
from typing import TYPE_CHECKING, List

from core.models.message_models import AudioPlaybackStatus, PlaybackState, Transport
from core.providers.tts.base import TtsAudioResponseData
from core.utils.audio_opus_handler import OpusEncoder
from core.utils.audio_pcm_handler import PcmHandler
import numpy as np

if TYPE_CHECKING:
    from core.session.session_context import SessionContext

TAG = __name__


class TtsPipeline:
    """
    TTS音频处理管道 - 核心音频管理和处理组件

    设计模式:
        - 生产者-消费者模式：异步队列处理TTS文本和音频数据
        - 策略模式：根据传输类型选择不同的音频处理策略
        - 观察者模式：通过事件系统监听任务状态变化
        - 工厂模式：创建不同格式的音频编码器

    主要功能:
        - TTS文本转语音处理管道，支持流式音频生成和播放
        - 多格式音频传输支持（WebSocket/Opus、WebRTC/PCM）
        - 异步任务管理和音频队列处理
        - WebSocket传输：Opus包生成后立即发送，零延迟
        - WebRTC传输：保持原有的分帧发送机制
        - 音频文件保存和状态管理

    组件关系:
        - 依赖SessionContext获取TTS服务、状态管理器等
        - 与OutputProcessor协作发送不同格式的音频数据
        - 通过StateManager管理音频播放状态和任务跟踪
        - 使用CancellationManager实现任务取消和资源清理

    注意事项:
        - 所有音频处理方法都是异步的，需要在协程环境中使用
        - 支持WebSocket(Opus编码)和WebRTC(PCM格式)两种传输方式
        - WebSocket传输已取消缓冲机制，每个Opus包立即发送
        - WebRTC音频分帧按20ms每帧进行发送，确保实时性
        - 需要正确处理任务取消和资源清理
    """

    def __init__(self, context: "SessionContext"):
        """
        初始化音频处理管道

        :param context: 会话上下文，提供TTS服务、日志记录器等依赖
        """
        self.context = context  # 会话上下文，提供全局服务访问
        self.logger = context.logger  # 日志记录器
        self.pcm_handler = PcmHandler()  # PCM音频处理器
        self.session_request_id = ""  # 当前会话请求ID
        self.state_manager = context.state_manager

        # 音频处理队列
        self.audio_tts_queue = self.state_manager.audio_tts_queue  # TTS文本处理队列（线程安全）
        self.audio_play_queue = self.state_manager.audio_play_queue  # 音频播放队列（线程安全）

        # 异步任务管理
        self.tts_send_thread = None  # TTS文本发送线程
        self.tts_send_loop = None  # TTS线程中的事件循环
        self.audio_send_thread = None  # 音频发送线程
        self.audio_send_loop = None  # 音频线程中的事件循环
        self.tts_thread_stop_event = threading.Event()  # TTS线程停止事件
        self.audio_thread_stop_event = threading.Event()  # 音频线程停止事件
        self.tts_tasks_stop = self.state_manager.tts_tasks_stop

        # WebSocket(Opus)编码器配置
        self.tts_encode_opus_sample_rate = 16000
        self.tts_encode_opus_channels = 1
        self.opus_encoder = OpusEncoder(
            sample_rate=self.tts_encode_opus_sample_rate, channels=self.tts_encode_opus_channels
        )  # Opus编码器
        self.tts_pcm_saved_buffer = []  # PCM音频数据保存缓冲区，存储 (pcm_bytes, sample_rate) 元组
        self.tts_pcm_saved_sample_rate = 16000

        # WebRTC(PCM)相关缓冲区
        self.tts_webrtc_playback_buffer: List[tuple] = []  # WebRTC音频播放缓冲区
        self.webrtc_tts_audio_output_queue = self.state_manager.webrtc_tts_audio_output_queue
        self.webrtc_buffer_trigger_count = 3  # WebRTC缓冲区触发发送的阈值

    def start_tts_pipeline_threads(self):
        """
        启动所有音频处理线程

        检查并启动TTS文本发送线程和音频发送线程，
        确保在任务完成或取消后能够重新启动。
        """
        # 开启TTS任务状态
        self.state_manager.update_state(tts_tasks_stop=False)

        # 检查并启动TTS文本发送线程
        if self.tts_send_thread:
            if not self.tts_send_thread.is_alive():
                self.logger.bind(tag=TAG).info("tts_send_thread已停止，需要重新启动")
                self._start_tts_send_thread()
            else:
                self.logger.bind(tag=TAG).debug("tts_send_thread运行正常")
        else:
            self.logger.bind(tag=TAG).info("tts_send_thread不存在，创建新线程")
            self._start_tts_send_thread()

        # 检查并启动音频发送线程
        if self.audio_send_thread:
            if not self.audio_send_thread.is_alive():
                self.logger.bind(tag=TAG).info("audio_send_thread已停止，需要重新启动")
                self._start_audio_send_thread()
            else:
                self.logger.bind(tag=TAG).debug("audio_send_thread运行正常")
        else:
            self.logger.bind(tag=TAG).info("audio_send_thread不存在，创建新线程")
            self._start_audio_send_thread()

    def _start_tts_send_thread(self):
        """
        启动TTS文本发送线程

        在独立线程中创建新的事件循环并运行TTS发送循环。
        """
        # 重置停止事件
        self.tts_thread_stop_event.clear()

        # 创建并启动线程
        self.tts_send_thread = threading.Thread(
            target=self._run_tts_send_loop_in_thread,
            name=f"TtsSendThread-{self.context.session_id}",
            daemon=True,
        )
        self.tts_send_thread.start()
        self.logger.bind(tag=TAG).info("TTS发送线程已启动")

    def _run_tts_send_loop_in_thread(self):
        """
        在独立线程中运行TTS发送循环

        创建新的事件循环并在其中运行TTS发送循环，
        直到收到停止信号。
        """
        # 创建新的事件循环
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        self.tts_send_loop = loop

        try:
            # 在新循环中运行TTS发送循环
            until_complete = loop.create_task(self._tts_send_loop())
            loop.run_until_complete(until_complete)
        except Exception as e:
            self.logger.bind(tag=TAG).error(f"TTS发送线程异常: {e}")
        finally:
            # 清理事件循环
            pending = asyncio.all_tasks(loop)
            for task in pending:
                task.cancel()
            if pending:
                loop.run_until_complete(asyncio.gather(*pending, return_exceptions=True))
            loop.close()
            self.logger.bind(tag=TAG).info("TTS发送线程已退出")

    def _start_audio_send_thread(self):
        """
        启动音频发送线程

        在独立线程中创建新的事件循环并运行音频发送循环。
        """
        # 创建并启动线程
        self.audio_send_thread = threading.Thread(
            target=self._run_audio_send_loop_in_thread,
            name=f"AudioSendThread-{self.context.session_id}",
            daemon=True,
        )
        self.audio_send_thread.start()
        self.logger.bind(tag=TAG).info("音频发送线程已启动")

    def _run_audio_send_loop_in_thread(self):
        """
        在独立线程中运行音频发送循环

        创建新的事件循环并在其中运行音频发送循环，
        直到收到停止信号。
        """
        # 创建新的事件循环
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        self.audio_send_loop = loop

        try:
            # 在新循环中运行音频发送循环
            until_complete = loop.create_task(self._audio_send_loop())
            loop.run_until_complete(until_complete)
        except Exception as e:
            self.logger.bind(tag=TAG).error(f"音频发送线程异常: {e}")
        finally:
            # 清理事件循环
            pending = asyncio.all_tasks(loop)
            for task in pending:
                task.cancel()
            if pending:
                loop.run_until_complete(asyncio.gather(*pending, return_exceptions=True))
            loop.close()
            self.logger.bind(tag=TAG).info("音频发送线程已退出")

    def stop_tts_pipeline_threads(self):
        """
        停止TTS管道线程

        工作原理：
        1. 设置停止事件标志（循环会检查并退出）
        2. 发送队列停止信号（辅助作用，让循环快速退出）
        3. 等待线程结束（给清理代码足够时间）
        4. 清理事件循环（确保所有异步任务被取消）
        5. 清理所有引用
        6. CancellationManager 会处理任务取消
        7. daemon=True 保证最终清理
        """
        try:
            # 开启TTS任务状态
            self.state_manager.update_state(tts_tasks_stop=True)

            # 1. 设置停止事件标志（循环会检查并退出）
            self.tts_thread_stop_event.set()
            self.audio_thread_stop_event.set()

            # 2. 发送队列停止信号（辅助作用，让循环快速退出）
            self.audio_tts_queue.put(None)
            self.audio_play_queue.put(None)

            # 2.5. 在线程的事件循环中主动关闭 TTS 连接
            # 这解决了 WebSocket 连接属于不同事件循环导致的关闭失败问题
            if self.tts_send_loop and not self.tts_send_loop.is_closed():
                try:
                    # 使用 run_coroutine_threadsafe 将关闭操作调度到正确的事件循环
                    close_future = asyncio.run_coroutine_threadsafe(
                        self._close_tts_connections_in_loop(), self.tts_send_loop
                    )
                    # 等待关闭完成（设置超时避免死锁）
                    close_future.result(timeout=0.1)
                except Exception as e:
                    self.logger.bind(tag=TAG).warning(f"在线程事件循环中关闭TTS连接失败: {e}")

            # 3. 等待线程结束（增加到5秒超时，给清理代码足够时间）
            if self.tts_send_thread and self.tts_send_thread.is_alive():
                self.tts_send_thread.join(timeout=0.1)
                if self.tts_send_thread.is_alive():
                    self.logger.bind(tag=TAG).warning("TTS发送线程在5秒后仍未停止")

            if self.audio_send_thread and self.audio_send_thread.is_alive():
                self.audio_send_thread.join(timeout=0.1)
                if self.audio_send_thread.is_alive():
                    self.logger.bind(tag=TAG).warning("音频发送线程在5秒后仍未停止")

            # 4. 清理事件循环（确保所有异步任务被取消）
            if self.tts_send_loop and not self.tts_send_loop.is_closed():
                pending = asyncio.all_tasks(self.tts_send_loop)
                if pending:
                    self.logger.bind(tag=TAG).debug(f"取消TTS发送循环中的{len(pending)}个任务")
                # 使用线程安全方法取消任务
                self._cancel_tasks_in_loop_safely(self.tts_send_loop)
                self.tts_send_loop.close()

            if self.audio_send_loop and not self.audio_send_loop.is_closed():
                pending = asyncio.all_tasks(self.audio_send_loop)
                if pending:
                    self.logger.bind(tag=TAG).debug(f"取消音频发送循环中的{len(pending)}个任务")
                # 使用线程安全方法取消任务
                self._cancel_tasks_in_loop_safely(self.audio_send_loop)
                self.audio_send_loop.close()

            # 5. 清理所有引用（无论线程是否停止）
            self.tts_send_thread = None
            self.tts_send_loop = None
            self.audio_send_thread = None
            self.audio_send_loop = None

            # 6. 清理队列和状态
            self.clear_audio_tts_queue()
            self.clear_audio_play_queue()

            # 7. 重置停止事件（为下次启动做准备）
            self.tts_thread_stop_event.clear()
            self.audio_thread_stop_event.clear()

            self.logger.bind(tag=TAG).info("TTS管道线程停止完成")

        except Exception:
            self.logger.bind(tag=TAG).error(f"停止线程异常: {traceback.format_exc()}")

    def _cancel_tasks_in_loop_safely(self, loop: asyncio.AbstractEventLoop, timeout: float = 1.0):
        """
        安全地取消事件循环中的所有任务

        使用 run_coroutine_threadsafe 从其他线程安全地操作事件循环，
        解决跨线程调用 run_until_complete 导致的 RuntimeError 问题。

        Args:
            loop: 目标事件循环
            timeout: 等待超时时间（秒）
        """
        if not loop or loop.is_closed():
            return

        async def _cancel_and_wait():
            pending = asyncio.all_tasks(loop)
            if pending:
                for task in pending:
                    task.cancel()
                # 等待所有任务取消完成
                await asyncio.gather(*pending, return_exceptions=True)

        # 使用 run_coroutine_threadsafe 跨线程安全执行
        future = asyncio.run_coroutine_threadsafe(_cancel_and_wait(), loop)
        try:
            future.result(timeout=timeout)
        except Exception as e:
            self.logger.bind(tag=TAG).warning(f"取消任务超时或失败: {e}")

    async def _close_tts_connections_in_loop(self):
        """
        在当前事件循环中关闭所有 TTS 连接

        此方法在线程的事件循环中被调用，确保 WebSocket 连接
        在创建它们的事件循环中被关闭，避免事件循环不匹配错误。

        该方法通过 asyncio.run_coroutine_threadsafe() 从 stop_tts_pipeline_threads()
        调度到正确的事件循环中执行。
        """
        try:
            if self.context and self.context.tts:
                await self.context.tts.close()
                self.logger.bind(tag=TAG).debug("TTS连接已关闭")
            else:
                self.logger.bind(tag=TAG).debug("TTS服务或上下文不可用，跳过关闭")
        except Exception as e:
            self.logger.bind(tag=TAG).error(f"关闭TTS连接异常: {e}")

    async def _tts_send_loop(self):
        """
        TTS文本发送循环处理

        持续从TTS文本队列中获取任务数据，调用TTS服务进行语音合成，
        支持任务取消和异常处理。当收到None数据时停止循环。
        """

        try:
            while not self.tts_thread_stop_event.is_set():
                # 检查是否停止tts任务
                if self.tts_tasks_stop:
                    self.logger.bind(tag=TAG).debug("收到停止信号，触发取消异常")
                    raise asyncio.CancelledError
                try:
                    text_data = self.audio_tts_queue.get_nowait()
                except queue.Empty:
                    await asyncio.sleep(0.001)
                    continue

                # 接收None退出异步循环
                if text_data is None:
                    break

                # 解析TTS文本数据。由于流式输出文本结束文本会发送空文本标识，这里不做非空校验。
                text, text_index, is_text_end = text_data
                # 第一个文本片段时，初始化TTS连接和处理管道
                if text_index == 1:
                    # 发送TTS开始状态消息
                    await self.context.output_processor.send_tts_state_message(
                        state=PlaybackState.START, session_request_id=self.session_request_id
                    )

                try:
                    # 创建TTS任务
                    task = asyncio.create_task(
                        self.context.tts.text_to_speech(
                            client_id=self.session_request_id,
                            text=text,
                            text_index=text_index,
                            is_text_end=is_text_end,
                            audio_queue=self.audio_play_queue,
                        )
                    )

                    # 等待TTS任务完成
                    await task
                    self.logger.bind(tag=TAG).info(f"TTS任务完成[{text_index}]: {text}-{self.session_request_id}")

                except asyncio.CancelledError:
                    self.logger.bind(tag=TAG).info("TTS任务被取消")
                    self.clear_audio_tts_queue()
                    break
                except Exception:
                    raise

        except Exception:
            self.logger.bind(tag=TAG).error(f"TTS发送循环出错: {traceback.format_exc()}")
            self.clear_audio_tts_queue()

    async def _audio_send_loop(self):
        """
        TTS音频流循环发送处理

        从音频播放队列中获取PCM音频数据，根据传输类型进行相应处理：
        - WebRTC: 将PCM数据分帧发送
        - WebSocket: 将PCM数据编码为Opus格式后发送

        支持音频缓冲、任务取消和资源清理。
        """

        try:
            while not self.audio_thread_stop_event.is_set():
                try:
                    if self.state_manager.tts_tasks_stop:
                        raise asyncio.CancelledError

                    # 从播放队列获取音频数据
                    try:
                        tts_playback_data = self.audio_play_queue.get_nowait()
                    except queue.Empty:
                        await asyncio.sleep(0.001)
                        continue

                    # 处理音频流数据
                    if isinstance(tts_playback_data, TtsAudioResponseData):
                        pcm_sample_rate = tts_playback_data.pcm_sample_rate
                        pcm_bytes = tts_playback_data.pcm_bytes
                        pcm_is_complete = tts_playback_data.pcm_is_complete
                        text_index = tts_playback_data.text_index  # tts文本序号

                        # 保存原始PCM数据用于文件保存
                        self.tts_pcm_saved_buffer.append((pcm_bytes, pcm_sample_rate))

                        # 根据传输类型选择处理方式
                        transport_type = self.context.state_manager.input_audio_transport_type
                        if transport_type == Transport.WEBRTC:
                            # WebRTC传输：保存TtsAudioResponseData对象用于批量处理
                            self.tts_webrtc_playback_buffer.append((tts_playback_data, text_index))
                            buffer_size = len(self.tts_webrtc_playback_buffer)

                            # 缓冲区达到阈值时发送
                            if buffer_size >= self.webrtc_buffer_trigger_count:
                                await self._send_webrtc_buffered_audio()

                            # 完整片段的最后数据时，强制发送缓冲区
                            if pcm_is_complete:
                                await self._send_webrtc_buffered_audio(flush=True)
                                self._check_and_send_tts_end_signal(text_index)

                        elif transport_type == Transport.WEBSOCKET:
                            # WebSocket传输：转换到16kHz后编码为Opus格式，立即发送
                            converted_pcm = self.pcm_handler.convert_pcm_format(
                                pcm_bytes, from_rate=pcm_sample_rate, to_rate=16000
                            )
                            opus_packets = self.opus_encoder.encode_pcm_stream(converted_pcm)

                            # 立即发送每个Opus包（无缓冲延迟）
                            for packet in opus_packets:
                                # await self.context.output_processor.send_opus_message(
                                #     audios=packet,
                                #     text_index=text_index,
                                #     session_request_id=self.session_request_id,
                                # )
                                future = asyncio.run_coroutine_threadsafe(
                                    self.context.output_processor.send_opus_message(
                                        audios=packet,
                                        text_index=text_index,
                                        session_request_id=self.session_request_id,
                                    ),
                                    self.context.loop,
                                )
                                future.result()

                            # 完整片段结束时，flush编码器并发送剩余包
                            if pcm_is_complete:
                                remaining_packets = self.opus_encoder.flush_pcm_stream()
                                for packet in remaining_packets:
                                    # await self.context.output_processor.send_opus_message(
                                    #     audios=packet,
                                    #     text_index=text_index,
                                    #     session_request_id=self.session_request_id,
                                    # )
                                    future = asyncio.run_coroutine_threadsafe(
                                        self.context.output_processor.send_opus_message(
                                            audios=packet,
                                            text_index=text_index,
                                            session_request_id=self.session_request_id,
                                        ),
                                        self.context.loop,
                                    )
                                    future.result()
                                self._check_and_send_tts_end_signal(text_index)

                    elif tts_playback_data is None:
                        # 收到停止信号
                        break

                except asyncio.CancelledError:
                    self.logger.bind(tag=TAG).info(f"TTS音频发送任务取消:{self.session_request_id}")
                    # 任务被取消时的清理工作
                    if len(self.tts_pcm_saved_buffer) > 0:
                        await self._save_pcm_to_wav_async()  # 保存未处理的PCM数据
                    self.clear_audio_play_queue()  # 清理播放队列（同步）
                    break

        except Exception:
            self.logger.bind(tag=TAG).error(f"音频发送循环出错: {traceback.format_exc()}")
            self.clear_audio_play_queue()
            self.logger.bind(tag=TAG).info(f"TTS发送循环结束，清理队列audio_play_queue:{self.audio_play_queue.qsize()}")

    async def _send_webrtc_buffered_audio(self, flush: bool = False):
        """
        发送WebRTC缓冲音频数据

        批量处理累积的PCM音频数据，统一转换为16kHz后分帧发送。

        :param flush: 是否强制发送缓冲区所有数据，为True时忽略触发阈值
        """
        try:
            # 检查缓冲区是否有数据
            if not self.tts_webrtc_playback_buffer:
                self.logger.bind(tag=TAG).warning("_send_webrtc_buffered_audio: 缓冲区为空，跳过发送")
                return

            # 计算本次发送的数据量
            send_count = len(self.tts_webrtc_playback_buffer) if flush else self.webrtc_buffer_trigger_count
            send_count = min(send_count, len(self.tts_webrtc_playback_buffer))

            # 收集需要处理的音频数据和采样率信息
            audio_chunks = []
            sample_rates = set()

            for audio_data, _ in self.tts_webrtc_playback_buffer[:send_count]:
                # audio_data 是 TtsAudioResponseData 对象
                audio_chunks.append(audio_data.pcm_bytes)
                sample_rates.add(audio_data.pcm_sample_rate)

            # 合并PCM数据块
            combined_pcm = b"".join(audio_chunks)

            # 使用 PcmHandler 批量转换到16kHz
            source_rate = sample_rates.pop()
            converted_pcm = self.pcm_handler.convert_pcm_format(combined_pcm, from_rate=source_rate, to_rate=16000)

            # 转换为numpy数组进行分帧处理
            audio_array = np.frombuffer(converted_pcm, dtype=np.int16)

            # 按目标采样率分帧发送
            await self._send_audio_in_frames(audio_array, sample_rate=16000)

            # 移除已发送的数据
            self.tts_webrtc_playback_buffer = self.tts_webrtc_playback_buffer[send_count:]

        except Exception:
            self.logger.bind(tag=TAG).error(f"WebRTC分帧音频发送失败: {traceback.format_exc()}")
            raise

    async def _send_audio_in_frames(self, audio_array: np.ndarray, sample_rate: int = 16000):
        """
        将音频数据按固定时间间隔分帧发送

        将音频数据分割为20ms大小的帧，并按实际时间间隔发送，
        确保音频播放的实时性和同步性。

        :param audio_array: 音频数据numpy数组，数据类型为int16
        :param sample_rate: 音频采样率，目前仅支持16000Hz
        """
        try:
            # 音频分帧参数
            frame_duration_ms = 20  # 每帧20毫秒
            frame_size_samples = int(sample_rate * frame_duration_ms / 1000)  # 每帧采样点数320

            # 计算总帧数
            total_frames = (len(audio_array) + frame_size_samples - 1) // frame_size_samples
            sent_frames = 0

            # 记录开始发送时间，用于计算发送速度
            start_send_time = time.time()

            # 获取当前任务用于取消检查
            current_task = asyncio.current_task()

            # 发送所有帧，保持20ms间隔
            # 这样确保emit()首次调用时队列已有数据，同时保持正确的帧间隔
            for frame_index in range(total_frames):
                # 检查任务是否已被取消
                if current_task and current_task.cancelled():
                    break

                # 计算当前帧的采样点范围
                start_sample = frame_index * frame_size_samples
                end_sample = min(start_sample + frame_size_samples, len(audio_array))

                # 提取当前帧音频数据
                frame_audio = audio_array[start_sample:end_sample]

                # 最后一帧长度不足时进行零填充
                if len(frame_audio) < frame_size_samples:
                    padding_size = frame_size_samples - len(frame_audio)
                    frame_audio = np.pad(frame_audio, (0, padding_size), mode="constant", constant_values=0)
                else:
                    pass

                # 发送当前帧音频数据
                asyncio.run_coroutine_threadsafe(
                    self.context.output_processor.send_webrtc_audio(
                        sample_rate=sample_rate,
                        audio_array=frame_audio,
                        session_request_id=self.session_request_id,
                        array_index=frame_index,
                    ),
                    self.context.loop,
                )
                # await self.context.output_processor.send_webrtc_audio(
                #     sample_rate=sample_rate,
                #     audio_array=frame_audio,
                #     session_request_id=self.session_request_id,
                #     array_index=frame_index,
                # )

                sent_frames += 1
                # 确保帧间隔
                await asyncio.sleep(frame_duration_ms / 1000)

            # 计算实际发送耗时
            send_duration = time.time() - start_send_time
            self.logger.bind(tag=TAG).info(
                f"WebRTC音频分帧发送完成: {sent_frames}帧, 总时长={len(audio_array) / sample_rate:.2f}秒, "
                f"实际发送耗时={send_duration:.3f}秒, 发送速率={sent_frames / send_duration:.1f}帧/秒"
            )

        except Exception:
            self.logger.bind(tag=TAG).error(f"音频分帧发送失败: {traceback.format_exc()}")
            raise

    def _check_and_send_tts_end_signal(self, text_index) -> bool:
        """
        检查并发送TTS结束信号

        当LLM任务完成、所有音频处理队列为空且当前文本索引为最后一个时，
        发送TTS结束状态信号并保存音频文件。

        :param text_index: 当前处理的文本索引
        :return: 是否发送了结束信号
        """
        try:
            # 获取状态管理器中的任务完成信息
            if self.context.state_manager:
                llm_finish_task = self.context.state_manager.llm_finish_task
                llm_last_text_index = self.context.state_manager.llm_last_text_index

            # 检查队列状态
            is_tts_queue_empty = self.audio_tts_queue.empty()
            is_audio_queue_empty = self.audio_play_queue.empty()

            # 判断是否满足TTS结束条件
            if llm_finish_task and llm_last_text_index == text_index and is_tts_queue_empty and is_audio_queue_empty:
                self.logger.bind(tag=TAG).info(f"所有TTS任务已完成 (最后音频索引: {text_index})，发送TTS_STATE_END信号")

                # 异步保存PCM数据为WAV文件
                if self.tts_pcm_saved_buffer:
                    asyncio.create_task(self._save_pcm_to_wav_async())

                # 线程安全地发送TTS结束状态消息
                asyncio.run_coroutine_threadsafe(
                    self.context.output_processor.send_tts_state_message(
                        state=AudioPlaybackStatus.STATE_END, session_request_id=self.session_request_id
                    ),
                    self.context.loop,
                )

                return True
            else:
                # 记录调试信息，说明TTS任务未完成的原因
                self.logger.bind(tag=TAG).debug(
                    f"TTS任务未完成 (llm_finish_task: {llm_finish_task}, llm_last_text_index: {llm_last_text_index}, text_index: {text_index}, tts_queue_empty: {is_tts_queue_empty}, audio_queue_empty: {is_audio_queue_empty})"
                )
                return False

        except Exception as e:
            self.logger.bind(tag=TAG).error(f"检查TTS结束状态异常: {e}", exc_info=True)

    def clear_audio_tts_queue(self):
        """
        清理TTS文本处理队列（同步方法）

        安全地清空TTS文本队列，释放队列资源，
        确保在任务取消或重启时不会积累未处理的任务。
        """
        try:
            # 循环清空队列中的所有任务
            while not self.audio_tts_queue.empty():
                try:
                    self.audio_tts_queue.get_nowait()
                    self.audio_tts_queue.task_done()
                except Exception:
                    break
        except Exception:
            self.logger.bind(tag=TAG).error(f"清理TTS转录队列失败: {traceback.format_exc()}")

    def clear_audio_play_queue(self):
        """
        清理音频播放队列和相关缓冲区（同步方法）

        清空音频播放队列以及WebRTC缓冲区，
        释放音频处理资源，确保在任务取消时正确清理。
        注意：WebSocket传输已取消缓冲机制，无需清理Opus缓冲区。
        """
        try:
            # 清空音频播放队列
            while not self.audio_play_queue.empty():
                try:
                    self.audio_play_queue.get_nowait()
                    self.audio_play_queue.task_done()
                except Exception:
                    # 如果获取任务失败，跳出循环避免无限等待
                    break
            # 清空WebRTC音频缓冲区（WebSocket传输已取消缓冲，无需清理）
            self.tts_webrtc_playback_buffer.clear()
            while not self.webrtc_tts_audio_output_queue.empty():
                try:
                    self.webrtc_tts_audio_output_queue.get_nowait()
                    self.webrtc_tts_audio_output_queue.task_done()
                except queue.Empty:
                    break

        except Exception:
            self.logger.bind(tag=TAG).error(f"清理TTS播放队列失败: {traceback.format_exc()}")

    async def _save_pcm_to_wav_async(self) -> None:
        """
        异步保存PCM数据为WAV文件

        将缓存的PCM音频数据（可能包含不同采样率）统一转换为16kHz后
        保存为WAV格式的音频文件，用于音频回放、调试和质量分析。
        文件名包含时间戳、模型名称和会话ID以便于管理和追踪。

        :return: 无返回值
        """
        try:
            # 复制并清空PCM缓冲区
            pcm_buffer_to_save = self.tts_pcm_saved_buffer.copy()
            self.tts_pcm_saved_buffer.clear()

            # 转换并合并所有PCM数据为统一的16kHz
            converted_chunks = []
            for pcm_data, sample_rate in pcm_buffer_to_save:
                # 如果已经是16kHz，直接使用
                if sample_rate == self.tts_pcm_saved_sample_rate:
                    converted_chunks.append(pcm_data)
                else:
                    # 转换为16kHz
                    converted = self.pcm_handler.convert_pcm_format(
                        pcm_data, from_rate=sample_rate, to_rate=self.tts_pcm_saved_sample_rate
                    )
                    if converted:
                        converted_chunks.append(converted)

            # 合并所有转换后的数据
            complete_pcm_data = b"".join(converted_chunks)

            # 如果没有数据，跳过保存
            if not complete_pcm_data:
                self.logger.bind(tag=TAG).debug("转换后无有效PCM数据，跳过WAV保存")
                return

            # 生成文件名：包含时间戳、模型名和会话ID
            timestamp = int(time.time())
            model_name = getattr(self.context.tts, "model_name", "unknown")
            filename = f"tts_{timestamp}_{model_name}_{self.session_request_id}.wav"

            # 获取会话目录，在会话目录下创建 tts 子目录
            if self.context.client_session_dir:
                tts_output_dir = os.path.join(self.context.client_session_dir, "tts")
                os.makedirs(tts_output_dir, exist_ok=True)
                # 构建完整的文件路径
                saved_path = os.path.join(tts_output_dir, filename)
                # 保存PCM数据为WAV文件（16kHz）
                self.pcm_handler.save_pcm_to_file(complete_pcm_data, saved_path)
            else:
                # 无会话目录时跳过保存
                self.logger.bind(tag=TAG).debug(f"无会话目录，跳过TTS音频保存 (会话: {self.session_request_id})")
                return

            # 统计信息
            original_total = sum(len(pcm) for pcm, _ in pcm_buffer_to_save)
            conversion_ratio = len(complete_pcm_data) / original_total if original_total > 0 else 0

            self.logger.bind(tag=TAG).info(
                f"TTS音频已保存为WAV文件: {saved_path} "
                f"(原始: {original_total} bytes, 转换后: {len(complete_pcm_data)} bytes, "
                f"压缩比: {conversion_ratio:.2f}, 会话: {self.session_request_id})"
            )

        except Exception:
            self.logger.bind(tag=TAG).error(f"异步保WAV文件失败{self.session_request_id}): {traceback.format_exc()}")
