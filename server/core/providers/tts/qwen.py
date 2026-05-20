"""
Qwen TTS Provider - 流式语音合成实现
将TTSRealtimeClient适配到项目的TTS Provider基类框架
"""

import asyncio
import base64
import json
import queue
import time

from config.logger import setup_logging
from core.providers.tts.base import TtsAudioResponseData, TTSConnectionError, TTSProviderBase
import websockets

TAG = __name__


class _TTSRealtimeClient:
    """简化的TTSRealtimeClient实现，移除音频播放和文件保存功能"""

    def __init__(
        self,
        api_key: str,
        model_name: str = "qwen3-tts-flash-realtime",
        voice: str = "Cherry",
        base_url: str = None,
        language_type: str = "Auto",
        sample_rate: int = 24000,
    ):
        if base_url is None:
            base_url = f"wss://dashscope.aliyuncs.com/api-ws/v1/realtime?model={model_name}"
        else:
            base_url = f"{base_url}?model={model_name}"

        self.base_url = base_url
        self.api_key = api_key
        self.voice = voice
        self.model_name = model_name
        self.language_type = language_type
        self.sample_rate = sample_rate
        self.ws = None
        self.logger = setup_logging()

    async def connect(self) -> None:
        """与 TTS Realtime API 建立 WebSocket 连接"""
        headers = {"Authorization": f"Bearer {self.api_key}"}

        self.ws = await websockets.connect(self.base_url, additional_headers=headers)

        # 设置默认会话配置
        await self.update_session(
            {
                "mode": "server_commit",  # 使用服务器提交模式
                "voice": self.voice,
                "language_type": self.language_type,
                "response_format": "pcm",
                "sample_rate": self.sample_rate,
            }
        )

    async def send_event(self, event) -> None:
        """发送事件到服务器"""
        event["event_id"] = "event_" + str(int(time.time() * 1000))
        await self.ws.send(json.dumps(event))

    async def update_session(self, config: dict) -> None:
        """更新会话配置"""
        event = {"type": "session.update", "session": config}
        await self.send_event(event)

    async def append_text(self, text: str) -> None:
        """向 API 发送文本数据"""
        event = {"type": "input_text_buffer.append", "text": text}
        await self.send_event(event)

    async def commit_text_buffer(self) -> None:
        """提交文本缓冲区以触发处理"""
        event = {"type": "input_text_buffer.commit"}
        await self.send_event(event)

    async def finish_session(self) -> None:
        """结束会话。"""
        event = {"type": "session.finish"}
        await self.send_event(event)

    async def close(self) -> None:
        """关闭 WebSocket 连接"""
        if self.ws:
            await self.ws.close()


