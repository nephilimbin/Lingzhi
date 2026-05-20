from abc import ABC, abstractmethod
import asyncio
from dataclasses import dataclass
import os
import queue
import time
from typing import Optional

from config.logger import setup_logging
from core.utils.audio_pcm_handler import PcmHandler
from core.utils.util import set_unique_id

TAG = __name__
logger = setup_logging()


TAG = __name__


class TTSConnectionError(Exception):
    """TTS连接异常，用于标识连接断开、网络错误等可重试的异常情况"""

    def __init__(self, message: str, recoverable: bool = True):
        super().__init__(message)
        self.recoverable = recoverable  # 标识是否可恢复（可重试）


@dataclass
class TtsAudioResponseData:
    """音频流数据模型，用于统一流式TTS的返回结果"""

    pcm_bytes: bytes = None
    pcm_sample_rate: int = 16000  # 原始采样率
    pcm_is_complete: bool = False
    text_index: int = 0
    error_info: Optional[str] = None


class TTSProviderBase(ABC):
    """简化的TTS提供者基类，专注于核心TTS功能"""

    def __init__(self, config: dict):
        self.logger = setup_logging()
        self.type = config.get("type")
        self.voice = config.get("voice")
        self.model_name = config.get("model_name")
        self.model_dir = config.get("model_dir", "")
        self.output_dir = config.get("output_dir", "./")
        self.audio_sample_rate = 16000
        self.audio_sample_channels = 1
        self.audio_sample_width = 2
        self.pcm_handler = PcmHandler(
            sample_rate=self.audio_sample_rate,
            channels=self.audio_sample_channels,
            sample_width=self.audio_sample_width,
        )

        # 确保输出目录存在
        if self.output_dir:
            os.makedirs(self.output_dir, exist_ok=True)

    def set_output_directory(self, output_dir: str) -> None:
        """向后兼容方法"""
        self.output_dir = output_dir
        os.makedirs(output_dir, exist_ok=True)

    def generate_output_path(self, filename: str = None) -> str:
        """生成输出文件路径"""
        if not self.output_dir:
            raise ValueError("Output directory not configured")

        if not filename:
            filename = f"tts_{int(time.time())}_{self.model_name}_{set_unique_id('')}.wav"

        # 检查文件尾缀不合规则抛出异常
        if not filename.endswith(".wav"):
            raise ValueError("TTS输出文件必须以 '.wav'")
        return os.path.join(self.output_dir, filename)

    @abstractmethod
    async def text_to_speech(self, client_id: str, text: str, text_index: int = None) -> TtsAudioResponseData:
        """
        流式TTS音频生成抽象方法 - 核心业务处理逻辑说明

        【业务处理逻辑】:
        1. 文本发送: 将输入文本发送到TTS服务API，支持流式文本提交
        2. 音频监听: 通过WebSocket或其他流式连接接收音频数据
        3. 格式转换: 将原始音频转换为16kHz PCM格式（统一标准）
        4. 数据推送: 通过audio_queue异步推送PCM数据块到tts_pipeline
        5. 完成信号: 音频生成完成后发送完成标志

        【数据流处理要求】:
        - 统一返回PCM格式数据，采样率16kHz，单声道，16位采样
        - 禁止在Provider内部进行Opus编码，统一交由tts_pipeline处理
        - 支持音频分块传输，避免单次传输数据过大
        - 正确处理文本索引，支持多段文本的顺序处理

        【实现类注意事项】:
        1. 连接管理:
           - 使用connect方法建立TTS服务连接
           - 维护client_id到连接实例的映射关系
           - 处理连接断开和重连逻辑

        2. 错误处理:
           - 捕获并记录TTS服务异常
           - 通过error_info字段返回错误信息
           - 确保异常情况下资源的正确清理

        3. 性能优化:
           - 使用异步I/O避免阻塞主线程
           - 合理设置音频缓冲区大小
           - 支持并发TTS请求处理

        4. 状态管理:
           - 维护文本索引递增，确保音频顺序
           - 正确标记音频流完成状态
           - 处理文本分段和音频包的对应关系

        【数据推送示例】:
        ```python
        # 处理流式音频数据
        async def handle_streaming_audio(self, client_id: str, text: str):
            audio_queue = self.get_audio_queue(client_id)

            # 发送文本到TTS服务
            await self.send_text_to_tts(text)

            # 接收并处理音频数据
            while True:
                audio_chunk = await self.receive_audio_data()
                if audio_chunk is None:  # 音频完成
                    # 发送完成信号
                    audio_queue.put_nowait(
                        TtsAudioResponseData(
                            pcm_chunk=None,
                            text_index=self.current_text_index,
                            is_complete=True
                        )
                    )
                    break

                # 转换为标准PCM格式
                pcm_data = self.convert_to_standard_pcm(audio_chunk)

                # 分块推送PCM数据
                for pcm_chunk in self.chunk_pcm_data(pcm_data):
                    audio_queue.put_nowait(
                        TtsAudioResponseData(
                            pcm_chunk=pcm_chunk,
                            text_index=self.current_text_index,
                            is_complete=False
                        )
                    )
        ```

        Args:
            client_id (str): 客户端唯一标识符，用于管理连接状态和音频队列
            text (str): 待转换为语音的文本内容，支持中文、英文等多语言

        Returns:
            TtsAudioResponseData: 音频流响应数据，包含以下字段：
                - pcm_chunk (bytes): PCM音频数据块，16kHz采样率，16位深度
                - text_index (int): 文本索引，用于维持音频播放顺序
                - is_complete (bool): 音频流完成标志，最后一段音频需设为True
                - error_info (Optional[str]): 错误信息，发生异常时提供错误详情

        Raises:
            ConnectionError: TTS服务连接失败或断开
            ValueError: 输入参数无效或音频格式转换失败
            TimeoutError: TTS服务响应超时
            Exception: 其他运行时异常
        """
        pass

    @abstractmethod
    def is_support_streaming(self) -> bool:
        """是否支持流式TTS"""
        return False

    @abstractmethod
    def connect(self, client_id: str, audio_play_queue: queue.Queue):
        """建立连接或会话"""
        pass

    @abstractmethod
    def close(self, client_id: str = None):
        """清理资源"""
        pass
