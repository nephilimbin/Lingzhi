from typing import List

from config.logger import setup_logging

TAG = __name__
logger = setup_logging()

# 延迟导入，避免在基础功能测试时强制要求opus库
try:
    import opuslib_next

    OPUS_AVAILABLE = True
except Exception as e:
    logger.bind(tag=TAG).warning(f"Warning: Opus library not available: {e}")
    OPUS_AVAILABLE = False
    opuslib_next = None


class OpusEncoder:
    """
    Opus编码器
    维护一个缓冲区，确保只对完整的帧进行编码，且保持编码器状态连续。
    """

    def __init__(self, sample_rate=16000, channels=1, frame_duration_ms=60):
        self.sample_rate = sample_rate
        self.channels = channels
        self.frame_duration_ms = frame_duration_ms
        self.application = opuslib_next.APPLICATION_AUDIO if OPUS_AVAILABLE else None

        # 初始化编码器 (保持单例，维持上下文状态)
        self.encoder = opuslib_next.Encoder(self.sample_rate, self.channels, self.application)

        # 计算每一帧需要的采样数和字节数
        # 16000Hz * 0.06s = 960 samples
        # 24000 * 0.06 = 1440 samples
        self.frame_size_samples = int(self.sample_rate * self.frame_duration_ms / 1000)
        self.frame_size_bytes = self.frame_size_samples * 2  # 16-bit audio = 2 bytes per sample

        # 数据缓冲区
        self.opus_stream_buffer = bytearray()

    def encode_pcm_full(self, pcm_chunk: bytes) -> List[bytes]:
        """
        处理输入的任意长度 PCM 数据块
        返回编码好的 Opus 帧列表（可能为空，也可能有多个）
        """
        try:
            opus_data_list = []

            # 按帧编码音频数据
            for i in range(0, len(pcm_chunk), self.frame_size_bytes):
                chunk = pcm_chunk[i : i + self.frame_size_bytes]

                # 最后一帧不足时补零
                if len(chunk) < self.frame_size_bytes:
                    chunk += b"\x00" * (self.frame_size_bytes - len(chunk))

                opus_data = self.encoder.encode(chunk, self.frame_size_samples)
                opus_data_list.append(opus_data)

            return opus_data_list

        except Exception as e:
            logger.bind(tag=TAG).error(f"Opus encoding error: {e}", exc_info=True)
            return []

    def encode_pcm_stream(self, pcm_chunk: bytes) -> List[bytes]:
        """
        处理输入的任意长度 PCM 数据块
        返回编码好的 Opus 帧列表（可能为空，也可能有多个）
        """
        self.opus_stream_buffer.extend(pcm_chunk)
        opus_frames = []

        # 只要缓冲区够切出一个完整的帧，就循环处理
        while len(self.opus_stream_buffer) >= self.frame_size_bytes:
            # 1. 切出头部一帧
            raw_frame = self.opus_stream_buffer[: self.frame_size_bytes]
            # 2. 从缓冲区移除
            del self.opus_stream_buffer[: self.frame_size_bytes]

            # 3. 编码 (注意：encode 接受的是 bytes，frame_size 是采样数)
            try:
                encoded_packet = self.encoder.encode(bytes(raw_frame), self.frame_size_samples)
                opus_frames.append(encoded_packet)
            except Exception as e:
                logger.error(f"Opus encoding error: {e}")

        return opus_frames

    def flush_pcm_stream(self) -> List[bytes]:
        """
        处理缓冲区剩余的数据（通常在会话结束或句子结束时调用）
        进行补零操作
        """
        if not self.opus_stream_buffer:
            return []

        logger.info(f"【Opus编码】Flush剩余数据: {len(self.opus_stream_buffer)} bytes")

        # 补零直到满足一帧的大小
        padding_size = self.frame_size_bytes - len(self.opus_stream_buffer)
        padding = b"\x00" * padding_size

        raw_frame = bytes(self.opus_stream_buffer) + padding
        self.opus_stream_buffer.clear()

        try:
            encoded_packet = self.encoder.encode(raw_frame, self.frame_size_samples)
            return [encoded_packet]
        except Exception as e:
            logger.error(f"Opus flush error: {e}")
            return []


class OpusDecoder:
    """
    Opus解码器
    保持解码器实例常驻，确保帧与帧之间的波形连续，消除杂音。
    """

    def __init__(self, sample_rate=16000, channels=1, frame_duration_ms=60):
        self.sample_rate = sample_rate
        self.channels = channels
        self.frame_duration_ms = frame_duration_ms
        # 创建解码器实例并保持它
        self.decoder = opuslib_next.Decoder(self.sample_rate, self.channels)

    def decode_pcm_stream(self, opus_packet: bytes) -> bytes:
        """
        解码单个 Opus 包
        """
        try:
            # 计算这一帧预期的采样点数
            frame_size = int(self.sample_rate * self.frame_duration_ms / 1000)

            # 解码
            pcm_data = self.decoder.decode(opus_packet, frame_size)

            # 确保返回 bytes
            if isinstance(pcm_data, bytes):
                return pcm_data
            else:
                return bytes(pcm_data)

        except opuslib_next.OpusError as e:
            logger.error(f"Opus decode error: {e}")
            return b""
        except Exception as e:
            logger.error(f"General decode error: {e}")
            return b""
