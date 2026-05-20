import os
import traceback
import wave
from typing import Optional

from config.logger import setup_logging
import librosa
import numpy as np
from pydub import AudioSegment

try:
    import av
except ImportError:
    av = None

TAG = __name__
logger = setup_logging()


class PcmHandler:
    def __init__(self, sample_rate=16000, channels=1, sample_width=2):
        self.sample_rate = sample_rate
        self.channels = channels
        self.sample_width = sample_width
        # 缓存 PyAV AudioResampler 实例
        self._resampler = None
        self._last_from_rate = None
        self._last_to_rate = None

    def encode(self, pcm_chunk: bytes) -> bytes:
        return pcm_chunk

    def _get_resampler(self, from_rate: int, to_rate: int) -> Optional["av.AudioResampler"]:
        """获取或创建重采样器（缓存复用）"""
        if av is None:
            return None

        if self._resampler is None or self._last_from_rate != from_rate or self._last_to_rate != to_rate:
            self._resampler = av.AudioResampler(format="s16", layout="mono", rate=to_rate)
            self._last_from_rate = from_rate
            self._last_to_rate = to_rate

        return self._resampler

    def convert_pcm_format(self, pcm_data: bytes, from_rate: int = 24000, to_rate: int = 16000) -> bytes:
        """
        使用 PyAV 进行高性能音频重采样

        Args:
            pcm_data: PCM格式的音频数据（16位）
            from_rate: 源采样率
            to_rate: 目标采样率

        Returns:
            bytes: 转换后的PCM数据（16位）
        """
        try:
            # 如果采样率相同，直接返回
            if from_rate == to_rate:
                return pcm_data

            # 检查输入数据是否为空
            if not pcm_data:
                logger.bind(tag=TAG).warning("输入PCM数据为空")
                return b""

            # 从字节数据创建 numpy 数组
            samples = np.frombuffer(pcm_data, dtype=np.int16)

            # 检查样本数量
            if len(samples) == 0:
                logger.bind(tag=TAG).warning("PCM数据无有效样本")
                return b""

            # 创建 PyAV AudioFrame
            try:
                frame = av.AudioFrame.from_ndarray(samples.reshape(1, -1), format="s16", layout="mono")
                frame.sample_rate = from_rate
            except Exception as e:
                logger.bind(tag=TAG).error(f"创建AudioFrame失败: {e}")
                raise

            # 获取或创建重采样器
            resampler = self._get_resampler(from_rate, to_rate)
            if resampler is None:
                logger.bind(tag=TAG).error("无法创建重采样器")
                raise RuntimeError("PyAV 不可用，无法进行音频重采样")

            # 执行重采样
            try:
                resampled_frames = list(resampler.resample(frame))
            except Exception as e:
                logger.bind(tag=TAG).error(f"重采样失败: {e}")
                raise

            if resampled_frames:
                # 合并所有重采样后的帧
                try:
                    output_samples = np.concatenate([f.to_ndarray()[0] for f in resampled_frames])
                    return output_samples.astype(np.int16).tobytes()
                except Exception as e:
                    logger.bind(tag=TAG).error(f"合并重采样帧失败: {e}")
                    raise

            # 重采样返回空帧的详细日志
            logger.bind(tag=TAG).warning(
                f"重采样返回空帧 - 输入: {len(samples)}样本, "
                f"源采样率: {from_rate}Hz, 目标采样率: {to_rate}Hz"
            )

            return b""

        except Exception:
            logger.bind(tag=TAG).error(f"音频重采样失败: {traceback.format_exc()}")
            raise

    def save_pcm_to_file(self, pcm_data: bytes, output_path: str) -> None:
        """
        保存PCM数据为WAV文件

        Args:
            pcm_data: PCM音频数据
            output_path: 输出文件路径
        """
        try:
            with wave.open(output_path, "wb") as wf:
                wf.setnchannels(self.channels)
                wf.setsampwidth(self.sample_width)
                wf.setframerate(self.sample_rate)
                wf.writeframes(pcm_data)
        except Exception as e:
            logger.bind(tag=TAG).error(f"保存PCM数据失败: {e}", exc_info=True)
            raise

    def read_file_to_pcm(self, file_path: str) -> bytes:
        try:
            # 读取音频文件
            file_type = os.path.splitext(file_path)[1].lstrip(".")
            audio = AudioSegment.from_file(file_path, format=file_type or "mp3", parameters=["-nostdin"])

            # 标准化音频格式：单声道/16kHz/16位
            audio = audio.set_channels(1).set_frame_rate(16000).set_sample_width(2)
            return audio.raw_data
        except Exception as e:
            logger.bind(tag=TAG).error(f"读取PCM文件失败: {e}", exc_info=True)
            raise
