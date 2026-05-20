import asyncio
import io
import time
import traceback
from typing import Dict, Optional

from core.providers.tts.base import TtsAudioResponseData, TTSProviderBase
import edge_tts
from pydub import AudioSegment

TAG = __name__


class EdgeTTSConnection:
    """Edge TTS连接管理器"""

    def __init__(self, client_id: str, audio_queue: asyncio.Queue):
        self.client_id = client_id
        self.audio_queue = audio_queue
        self.current_text_index = 0
        self.is_active = True
        self.last_activity = time.time()

    async def send_audio_chunk(self, pcm_data: bytes, text_index: int, is_complete: bool = False):
        """发送PCM音频块到队列"""
        if self.is_active:
            response = TtsAudioResponseData(
                pcm_bytes=pcm_data, text_index=text_index, pcm_is_complete=is_complete, error_info=None
            )
            await self.audio_queue.put(response)
            self.last_activity = time.time()

    async def send_completion(self, text_index: int | None):
        """发送完成信号"""
        if text_index is None:
            text_index = 0
        await self.send_audio_chunk(None, text_index, True)

    def close(self):
        """关闭连接"""
        self.is_active = False


class TTSProvider(TTSProviderBase):
    """Edge TTS提供者 - 支持流式并发处理"""

    def __init__(self, config):
        super().__init__(config)
        self.voice = config.get("voice", "zh-CN-XiaoxiaoNeural")
        self.type = config.get("type")

        # 确保 model_name 设置正确
        if not self.model_name:
            self.model_name = config.get("model_name", "edge-tts")

        # 连接管理: {client_id: EdgeTTSConnection}
        self.connections: Dict[str, EdgeTTSConnection] = {}
        self.connection_lock = asyncio.Lock()

        # TTS处理配置
        self.chunk_size = 4096  # PCM数据块大小
        self.max_concurrent_requests = 5  # 最大并发请求数

    async def text_to_speech(self, client_id: str, text: str, text_index: int | None = None) -> TtsAudioResponseData:
        """
        流式TTS音频生成 - Edge TTS实现

        业务处理逻辑:
        1. 获取客户端连接，检查连接有效性
        2. 使用edge_tts进行文本转音频
        3. 将音频转换为标准PCM格式(16kHz, 单声道, 16位)
        4. 分块发送PCM数据到tts业务层处理队列
        5. 发送完成信号

        Args:
            client_id: 客户端唯一标识符
            text: 待转换的文本内容
            text_index: 文本索引，维持音频播放顺序

        Returns:
            TtsAudioResponseData: 最后一个音频块标记为完成状态

        Raises:
            ConnectionError: 客户端连接不存在或已断开
            ValueError: 输入参数无效
            Exception: TTS服务异常
        """
        if not text or not text.strip():
            self.logger.bind(tag=TAG).error(f"TTS文本为空: client_id={client_id}")
            safe_text_index = text_index if text_index is not None else 0
            return TtsAudioResponseData(
                pcm_bytes=None, text_index=safe_text_index, pcm_is_complete=True, error_info="输入文本为空"
            )

        # 获取客户端连接
        connection = await self._get_connection(client_id)
        if not connection:
            self.logger.bind(tag=TAG).error(f"客户端连接不存在: client_id={client_id}")
            safe_text_index = text_index if text_index is not None else 0
            return TtsAudioResponseData(
                pcm_bytes=None, text_index=safe_text_index, pcm_is_complete=True, error_info="客户端连接不存在"
            )

        try:
            self.logger.bind(tag=TAG).debug(
                f"开始TTS转换: client_id={client_id}, text={text[:50]}..., index={text_index}"
            )

            # 使用edge_tts进行文本转音频
            communicate = edge_tts.Communicate(text, self.voice)

            # 收集音频数据到内存
            audio_buffer = io.BytesIO()
            async for chunk in communicate.stream():
                if chunk["type"] == "audio":
                    audio_buffer.write(chunk["data"])

            # 转换为标准PCM格式 (16kHz, 单声道, 16位)
            audio_buffer.seek(0)
            try:
                # 从MP3转换为AudioSegment
                audio = AudioSegment.from_mp3(audio_buffer)

                # 转换为标准格式
                audio = audio.set_frame_rate(16000).set_channels(1).set_sample_width(2)
                pcm_data = audio.raw_data

                self.logger.bind(tag=TAG).debug(
                    f"TTS转换完成: client_id={client_id}, PCM大小={len(pcm_data)}字节, index={text_index}"
                )

            except Exception as audio_error:
                self.logger.bind(tag=TAG).error(f"音频格式转换失败: client_id={client_id}, error={audio_error}")
                safe_text_index = text_index if text_index is not None else 0
                return TtsAudioResponseData(
                    pcm_bytes=None,
                    text_index=safe_text_index,
                    pcm_is_complete=True,
                    error_info=f"音频格式转换失败: {str(audio_error)}",
                )

            # 分块发送PCM数据
            if pcm_data:
                await self._send_pcm_chunks(connection, pcm_data, text_index)

                # 发送完成信号
                await connection.send_completion(text_index)

                self.logger.bind(tag=TAG).debug(f"TTS流发送完成: client_id={client_id}, index={text_index}")

                # 返回最后一个完成信号
                safe_text_index = text_index if text_index is not None else 0
                return TtsAudioResponseData(
                    pcm_bytes=None, text_index=safe_text_index, pcm_is_complete=True, error_info=None
                )
            else:
                self.logger.bind(tag=TAG).warning(f"生成的PCM数据为空: client_id={client_id}")
                safe_text_index = text_index if text_index is not None else 0
                return TtsAudioResponseData(
                    pcm_bytes=None, text_index=safe_text_index, pcm_is_complete=True, error_info="生成的音频数据为空"
                )

        except Exception:
            error_msg = f"TTS转换失败: {traceback.format_exc()}"
            self.logger.bind(tag=TAG).error(f"TTS转换异常: client_id={client_id}, error={error_msg}")

            # 发送错误信号
            safe_text_index = text_index if text_index is not None else 0
            return TtsAudioResponseData(
                pcm_bytes=None, text_index=safe_text_index, pcm_is_complete=True, error_info=error_msg
            )

    async def connect(self, client_id: str, audio_play_queue: asyncio.Queue):
        """
        建立TTS连接 - 创建连接管理器

        Args:
            client_id: 客户端唯一标识符
            audio_play_queue: 音频播放队列，用于发送PCM数据

        Returns:
            EdgeTTSConnection: 连接实例
        """
        async with self.connection_lock:
            if client_id in self.connections:
                # 如果连接已存在，检查是否有效
                existing_connection = self.connections[client_id]
                if existing_connection.is_active:
                    self.logger.bind(tag=TAG).debug(f"TTS连接已存在: client_id={client_id}")
                    return existing_connection
                else:
                    # 清理无效连接
                    del self.connections[client_id]

            # 创建新连接
            connection = EdgeTTSConnection(client_id, audio_play_queue)
            self.connections[client_id] = connection

            self.logger.bind(tag=TAG).info(f"建立TTS连接: client_id={client_id}, 总连接数={len(self.connections)}")

            return connection

    async def close(self, client_id: str = None):
        """
        清理TTS连接资源

        Args:
            client_id: 客户端ID，如果为None则清理所有连接
        """
        async with self.connection_lock:
            if client_id:
                # 清理指定客户端连接
                if client_id in self.connections:
                    connection = self.connections[client_id]
                    connection.close()
                    del self.connections[client_id]
                    self.logger.bind(tag=TAG).info(f"关闭TTS连接: client_id={client_id}")
                else:
                    self.logger.bind(tag=TAG).warning(f"连接不存在: client_id={client_id}")
            else:
                # 清理所有连接
                connection_count = len(self.connections)
                for connection in self.connections.values():
                    connection.close()

                self.connections.clear()
                self.logger.bind(tag=TAG).info(f"关闭所有TTS连接: {connection_count}个连接")

    def is_support_streaming(self) -> bool:
        """是否支持流式TTS"""
        return True

    # ============ 私有辅助方法 ============

    async def _get_connection(self, client_id: str) -> Optional[EdgeTTSConnection]:
        """获取客户端连接"""
        async with self.connection_lock:
            return self.connections.get(client_id)

    async def _send_pcm_chunks(self, connection: EdgeTTSConnection, pcm_data: bytes, text_index: int | None):
        """分块发送PCM数据"""
        try:
            # 确保text_index不为None（虽然类型注解是int，但为了安全起见）
            if text_index is None:
                text_index = 0
                self.logger.bind(tag=TAG).warning("text_index为None，设置为默认值0")

            total_size = len(pcm_data)
            chunks_sent = 0

            # 分块发送PCM数据
            for offset in range(0, total_size, self.chunk_size):
                chunk = pcm_data[offset : offset + self.chunk_size]

                # 发送音频块
                await connection.send_audio_chunk(chunk, text_index, False)
                chunks_sent += 1

                # 避免过快发送，适当控制节奏
                await asyncio.sleep(0.001)

            self.logger.bind(tag=TAG).debug(
                f"PCM数据分块发送完成: client_id={connection.client_id}, "
                f"总大小={total_size}字节, 分块数={chunks_sent}, index={text_index}"
            )

        except Exception as e:
            self.logger.bind(tag=TAG).error(f"发送PCM数据失败: client_id={connection.client_id}, error={e}")
            raise
