import logging
import queue
import threading
import time
import traceback
from typing import Tuple

from core.models.asr_models import ASRResponseInfo
from core.providers.asr.base import ASRProviderBase
from core.utils.audio_opus_handler import OpusDecoder
import dashscope
from dashscope.audio.asr import (
    TranscriptionResult,
    TranslationRecognizerCallback,
    TranslationRecognizerRealtime,
    TranslationResult,
)
import numpy as np

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TAG = __name__


# 服务容器所需的ASRProvider类
class ASRProvider(ASRProviderBase):
    """
    Qwen ASR Provider - 完全实现ASRProviderBase接口
    支持Opus格式输入和PCM格式处理，提供流式语音识别
    """

    def __init__(self, config: dict):
        super().__init__(config)

        self.type = config.get("type", "qwen")
        self.model_name = config.get("model_name", "qwen-unknow")
        # 设置API密钥
        dashscope.api_key = self.api_key
        if not hasattr(self, "audio_sample_rate"):
            self.audio_sample_rate = 16000
        if not hasattr(self, "audio_channels"):
            self.audio_channels = 1
        if not hasattr(self, "audio_format"):
            self.audio_format = "opus"
        if not hasattr(self, "audio_frame_duration"):
            self.audio_frame_duration = 60

        # 流式识别器相关
        self.recognizer = None
        self.result_queue = queue.Queue()
        self.is_ready = threading.Event()
        self.current_transcript = ""
        self.last_sentence_id = -1
        self.speech_ended = False

        # 音频缓冲相关
        self.audio_buffer = []
        self.is_recording = False
        self.recording_start_time = 0
        self.audio_frames_sent = 0

    def _initialize_recognizer(self):
        """初始化Qwen流式识别器"""
        if self.recognizer is not None:
            return

        callback = self._create_callback()
        self.recognizer = TranslationRecognizerRealtime(
            model=self.model_name,
            format="pcm",  # Qwen内部使用PCM格式
            sample_rate=self.audio_sample_rate,
            transcription_enabled=True,
            translation_enabled=False,
            callback=callback,
        )

        # 在后台线程启动识别器
        threading.Thread(target=self._start_recognizer, daemon=True).start()

        # 等待识别器就绪
        if not self.is_ready.wait(timeout=10):
            raise RuntimeError("Qwen识别器初始化超时")

    def _create_callback(self):
        """创建Qwen流式回调处理器"""

        class QwenCallback(TranslationRecognizerCallback):
            def __init__(self, outer_instance):
                self.outer = outer_instance

            def on_open(self) -> None:
                try:
                    self.outer.is_ready.set()
                except Exception:
                    logger.error(f"❌ 建立Qwen流式回调时出错: {traceback.format_exc()}")

            def on_close(self) -> None:
                try:
                    logger.info("❌ Qwen ASR流式连接已关闭")
                    self.outer.is_ready.clear()
                    self.outer.recognizer = None  # 清理识别器实例，以便下次重新初始化
                except Exception:
                    logger.error(f"❌ 关闭Qwen流式回调时出错: {traceback.format_exc()}")

            def on_event(
                self,
                request_id: str,
                transcription_result: TranscriptionResult,
                translation_result: TranslationResult = None,
                usage=None,
            ) -> None:
                try:
                    if transcription_result is not None:
                        transcript = transcription_result.text
                        sentence_id = transcription_result.sentence_id
                        begin_time = transcription_result.begin_time
                        end_time = transcription_result.end_time
                        is_sentence_end = transcription_result.is_sentence_end

                        # 检查是否是新的句子
                        if sentence_id != self.outer.last_sentence_id:
                            # 新句子开始
                            self.outer.current_transcript = transcript
                            self.outer.last_sentence_id = sentence_id
                            logger.debug(f"🆕 新句子 {sentence_id}: '{transcript}'")
                        else:
                            # 同一句子的更新
                            self.outer.current_transcript = transcript

                        if is_sentence_end:
                            logger.debug(f"🏁 实时语音结束:{transcript}，时长: {usage}")

                        # 将当前转录放入队列
                        result_data = {
                            "text": transcript,
                            "sentence_id": sentence_id,
                            "is_sentence_end": is_sentence_end,
                            "begin_time": begin_time,
                            "end_time": end_time,
                        }
                        self.outer.result_queue.put(result_data)

                except Exception as e:
                    logger.error(f"❌ 处理Qwen流式回调时出错: {e}")

        return QwenCallback(self)

    def _start_recognizer(self):
        """在后台线程启动识别器"""
        try:
            self.recognizer.start()
            logger.info("🚀 Qwen ASR流式识别器已启动")
        except Exception as e:
            logger.error(f"❌ 启动Qwen ASR识别器失败: {e}")
            self.is_ready.set()

    def _audio_data_to_pcm_array(self, audio_data: bytes) -> Tuple[int, np.ndarray]:
        """将Opus数据转换为PCM numpy数组格式"""
        try:
            # 初始化Opus解码器
            if not hasattr(self, "opus_decoder"):
                self.opus_decoder = OpusDecoder(sample_rate=self.audio_sample_rate, channels=self.audio_channels)

            # 解码Opus数据到PCM
            pcm_frame = audio_data

            if pcm_frame:
                # 转换为numpy数组
                audio_array = np.frombuffer(pcm_frame, dtype=np.int16)
                return self.audio_sample_rate, audio_array
            else:
                logger.warning("⚠️ 没有成功解码的音频数据")
                return self.audio_sample_rate, np.array([], dtype=np.int16)

        except Exception as e:
            logger.error(f"❌ Opus到PCM转换失败: {e}, 追踪:{traceback.format_exc()}")
            return self.audio_sample_rate, np.array([], dtype=np.int16)

    def _valid_ndarray_format(self, audio_array: np.ndarray) -> bytes:
        """将音频数组转换为标准的16位PCM小端序格式"""
        try:
            # 确保数据类型正确
            if audio_array.dtype != np.int16:
                if audio_array.dtype in [np.float32, np.float64]:
                    audio_array = (audio_array * 32767).astype(np.int16)
                elif audio_array.dtype == np.int32:
                    audio_array = (audio_array // 65536).astype(np.int16)
                else:
                    audio_array = audio_array.astype(np.int16)

            # 确保小端序
            pcm_bytes = audio_array.tobytes(order="C")
            return pcm_bytes

        except Exception as e:
            logger.error(f"❌ PCM格式转换错误: {e}")
            return b""

    def _stt(self, audio_data: Tuple[int, np.ndarray]) -> dict:
        """
        立即处理音频数据并返回流式识别结果（不等待）
        完全按照stt_model_from_qwen.py的成功模式实现
        """
        try:
            # 检查识别器是否需要重新初始化（识别器不存在或已停止）
            if not self.recognizer or not self.is_ready.is_set():
                self.recognizer = None  # 确保清理旧实例
                self._initialize_recognizer()

            sample_rate, audio_array = audio_data

            # Ensure audio is not empty
            if audio_array.size == 0:
                return ""

            # Ensure audio is 1-dimensional (mono)
            if len(audio_array.shape) > 1:
                audio_array = audio_array.flatten()

            # 音频缓冲和录音状态管理
            if not self.is_recording:
                # 开始录音
                self.is_recording = True
                self.recording_start_time = time.time()
                self.audio_buffer = [audio_array]
                logger.debug("🎙️ 开始录音，缓冲第一帧音频")
            else:
                # 继续录音，缓冲音频
                self.audio_buffer.append(audio_array)
                logger.debug(f"🎙️ 缓冲音频帧，当前缓冲: {len(self.audio_buffer)} 帧")

            # 直接转换并发送音频，不累积
            pcm_bytes = self._valid_ndarray_format(audio_array)

            if len(pcm_bytes) > 0:
                # 发送前再次检查识别器状态，防止竞争条件
                if self.recognizer and self.is_ready.is_set():
                    try:
                        self.recognizer.send_audio_frame(pcm_bytes)
                        self.audio_frames_sent += 1
                        logger.debug(f"📤 Sent audio frame: {len(pcm_bytes)} bytes")
                    except Exception as send_err:
                        # 识别器内部已停止但on_close回调尚未触发，强制重置
                        logger.warning(f"⚠️ 发送音频帧失败，重置识别器: {send_err}")
                        self.recognizer = None
                        self.is_ready.clear()
                        # 立即重新初始化并发送当前帧
                        self._initialize_recognizer()
                        if self.recognizer and self.is_ready.is_set():
                            self.recognizer.send_audio_frame(pcm_bytes)
                            self.audio_frames_sent += 1
                else:
                    logger.warning("⚠️ 识别器未就绪，跳过发送音频帧")

            # 检查是否有流式结果（只获取非最终结果）
            streaming_results = []
            final_results = []
            try:
                while True:
                    result = self.result_queue.get_nowait()
                    if result is not None:
                        if result["is_sentence_end"]:
                            final_results.append(result)
                        else:
                            streaming_results.append(result)
            except queue.Empty:
                pass

            # 将最终结果放回队列
            for final_result in final_results:
                self.result_queue.put(final_result)

            # 返回最新的流式结果
            if streaming_results:
                # return streaming_results[-1]["text"]
                return streaming_results[-1]

            return ""

        except Exception:
            logger.error(f"❌ 处理音频数据失败: {traceback.format_exc()}")
            return ""

    def is_support_stream_mode(self) -> bool:
        """
        QwenASR支持流式处理模式
        """
        return True

    async def speech_to_text(self, audio_data) -> ASRResponseInfo:
        """将Opus音频数据转换为文本 - 支持流式和非流式模式

        Args:
            audio_data: Opus音频数据
        """
        try:
            stream_mode = self.is_support_stream_mode()
            if stream_mode:
                # 流式模式：直接使用stt方法，它已经包含流式处理逻辑
                # 转换Opus到PCM
                sample_rate, audio_array = self._audio_data_to_pcm_array(audio_data)

                if audio_array.size == 0:
                    return ASRResponseInfo(text="", is_final=True, provider_name="qwen")

                # 直接使用stt方法，它会返回流式结果
                transcription_dict = self._stt((sample_rate, audio_array))

                # 如果是流式结果，则返回最后一个结果
                if isinstance(transcription_dict, dict) and transcription_dict:
                    return ASRResponseInfo(
                        text=transcription_dict.get("text", ""),
                        is_final=transcription_dict.get("is_sentence_end", False),
                        sentence_id=transcription_dict.get("sentence_id"),
                        begin_time=transcription_dict.get("begin_time"),
                        end_time=transcription_dict.get("end_time"),
                        provider_name=self.model_name,
                    )
                else:
                    return ASRResponseInfo(text="", is_final=True, provider_name=self.model_name)

        except Exception as e:
            logger.error(f"❌ Opus语音识别失败: {e}")
            return ASRResponseInfo(text="", is_final=True, provider_name=self.model_name)

    def close(self):
        """Close recognizer and release resources"""
        try:
            if self.recognizer is not None:
                self.recognizer.stop()
                self.recognizer = None
                logger.info(f"🔄 Closing Qwen streaming recognizer (sent {self.audio_frames_sent} frames)")

            # 清理Opus解码器
            if hasattr(self, "_opus_decoder"):
                self._opus_decoder = None
                logger.info("🔄 Opus解码器已清理")

            # 重置所有状态，确保下次启动时干净
            self.is_ready.clear()
            self.is_recording = False
            self.audio_buffer = []
            self.audio_frames_sent = 0

            logger.info("🔄 Qwen ASR状态已完全重置")
        except Exception as e:
            logger.error(f"❌ Qwen语音识别关闭失败: {e}")
            # 即使关闭失败，也要重置状态以避免下次启动冲突
            self.recognizer = None
            if hasattr(self, "_opus_decoder"):
                self._opus_decoder = None
            self.is_ready.clear()
            self.is_recording = False