class TTSProvider(TTSProviderBase):
    """Qwen TTS Provider，将TTSRealtimeClient适配到基类接口"""

    def __init__(self, config: dict):
        super().__init__(config)
        self.config = config
        self.api_key = config.get("api_key")
        self.model_name = config.get("model_name", "qwen3-tts-flash-realtime")
        self.voice = config.get("voice", "Cherry")
        self.base_url = config.get("base_url")
        self.language_type = config.get("language_type", "Auto")
        self.sample_rate = config.get("sample_rate", 24000)
        self.logger = setup_logging()

        # 初始化连接管理器
        self.active_connections = {}
        # 存储监听任务
        self.listening_tasks = {}
        # 为每个client_id维护独立的text_index计数器
        self.text_index_counters = {}

    async def connect(self, client_id: str, audio_queue: queue.Queue) -> _TTSRealtimeClient:
        """
        获取或创建对应的TTS连接，并启动音频监听循环
        :param client_id: 唯一的客户端标识符
        :param audio_queue: 用于接收音频数据的队列
        :return: _TTSRealtimeClient实例
        """
        try:
            if client_id not in self.active_connections:
                client = _TTSRealtimeClient(
                    api_key=self.config["api_key"],
                    model_name=self.config["model_name"],
                    voice=self.config["voice"],
                    base_url=self.config["base_url"],
                    sample_rate=self.config["sample_rate"],
                )
                await client.connect()
                self.active_connections[client_id] = client
                # 为每个client_id初始化独立的text_index计数器
                self.text_index_counters[client_id] = 1

                # 启动音频监听任务
                task = asyncio.create_task(self._receive_audio_loop(client_id, client, audio_queue))
                self.listening_tasks[client_id] = task
                self.logger.bind(tag=TAG).info(f"[QwenTTS] session {client_id} TTS连接建立成功，监听任务已启动")

            return self.active_connections[client_id]
        except Exception as e:
            self.logger.bind(tag=TAG).error(f"[QwenTTS] session {client_id} TTS连接建立失败: {e}")
            raise

    async def _receive_audio_loop(self, client_id: str, client: _TTSRealtimeClient, audio_queue: queue.Queue):
        """
        后台任务：监听WebSocket消息并处理音频数据
        """
        self.logger.bind(tag=TAG).info(f"[QwenTTS] session {client_id} 开始监听音频数据")

        try:
            # 使用超时的websocket消息接收，避免无限阻塞
            while client_id in self.active_connections:  # 检查连接是否仍然有效
                try:
                    # 设置较短的超时时间，这样可以定期检查连接状态
                    message = await asyncio.wait_for(client.ws.recv(), timeout=1.0)
                    event = json.loads(message)
                    event_type = event.get("type")

                    if event_type == "session.created":
                        self.logger.bind(tag=TAG).info(f"[QwenTTS] 会话创建: {event.get('session', {}).get('id')}")
                    # elif event_type == "session.updated":
                    #     self.logger.bind(tag=TAG).info(f"[QwenTTS] 会话更新: {event.get('session', {}).get('id')}")
                    # elif event_type == "input_text_buffer.committed":
                    #     self.logger.bind(tag=TAG).info(f"[QwenTTS] 文本缓冲区已提交，项目ID: {event.get('item_id')}")
                    # elif event_type == "response.created":
                    #     self.logger.bind(tag=TAG).info(
                    #         f"[QwenTTS] 响应已创建，ID: {event.get('response', {}).get('id')}"
                    #     )
                    # elif event_type == "response.output_item.added":
                    #     self.logger.bind(tag=TAG).info(f"[QwenTTS] 输出项已添加，ID: {event.get('item', {}).get('id')}")
                    # elif event_type == "response.audio.done":
                    #     self.logger.bind(tag=TAG).info("[QwenTTS] 音频生成完成")
                    elif event_type == "response.audio.delta":
                        audio_bytes = base64.b64decode(event.get("delta", ""))
                        # 返回原始 24kHz 音频，让业务层处理批量转换
                        # 由于是并发处理，qwen会合并为一个需求，无法拆分每个完成的任务。所以处理中的text_index都标记为1，完成的时候再更新。
                        audio_queue.put(
                            TtsAudioResponseData(
                                pcm_bytes=audio_bytes,
                                pcm_sample_rate=self.sample_rate,  # Qwen TTS 原始采样率
                                text_index=1,
                            )
                        )
                    elif event_type == "response.done":
                        # self.logger.bind(tag=TAG).debug("[QwenTTS] 响应完成，发送完成信号")

                        # 发送完成信号
                        audio_queue.put(
                            TtsAudioResponseData(
                                pcm_bytes=b"", pcm_is_complete=True, text_index=self.text_index_counters[client_id]
                            )
                        )

                    elif event_type == "error":
                        error_info = event.get("error", {})
                        self.logger.bind(tag=TAG).info(f"[QwenTTS] 错误: {error_info}")
                    else:
                        # 对于其他事件，只记录但不影响处理
                        pass

                except asyncio.TimeoutError:
                    # 超时是正常的，继续循环检查连接状态
                    continue
                except websockets.exceptions.ConnectionClosed as e:
                    self.logger.bind(tag=TAG).warning(f"[QwenTTS] 连接意外关闭: {e}")
                    raise TTSConnectionError(f"TTS连接意外关闭: {e}", recoverable=True)
                except json.JSONDecodeError as e:
                    self.logger.bind(tag=TAG).error(f"[QwenTTS] JSON解析错误: {e}")
                    continue  # 继续处理下一条消息
                except asyncio.CancelledError:
                    self.logger.bind(tag=TAG).info(f"[QwenTTS] session {client_id} 监听任务被取消")
                    break
                except Exception as e:
                    self.logger.bind(tag=TAG).error(f"[QwenTTS] 处理消息异常: {e}")
                    continue  # 继续处理下一条消息

        except TTSConnectionError as e:
            # 连接意外关闭（如300秒超时），清理本地资源并优雅退出
            self.logger.bind(tag=TAG).warning(f"[QwenTTS] session {client_id} 连接关闭: {e}")
            self.active_connections.pop(client_id, None)
            self.text_index_counters.pop(client_id, None)
        except Exception as e:
            self.logger.bind(tag=TAG).error(f"[QwenTTS] 监听TTS音频错误: {type(e).__name__}: {str(e)}")

    async def _produce_text(self, client: _TTSRealtimeClient, text: str, is_text_end: bool):
        """向服务器发送文本片段"""
        if text == "":
            if is_text_end:
                await client.commit_text_buffer()
                # self.logger.bind(tag=TAG).debug(f"[QwenTTS] 提交文本任务结束:{is_text_end}")
            return

        await client.append_text(text)
        # 等待服务器完成内部处理后结束会话
        await asyncio.sleep(0.1)
        if is_text_end:
            await client.commit_text_buffer()

    async def text_to_speech(
        self, client_id: str, text: str, text_index: int, is_text_end: bool, audio_queue: queue.Queue
    ):
        """
        发送文本到TTS服务，如果连接不存在则自动创建

        设计模式:
            - 延迟初始化模式: 首次调用时自动创建连接
            - 单例模式: 每个client_id对应唯一的TTS连接
            - 重试模式: 连接失败时自动重试（最多2次）

        主要功能:
            - 自动连接管理: 检查连接状态，不存在时自动创建
            - 文本发送: 将文本发送到TTS服务进行语音合成
            - 异常处理: 统一的连接异常处理和重试机制
            - 连接恢复: 检测到连接断开时自动重建连接并重试发送

        :param client_id: 客户端ID，用于标识唯一的TTS连接
        :param text: 要转换的文本内容
        :param text_index: 文本索引（可选），用于标识文本片段顺序
        :param is_text_end: 是否是文本的最后一个片段
        :param audio_queue: 音频数据队列，首次连接时必须提供
        :raises TTSConnectionError: 当连接创建或发送失败且重试耗尽后抛出
        """
        # 最大重试次数：初始尝试 + 2次重试
        max_retries = 2

        for attempt in range(max_retries + 1):
            try:
                # 获取或创建TTS连接
                client = await self.connect(client_id, audio_queue)
                # 更新文本任务计数
                self.text_index_counters[client_id] = text_index

                # 发送文本到TTS服务
                produce_task = asyncio.create_task(self._produce_text(client, text, is_text_end))
                await produce_task

                return  # 成功完成，退出重试循环

            except websockets.exceptions.ConnectionClosed as e:
                # 连接关闭异常，标记为可恢复
                error_msg = f"发送文本时连接断开: {e}"

                if attempt < max_retries:
                    # 还有重试机会，关闭旧连接并重试
                    self.logger.bind(tag=TAG).warning(
                        f"[QwenTTS] {error_msg}，关闭旧连接并重试 ({attempt + 1}/{max_retries})"
                    )
                    try:
                        # 关闭旧连接
                        await self._close_single_connection(client_id)
                        self.logger.bind(tag=TAG).debug(f"[QwenTTS] 旧连接已关闭: {client_id}")
                    except Exception as close_error:
                        self.logger.bind(tag=TAG).warning(f"[QwenTTS] 关闭旧连接失败: {close_error}")

                    # 短暂等待后重试
                    await asyncio.sleep(0.2)
                else:
                    # 重试耗尽，抛出异常
                    self.logger.bind(tag=TAG).error(f"[QwenTTS] {error_msg}，重试耗尽")
                    raise TTSConnectionError(f"{error_msg}（已重试{max_retries}次）", recoverable=True)

            except TTSConnectionError as e:
                # TTS连接异常，根据recoverable决定是否重试
                if e.recoverable and attempt < max_retries:
                    self.logger.bind(tag=TAG).warning(
                        f"[QwenTTS] 连接异常可恢复: {e}，重试 ({attempt + 1}/{max_retries})"
                    )
                    # 短暂等待后重试
                    await asyncio.sleep(0.2)
                else:
                    # 不可恢复或重试耗尽，抛出异常
                    self.logger.bind(tag=TAG).error(f"[QwenTTS] 连接异常: {e}，重试耗尽")
                    raise

            except Exception as e:
                # 其他异常，记录后重新抛出（不重试）
                self.logger.bind(tag=TAG).error(f"[QwenTTS] 发送文本失败（不可恢复）: {e}")
                raise

    async def close(self, client_id: str = None):
        """关闭指定client_id的TTS连接或者全部关闭"""
        try:
            if client_id is None:
                # 获取所有连接的ID列表，避免在迭代过程中修改字典
                client_ids = list(self.active_connections.keys())

                # 逐个关闭连接，_close_single_connection 会清理所有相关资源
                for cid in client_ids:
                    try:
                        await self._close_single_connection(cid)
                    except Exception as e:
                        self.logger.bind(tag=TAG).error(f"[QwenTTS] 关闭连接 {cid} 异常: {e}")
            else:
                # 关闭特定连接
                await self._close_single_connection(client_id)

        except Exception as e:
            self.logger.bind(tag=TAG).error(f"[QwenTTS] 关闭异常: {e}")

    async def _close_single_connection(self, client_id: str):
        """关闭单个连接"""
        # 关闭 WebSocket 并移除连接记录
        client = self.active_connections.pop(client_id, None)
        if client:
            try:
                await client.close()
                self.logger.bind(tag=TAG).info(f"[QwenTTS] WebSocket连接已关闭: {client_id}")
            except Exception as e:
                self.logger.bind(tag=TAG).warning(f"[QwenTTS] 关闭WebSocket异常: {e}")

        # 取消/清理监听任务，确保始终消费任务异常避免 "Task exception was never retrieved"
        task = self.listening_tasks.pop(client_id, None)
        if task:
            if not task.done():
                self.logger.bind(tag=TAG).info(f"[QwenTTS] 取消 session {client_id} 的监听任务")
                try:
                    task.cancel()
                    await asyncio.wait_for(task, timeout=5.0)
                except (asyncio.CancelledError, TTSConnectionError):
                    pass
                except asyncio.TimeoutError:
                    self.logger.bind(tag=TAG).warning(f"[QwenTTS] 监听任务取消超时: {client_id}")
            else:
                # 任务已完成（可能因连接超时等原因异常退出），消费其异常
                try:
                    task.result()
                except Exception:
                    pass

        # 清理其他资源（静默处理，不存在则返回None）
        self.text_index_counters.pop(client_id, None)

        # 记录完成日志
        if client or task:
            self.logger.bind(tag=TAG).info(f"[QwenTTS] session {client_id} 资源清理完成")
        else:
            self.logger.bind(tag=TAG).debug(f"[QwenTTS] session {client_id} 资源已清理或不存在")

    def is_support_streaming(self) -> bool:
        """是否支持流式TTS"""
        return True
