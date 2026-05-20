"""
音频淡出处理器 - 实现WebRTC音频的平滑淡出效果
"""

import asyncio
from typing import List, Optional

from config.logger import setup_logging
import numpy as np

TAG = __name__
logger = setup_logging()


class AudioFadeOutProcessor:
    """
    音频淡出处理器

    功能：
    - 实现200ms的指数淡出效果
    - 生成淡出音频帧序列
    - 管理淡出队列和状态
    """

    def __init__(self, sample_rate: int = 16000, fade_duration_ms: int = 200, frame_duration_ms: int = 20):
        """
        初始化音频淡出处理器

        Args:
            sample_rate: 音频采样率，默认16000Hz
            fade_duration_ms: 淡出持续时间，默认200ms
            frame_duration_ms: 每帧持续时间，默认20ms
        """
        self.sample_rate = sample_rate
        self.fade_duration_ms = fade_duration_ms
        self.frame_duration_ms = frame_duration_ms
        self.fade_frames = fade_duration_ms // frame_duration_ms
        self.samples_per_frame = sample_rate * frame_duration_ms // 1000

        # 淡出相关状态
        self.is_fading_out = False
        self.fade_out_queue = asyncio.Queue(maxsize=50)  # 限制队列大小防止积压

        # 淡出参数
        self.fade_factor_per_frame = 0.8  # 每帧衰减到80%（指数淡出）

        logger.bind(tag=TAG).info(
            f"AudioFadeOutProcessor初始化: "
            f"采样率={sample_rate}Hz, 淡出时长={fade_duration_ms}ms, "
            f"帧时长={frame_duration_ms}ms, 淡出帧数={self.fade_frames}"
        )

    def start_fade_out(self, remaining_audio: Optional[np.ndarray] = None) -> List[np.ndarray]:
        """
        开始淡出，生成淡出音频帧序列

        Args:
            remaining_audio: 剩余的音频数据，如果为None则生成静音淡出

        Returns:
            淡出音频帧列表
        """
        if self.is_fading_out:
            logger.bind(tag=TAG).warning("淡出已在进行中，忽略新的淡出请求")
            return []

        self.is_fading_out = True
        fade_frames = []

        try:
            # 如果没有剩余音频，生成静音帧
            if remaining_audio is None or len(remaining_audio) == 0:
                remaining_audio = np.zeros(self.samples_per_frame, dtype=np.int16)
                logger.bind(tag=TAG).info("没有剩余音频，生成静音淡出")
            else:
                logger.bind(tag=TAG).info(f"使用剩余音频进行淡出，长度: {len(remaining_audio)} 样本")

            # 生成淡出帧序列
            current_audio = remaining_audio.copy()

            for frame_index in range(self.fade_frames):
                # 计算当前帧的淡出系数（指数衰减）
                fade_factor = self.fade_factor_per_frame**frame_index

                # 应用淡出效果
                faded_audio = current_audio.astype(np.float32) * fade_factor

                # 确保音频在有效范围内并转换为int16
                faded_int16 = np.clip(faded_audio, -32768, 32767).astype(np.int16)

                # 调整音频帧大小到标准帧大小
                if len(faded_int16) < self.samples_per_frame:
                    # 如果音频太短，用零填充
                    padded_audio = np.zeros(self.samples_per_frame, dtype=np.int16)
                    padded_audio[: len(faded_int16)] = faded_int16
                    fade_frames.append(padded_audio)
                elif len(faded_int16) > self.samples_per_frame:
                    # 如果音频太长，截取前N个样本
                    fade_frames.append(faded_int16[: self.samples_per_frame])
                else:
                    fade_frames.append(faded_int16)

                # 更新当前音频为淡出后的版本（用于下一帧）
                current_audio = faded_int16

            logger.bind(tag=TAG).info(f"生成{len(fade_frames)}个淡出帧")
            return fade_frames

        except Exception as e:
            logger.bind(tag=TAG).error(f"生成淡出帧失败: {e}")
            self.is_fading_out = False
            return []

    async def add_fade_out_frames(self, fade_frames: List[np.ndarray]):
        """
        将淡出帧添加到淡出队列

        Args:
            fade_frames: 淡出音频帧列表
        """
        try:
            for i, frame in enumerate(fade_frames):
                # 如果队列满了，丢弃最旧的帧
                if self.fade_out_queue.full():
                    try:
                        self.fade_out_queue.get_nowait()
                        logger.bind(tag=TAG).warning("淡出队列已满，丢弃最旧帧")
                    except asyncio.QueueEmpty:
                        pass

                await self.fade_out_queue.put(frame)

            logger.bind(tag=TAG).debug(f"添加{len(fade_frames)}个淡出帧到队列")

        except Exception as e:
            logger.bind(tag=TAG).error(f"添加淡出帧到队列失败: {e}")

    async def get_next_fade_frame(self) -> Optional[np.ndarray]:
        """
        获取下一个淡出帧

        Returns:
            下一个淡出帧，如果没有则返回None
        """
        try:
            if not self.fade_out_queue.empty():
                frame = self.fade_out_queue.get_nowait()
                return frame
            return None
        except asyncio.QueueEmpty:
            return None
        except Exception as e:
            logger.bind(tag=TAG).error(f"获取淡出帧失败: {e}")
            return None

    async def start_fade_out_and_enqueue(self, remaining_audio: Optional[np.ndarray] = None):
        """
        开始淡出并自动将淡出帧添加到队列

        Args:
            remaining_audio: 剩余的音频数据
        """
        try:
            fade_frames = self.start_fade_out(remaining_audio)
            if fade_frames:
                await self.add_fade_out_frames(fade_frames)
                logger.bind(tag=TAG).info("淡出帧已添加到队列，等待播放")
            else:
                self.is_fading_out = False
                logger.bind(tag=TAG).warning("没有生成淡出帧")
        except Exception as e:
            logger.bind(tag=TAG).error(f"启动淡出失败: {e}")
            self.is_fading_out = False

    def has_fade_frames(self) -> bool:
        """
        检查是否有淡出帧待播放

        Returns:
            True如果有淡出帧，False否则
        """
        return not self.fade_out_queue.empty()

    def is_active(self) -> bool:
        """
        检查淡出处理器是否活跃（正在淡出或有待播放的帧）

        Returns:
            True如果活跃，False否则
        """
        return self.is_fading_out or self.has_fade_frames()

    def reset(self):
        """重置淡出处理器状态"""
        self.is_fading_out = False

        # 清空淡出队列
        while not self.fade_out_queue.empty():
            try:
                self.fade_out_queue.get_nowait()
            except asyncio.QueueEmpty:
                break

        logger.bind(tag=TAG).debug("淡出处理器状态已重置")

    async def clear_queue(self):
        """清空淡出队列（异步版本）"""
        while not self.fade_out_queue.empty():
            try:
                await self.fade_out_queue.get()
            except asyncio.QueueEmpty:
                break

        logger.bind(tag=TAG).debug("淡出队列已清空")

    def get_queue_size(self) -> int:
        """
        获取当前淡出队列大小

        Returns:
            队列中的帧数
        """
        return self.fade_out_queue.qsize()

    def get_status(self) -> dict:
        """
        获取淡出处理器状态信息

        Returns:
            状态字典
        """
        return {
            "is_fading_out": self.is_fading_out,
            "queue_size": self.get_queue_size(),
            "fade_frames": self.fade_frames,
            "samples_per_frame": self.samples_per_frame,
            "fade_duration_ms": self.fade_duration_ms,
            "fade_factor_per_frame": self.fade_factor_per_frame,
        }
