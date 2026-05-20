import asyncio
import queue
import traceback
from typing import TYPE_CHECKING, List, Union

from config.logger import setup_logging
from core.adapters.websocket_status import WebSocketException, WebSocketStatus
from core.models.message_models import AudioPlaybackStatus, ChatMode, ResponseInfoInstant

# 使用TYPE_CHECKING来避免循环导入
if TYPE_CHECKING:
    from core.session.session_context import SessionContext

TAG = __name__
logger = setup_logging()


class OutputProcessor:
    """
    统一输出处理器 - 核心消息发送和通信组件

    职责：
    - 整合所有类型的消息输出：文本、音频、状态、错误等
    - 统一WebSocket消息发送接口，简化组件间通信
    - 支持多种传输协议：WebSocket（Opus）、WebRTC（PCM）
    - 管理任务取消和异常处理，确保系统稳定性
    - 实现背压管理和流控，防止网络拥塞

    组件关系：
    - 依赖SessionContext获取WebSocket连接、取消管理器等
    - 与TtsPipeline协作发送不同格式的音频数据
    - 通过StateManager管理发送状态和错误恢复
    - 使用WebSocketAdapter处理底层连接细节

    设计模式：
    - 外观模式：提供统一的输出接口，隐藏复杂的内部实现
    - 策略模式：根据消息类型选择不同的发送策略
    - 模板方法模式：统一的发送流程模板，子类可定制具体实现
    - 观察者模式：监听连接状态变化，动态调整发送策略
    """

    def __init__(self, context: "SessionContext"):
        """
        初始化统一输出处理器

        :param context: 会话上下文，提供WebSocket连接、取消管理器等必要依赖
        """
        self.context = context
        self.session_request_id = ""

    async def send_tts_state_message(self, state: str, session_request_id: str = None, text="text"):
        """
        发送TTS状态消息

        :param state: TTS状态
        :param session_request_id: 会话请求ID
        :param text: 文本内容
        """
        if not session_request_id:
            session_request_id = self.session_request_id
        audio_playback_status = AudioPlaybackStatus(state=state, mode=AudioPlaybackStatus.MODE_AUTO)
        response = ResponseInfoInstant.create_tts_response(
            session_id=self.context.session_id,
            audio_playback_status=audio_playback_status,
            text_source=text,
            session_request_id=session_request_id,
        )
        await self.send_via_websocket(response.to_dict(), "TTS状态", session_request_id)

    async def send_tts_stop_message(self, session_request_id: str = None):
        """
        发送TTS停止消息

        :param session_request_id: 会话请求ID
        """
        if not session_request_id:
            session_request_id = self.session_request_id
        audio_playback_status = AudioPlaybackStatus(
            state=AudioPlaybackStatus.STATE_STOP, mode=AudioPlaybackStatus.MODE_AUTO
        )
        response = ResponseInfoInstant.create_tts_response(
            session_id=self.context.session_id,
            audio_playback_status=audio_playback_status,
            session_request_id=session_request_id,
        )
        await self.send_via_websocket(response.to_dict(), "TTS停止", session_request_id)

    async def send_stt_message(self, text: str, session_request_id: str = None):
        """
        发送STT状态消息

        :param text: 识别的文本内容
        :param session_request_id: 会话请求ID
        """
        if not session_request_id:
            session_request_id = self.session_request_id
        # 发送stt文本内容
        response = ResponseInfoInstant.create_stt_response(
            session_id=self.context.session_id, text_source=text, session_request_id=session_request_id
        )
        await self.send_via_websocket(response.to_dict(), "STT", session_request_id)

    async def send_handshake_message(self, session_request_id: str = None, chat_mode: str = ChatMode.USUAL_MODE):
        """
        发送握手/欢迎消息

        :param session_request_id: 会话请求ID
        :param chat_mode: 聊天模式，默认为usual_mode
        """
        if not session_request_id:
            session_request_id = self.session_request_id
        # 创建握手信息数据
        response = ResponseInfoInstant.create_hello_response(
            session_id=self.context.session_id,
            session_request_id=session_request_id,
            chat_mode=chat_mode,
        )
        await self.send_via_websocket(response.to_dict(), "握手响应", session_request_id)

    async def send_error_message(self, message, session_request_id: str = None):
        """
        发送错误消息

        :param message: 错误消息文本
        :param session_request_id: 会话请求ID
        """
        try:
            if not session_request_id:
                session_request_id = self.session_request_id
            # 创建错误信息数据类型
            response = ResponseInfoInstant.create_error_response(
                session_id=self.context.session_id,
                error_text=message,
                session_request_id=session_request_id,
            )
            await self.send_via_websocket(response.to_dict(), "错误消息", session_request_id)

        except WebSocketException as we:
            # WebSocket状态码处理
            if we.status_code in [WebSocketStatus.DISCONNECTED, WebSocketStatus.ERROR_CONNECTION_LOST]:
                logger.bind(tag=TAG).warning("WebSocket连接已断开，错误消息发送失败")
            else:
                logger.bind(tag=TAG).error(f"错误消息发送失败: {we.status_code.name} - {we.message}")
        except Exception as e:
            logger.bind(tag=TAG).error(f"错误消息发送异常: {e}, traceback: {traceback.format_exc()}")

    async def send_llm_stream_response_message(self, text, is_first_chunk, session_request_id=None):
        """
        发送LLM流式响应消息

        :param text: LLM响应文本
        :param is_first_chunk: 是否为第一个数据块
        :param session_request_id: 会话请求ID
        """
        if not session_request_id:
            session_request_id = self.session_request_id
        # 创建LLM流式响应数据类型
        response = ResponseInfoInstant.create_llm_stream_response(
            session_id=self.context.session_id,
            text_source=text,
            is_first_chunk=is_first_chunk,
            session_request_id=session_request_id,
        )
        await self.send_via_websocket(response.to_dict(), "LLM流式响应", session_request_id)

    async def send_webrtc_audio(self, sample_rate: int, audio_array, session_request_id=None, array_index=-1):
        """
        发送WebRTC格式的音频数据，实现背压管理和流量控制

        :param sample_rate: 音频采样率
        :param audio_array: 音频数据numpy数组
        :param session_request_id: 会话请求ID，用于追踪
        :param array_index: 音频帧序号，用于调试和跟踪
        """
        if not session_request_id:
            session_request_id = self.session_request_id
        try:
            # # 注册任务到取消管理器
            # current_task = asyncio.current_task()
            # if self.context.cancellation_manager and current_task:
            #     await self.context.cancellation_manager.register_task(
            #         session_id=self.context.session_id,
            #         task=current_task,
            #         task_type=self.context.cancellation_manager.task_types.AUDIO_TTS_OUTPUT_TASK,
            #     )

            # # 检查任务取消状态
            # if current_task and current_task.cancelled():
            #     logger.bind(tag=TAG).info("WebRTC音频发送任务已被取消")
            #     return

            # 获取WebRTC输出队列
            webrtc_output_queue = self.context.state_manager.webrtc_tts_audio_output_queue
            if webrtc_output_queue:
                # # 实现背压管理：检查队列大小
                # if webrtc_output_queue.qsize() > 50:
                #     logger.bind(tag=TAG).warning("WebRTC输出队列过满，丢弃最旧数据")
                #     try:
                #         webrtc_output_queue.get_nowait()  # 丢弃最旧数据
                #     except queue.Empty:
                #         pass

                # 音频数据加入队列（同步操作，线程安全）
                # queue.Queue 使用 put() 而不是 put_nowait()
                # put() 是阻塞的，但由于队列无界，实际上不会阻塞
                webrtc_output_queue.put_nowait(item=(sample_rate, audio_array, session_request_id, array_index))
                # logger.bind(tag=TAG).info(
                #     f"WebRTC音频帧已放入队列: array_index={array_index}, queue_size={webrtc_output_queue.qsize()}"
                # )

            else:
                logger.bind(tag=TAG).warning("WebRTC输出队列不可用")

        except asyncio.CancelledError:
            logger.bind(tag=TAG).info("WebRTC音频发送任务被事件驱动中断")
            # 清理WebRTC输出队列（同步操作）
            while not self.context.state_manager.webrtc_tts_audio_output_queue.empty():
                try:
                    self.context.state_manager.webrtc_tts_audio_output_queue.get_nowait()
                except queue.Empty:
                    break
            raise
        except Exception:
            logger.bind(tag=TAG).error(f"WebRTC音频发送失败: {traceback.format_exc()}")
            raise

    async def send_audio_bytes(self, audios: List[bytes], session_request_id=None):
        """
        发送音频字节数据到客户端

        :param audios: 音频字节数据列表
        :param session_request_id: 会话请求ID
        """
        if not session_request_id:
            session_request_id = self.session_request_id
        if isinstance(audios, list) and audios:
            # 注册可取消的音频发送任务
            current_task = asyncio.current_task()
            if self.context.cancellation_manager and current_task:
                await self.context.cancellation_manager.register_task(
                    session_id=self.context.session_id,
                    task=current_task,
                    task_type=self.context.cancellation_manager.task_types.AUDIO_TTS_OUTPUT_TASK,
                )
            try:
                for audio_source in audios:
                    # 检查任务取消状态
                    if current_task and current_task.cancelled():
                        logger.bind(tag=TAG).info("音频发送任务已被取消")
                        break

                    if audio_source:
                        message_info = ResponseInfoInstant.create_tts_audio_opus_response(
                            session_id=self.context.session_id,
                            audio_source=audio_source,
                            session_request_id=session_request_id,
                            audio_input_format="opus",
                            audio_output_format="opus",
                        )
                        # ✅ 统一通过 send_via_websocket 发送到 audio 通道
                        await self.send_via_websocket(
                            message_info.to_dict(), "音频字节数据", session_request_id, channel="audio"
                        )
                        await asyncio.sleep(0.001)  # 防止网络拥塞（保持原有逻辑）
            except asyncio.CancelledError:
                logger.bind(tag=TAG).info("音频发送任务被事件驱动中断")
                raise  # 重新抛出异常
            except Exception as e:
                logger.bind(tag=TAG).error(f"音频发送任务失败: {e}, 追踪: {traceback.format_exc()}")
                raise

    async def send_opus_message(self, audios: Union[bytes, List[bytes]], text_index=0, session_request_id=None):
        """
        发送完整的音频消息，包括状态和音频数据

        :param audios: 音频数据，可以是单个bytes或bytes列表
        :param text_index: 文本索引
        :param session_request_id: 会话请求ID
        """
        try:
            if not session_request_id:
                session_request_id = self.session_request_id
            # 注册可取消的任务
            current_task = asyncio.current_task()
            if self.context.cancellation_manager and current_task:
                await self.context.cancellation_manager.register_task(
                    session_id=self.context.session_id,
                    task=current_task,
                    task_type=self.context.cancellation_manager.task_types.AUDIO_TTS_OUTPUT_TASK,
                )

            # 检查任务是否已被取消
            if current_task and current_task.cancelled():
                logger.bind(tag=TAG).info(f"Opus消息发送任务已被取消 (索引: {text_index})")
                return

            # 检查任务编号是否被重置
            if session_request_id is None:
                logger.bind(tag=TAG).info(f"会话请求ID为空，跳过Opus消息发送 (索引: {text_index})")
                return

            # 创建音频发送数据
            message_info = ResponseInfoInstant.create_tts_audio_opus_response(
                session_id=self.context.session_id,
                audio_source=audios,
                session_request_id=session_request_id,
                audio_input_format="opus",
                audio_output_format="opus",
            )
            # 通过WebSocket发送音频消息
            await self.send_via_websocket(message_info.to_dict(), "Opus音频消息", session_request_id, channel="audio")
            await asyncio.sleep(0.001)  # 防止网络拥塞

        except asyncio.CancelledError:
            logger.bind(tag=TAG).info(f"Opus消息发送任务被事件驱动中断 (索引: {text_index})")
            raise  # 重新抛出异常
        except Exception:
            logger.bind(tag=TAG).error(f"音频发送未知错误 - 索引: {text_index}, 错误: {traceback.format_exc()}")

            # 其他错误，尝试发送错误消息
            await self.send_error_message(message="音频发送失败", session_request_id=session_request_id)
            # 清理会话状态
            self.context.state_manager.clear_session_state()

            raise

    async def send_via_websocket(
        self, response_dict: dict, message_type: str = "message", session_request_id: str = None, channel: str = "text"
    ) -> bool:
        """
        通过 WebSocket 发送消息

        :param response_dict: 要发送的消息字典
        :param message_type: 消息类型，用于日志记录
        :param session_request_id: 会话请求ID
        :param channel: 通道类型，'text' 或 'audio'，默认为 'text'
        :return: 发送成功返回 True，失败返回 False
        """
        if not session_request_id:
            session_request_id = self.session_request_id
        # 根据通道类型获取对应的 WebSocketAdapter
        if channel == "audio":
            ws_adapter = self.context.audio_websocket
        elif channel == "text":
            ws_adapter = self.context.text_websocket

        # 检查 WebSocket 连接是否可用
        if not ws_adapter or not ws_adapter.is_connected():
            logger.bind(tag=TAG).error(f"{message_type}发送失败 - {channel} WebSocket不可用")
            return False

        try:
            await ws_adapter.send_message(response_dict)
            await asyncio.sleep(0.0001)  # 防阻塞
            logger.bind(tag=TAG).info(
                f"发送:{session_request_id[:10] if session_request_id else 'N/A'}:{message_type} [{channel}]"
            )
            return True
        except WebSocketException as we:
            if we.status_code in [WebSocketStatus.DISCONNECTED, WebSocketStatus.ERROR_CONNECTION_LOST]:
                logger.bind(tag=TAG).error(f"{message_type}发送失败 - 连接已断开")
            else:
                logger.bind(tag=TAG).error(f"{message_type}发送失败 - {we.status_code.name}: {we.message}")
            return False
        except Exception:
            logger.bind(tag=TAG).error(f"{message_type}发送异常: {traceback.format_exc()}")
            return False
