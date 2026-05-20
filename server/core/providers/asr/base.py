from abc import ABC, abstractmethod
import os
from typing import List, Union

from config.logger import setup_logging
from core.models.asr_models import ASRResponseInfo
from core.utils.audio_opus_handler import OpusDecoder

TAG = __name__


class ASRProviderBase(ABC):
    OPUS_SAMPLE_RATE = 16000
    OPUS_CHANNELS = 1
    OPUS_FRAME_DURATION = 60

    def __init__(self, config: dict):
        self.logger = setup_logging()
        self.output_dir = None
        self.model_name = config.get("model_name", "")
        self.model_dir = config.get("model_dir", "")
        self.type = config.get("type", "")
        self.api_key = config.get("api_key", "")
        self.audio_sample_rate = 16000
        self.audio_sample_channels = 1
        self.audio_sample_width = 2  # 2 bytes = 16-bit
        self.audio_frame_duration = 60
        self.opus_decoder = OpusDecoder(sample_rate=self.audio_sample_rate, channels=self.audio_sample_channels)

    def set_output_directory(self, output_dir):
        """动态设置输出目录"""
        self.output_dir = output_dir
        # 确保目录存在
        os.makedirs(output_dir, exist_ok=True)

    @abstractmethod
    async def speech_to_text(self, audio_data: Union[bytes, List[bytes]]) -> ASRResponseInfo:
        """
        流式ASR语音识别抽象方法 - 核心业务处理逻辑说明

        【业务处理逻辑】:
        1. 音频接收: 接收原始音频数据，支持单块bytes或多块List[bytes]格式
        2. 音频解码: 将Opus编码的音频数据解码为标准PCM格式
        3. 语音识别: 将音频数据发送到ASR服务进行语音识别处理
        4. 结果解析: 解析ASR服务返回的识别结果，提取文本和相关信息
        5. 状态管理: 管理识别状态，包括临时结果和最终结果

        【数据流处理要求】:
        - 支持Opus格式音频输入，采样率16kHz，单声道，16位采样
        - 统一处理音频解码，兼容不同格式的音频输入
        - 支持流式识别，能够处理实时音频流
        - 正确处理音频分段和识别结果的对应关系

        【实现类注意事项】:
        1. 音频处理:
           - 使用opus_decoder解码Opus格式音频数据
           - 确保音频格式符合ASR服务要求
           - 处理音频缓冲区和分块逻辑

        2. 识别管理:
           - 维护识别会话状态，区分临时结果和最终结果
           - 处理识别超时和异常情况
           - 支持多语言和方言识别

        3. 错误处理:
           - 捕获并记录ASR服务异常
           - 通过ASRResponseInfo返回错误信息
           - 确保异常情况下资源的正确清理

        4. 性能优化:
           - 使用异步I/O避免阻塞主线程
           - 合理设置音频缓冲区大小
           - 支持并发ASR请求处理

        【数据流处理示例】:
        ```python
        # 处理流式音频识别
        async def handle_streaming_audio(self, audio_data: Union[bytes, List[bytes]]):
            try:
                # 解码Opus音频数据
                if isinstance(audio_data, bytes):
                    pcm_data = self.opus_decoder.decode(audio_data)
                else:
                    pcm_chunks = []
                    for opus_chunk in audio_data:
                        pcm_chunk = self.opus_decoder.decode(opus_chunk)
                        pcm_chunks.append(pcm_chunk)
                    pcm_data = b"".join(pcm_chunks)

                # 发送到ASR服务进行识别
                recognition_result = await self.send_to_asr_service(pcm_data)

                # 构造返回结果
                return ASRResponseInfo(
                    text=recognition_result.text,
                    is_final=recognition_result.is_final,
                    confidence=recognition_result.confidence,
                    begin_time=recognition_result.begin_time,
                    end_time=recognition_result.end_time,
                    provider_name=self.model_name
                )

            except Exception as e:
                self.logger.error(f"ASR recognition failed: {e}")
                return ASRResponseInfo(
                    text="",
                    is_final=True,
                    error_info=str(e)
                )
        ```

        Args:
            audio_data (Union[bytes, List[bytes]]): 待识别的音频数据
                - bytes: 单块Opus编码音频数据
                - List[bytes]: 多块Opus编码音频数据列表，支持连续音频流

        Returns:
            ASRResponseInfo: 语音识别响应数据，包含以下字段：
                - text (str): 识别出的文本内容
                - is_final (bool): 是否为最终识别结果，True表示最终结果
                - confidence (Optional[float]): 识别置信度，0.0-1.0范围
                - begin_time (Optional[float]): 音频片段开始时间（秒）
                - end_time (Optional[float]): 音频片段结束时间（秒）
                - sentence_id (Optional[int]): 句子ID，用于多句子识别场景
                - audio_file_path (Optional[str]): 保存的音频文件路径
                - provider_name (Optional[str]): ASR服务提供商名称

        Raises:
            ConnectionError: ASR服务连接失败或断开
            ValueError: 输入音频数据格式无效
            TimeoutError: ASR服务响应超时
            Exception: 其他运行时异常
        """
        pass

    @abstractmethod
    def is_support_stream_mode(self) -> bool:
        """是否支持流式识别"""
        return False

    @abstractmethod
    def close(self):
        # 流式模式有时候需要关闭
        pass
