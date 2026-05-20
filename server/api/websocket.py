"""
WebSocket路由模块

处理WebSocket连接，保持与原有架构的完全兼容性。
每个连接创建独立的SessionContext，共享全局服务实例。
"""

import asyncio
from datetime import datetime
import json
import time
import traceback

from api.error import WebSocketErrorHandler
from api.headers import HttpHeaders
from config.logger import setup_logging
from core.connection.websocket_connector import WebSocketConnector
from core.container.service_container import DependencyInjector
from core.global_services import GlobalServices
from core.session.session_orchestrator import SessionOrchestrator
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, status
from fastapi.websockets import WebSocketState

router = APIRouter()
logger = setup_logging()
TAG = __name__


# TODO 测试后删除
async def _create_webrtc_session_context(
    websocket: WebSocket, session_id: str, handler: WebSocketConnector, service_container, config: dict
):
    """
    为WebRTC连接创建SessionContext的最简化实现（测试使用）

    Args:
        websocket: WebSocket连接对象
        session_id: 会话ID
        handler: WebSocketConnector实例
        service_container: 服务容器
        config: 配置字典

    Returns:
        SessionContext: 创建的会话上下文
    """
    try:
        # 构造基础session_info
        headers = dict(websocket.headers) if hasattr(websocket, "headers") else {}

        # 为WebRTC连接生成必要的client信息
        device_id = headers.get("device-id") or f"webrtc_device_{session_id}"
        client_id = f"webrtc_client_{device_id}"

        # 创建客户端目录
        import os

        from config.server_config import ServerConfiger
        from core.utils.util import safe_path_component

        data_dir = os.path.join(ServerConfiger.get_project_dir(), "data")
        device_id_safe = safe_path_component(device_id)
        client_info_dir = os.path.join(data_dir, client_id)
        os.makedirs(client_info_dir, exist_ok=True)

        # 创建会话目录
        client_session_dir = os.path.join(client_info_dir, "sessions", session_id)
        os.makedirs(client_session_dir, exist_ok=True)

        session_info = {
            "session_id": session_id,
            "headers": headers,
            "client_ip": "127.0.0.1",  # WebRTC默认本地连接
            "device_id": device_id,
            "client_id": client_id,
            "client_info_dir": client_info_dir,
            "client_session_dir": client_session_dir,
            "private_service_container": None,  # WebRTC连接使用全局服务
            "private_config": None,  # WebRTC连接暂不使用私有配置
            "is_device_verified": False,  # WebRTC连接默认未验证设备
            "is_new_session": True,
            "is_session_restore": False,
        }

        # 创建SessionContext（直接调用_create_session_context方法）
        session_context = await handler._create_session_context(session_info)

        # 注册SessionContext到全局管理器
        if session_context:
            GlobalServices.register_session_context(session_id, session_context)
            logger.bind(tag=TAG).info(f"✅ WebRTC SessionContext已创建并注册: {session_id}")

            # 启动会话（不启动完整连接，只启动会话逻辑）
            logger.bind(tag=TAG).info(f"🚀 WebRTC会话已启动: {session_id}")

            return session_context
        else:
            raise Exception("SessionContext创建失败")

    except Exception as e:
        logger.bind(tag=TAG).error(f"创建WebRTC SessionContext失败: {e}", exc_info=True)
        raise


@router.websocket("")
async def websocket_endpoint(websocket: WebSocket):
    """
    WebSocket端点 - 保持原有/chat/v1/路径

    处理WebSocket连接的完整生命周期：
    1. 连接建立和认证
    2. 提前获取session_id作为connection_id
    3. 创建独立的SessionContext
    4. 处理消息通信
    5. 连接关闭和资源清理

    Args:
        websocket: WebSocket连接对象
    """
    connection_id = None
    handler = None

    try:
        # 🔍 诊断：在accept之前打印收到的headers
        headers = dict(websocket.headers)
        logger.bind(tag=TAG).info("===========================WebSocket连接请求===========================")
        logger.bind(tag=TAG).info(f"📋 收到的headers: {headers}")
        logger.bind(tag=TAG).info(f"🔍 查找device-id: headers.get('device-id')={headers.get('device-id')}")

        # ✅ 安全修复：在accept之前进行认证
        device_id = headers.get(HttpHeaders.DEVICE_ID)
        token = headers.get(HttpHeaders.AUTHORIZATION)

        logger.bind(tag=TAG).info("===========================认证检查（accept之前）===========================")
        logger.bind(tag=TAG).info(f"客户端认证信息 - device_id: {device_id}, token: {token}")

        # ✅ 认证（封装在静态方法中）
        from core.connection.auth_middleware import AuthMiddleware

        await AuthMiddleware.authenticate_websocket(headers, logger, TAG)

        # ✅ 认证通过后，才accept WebSocket连接
        await websocket.accept()
        logger.bind(tag=TAG).info("===========================WebSocket连接已建立===========================")

        # 🔍 检查是否为测试连接
        is_test_connection = headers.get("x-test-connection") == "true" or headers.get("X-Test-Connection") == "true"

        if is_test_connection:
            # 🧪 测试连接：不创建session，直接返回响应
            logger.bind(tag=TAG).info("🧪 检测到测试连接，跳过session创建")

            # 发送测试成功响应
            test_response = {
                "type": "response.hello",
                "data": {"status": "test_success", "message": "测试连接成功", "server_version": "1.0.0"},
                "timestamp": datetime.now().isoformat(),
            }
            await websocket.send_json(test_response)
            logger.bind(tag=TAG).info("🧪 测试连接响应已发送")

            # 关闭连接
            await websocket.close(code=status.WS_1000_NORMAL_CLOSURE)
            logger.bind(tag=TAG).info("🧪 测试连接已关闭")
            return

        # 正常连接：继续创建session
        # 提前处理session_id，作为connection_id使用
        session_orchestrator = SessionOrchestrator()
        session_id = session_orchestrator.get_or_create_session_id(headers)
        connection_id = session_id  # 直接使用session_id作为连接id

        # 获取全局服务和配置
        service_container = GlobalServices.get_service_container()
        config = GlobalServices.get_config()

        # 创建WebSocketConnector实例，直接传入session_id
        dependency_injector = DependencyInjector(service_container)
        handler = dependency_injector.create(
            WebSocketConnector,
            websocket=websocket,
            config=config,
            session_id=session_id,  # 直接传入session_id
        )

        # 注册连接到全局管理器（使用session_id作为connection_id）
        GlobalServices.register_connection(connection_id, handler)

        logger.bind(tag=TAG).info(f"WebSocket连接建立成功: {connection_id}")
        logger.bind(tag=TAG).info("===========================建立新连接请求===========================")

        # 处理连接
        await handler.start_connection()

    except WebSocketDisconnect:
        logger.bind(tag=TAG).info(f"WebSocket连接断开: {connection_id}")
    except Exception as e:
        logger.bind(tag=TAG).error(f"WebSocket连接处理错误: {e}")

        # 检测配置错误类型
        is_config_error = isinstance(e, (FileNotFoundError, RuntimeError))

        # 发送错误响应
        try:
            if websocket.application_state == WebSocketState.CONNECTED:
                error_response = WebSocketErrorHandler.create_connection_error(
                    message=f"连接处理错误: {str(e)}",
                    details={
                        "connection_id": connection_id,
                        "error_type": type(e).__name__,
                        "is_config_error": is_config_error,
                    },
                )
                await websocket.send_json(error_response)
                await websocket.close(code=status.WS_1011_INTERNAL_ERROR)
        except Exception as send_error:
            logger.bind(tag=TAG).error(f"发送错误响应失败: {send_error}")
    finally:
        # 清理连接
        if connection_id:
            GlobalServices.unregister_connection(connection_id)

        # 清理处理器资源
        if handler and hasattr(handler, "cleanup"):
            try:
                await handler.cleanup()
            except Exception as cleanup_error:
                logger.bind(tag=TAG).warning(f"连接处理器清理失败: {cleanup_error}")


@router.websocket("/test")
async def websocket_test_endpoint(websocket: WebSocket):
    """
    WebSocket测试端点

    用于测试WebSocket连接的基本功能，不涉及复杂的业务逻辑。

    Args:
        websocket: WebSocket连接对象
    """
    connection_id = None

    try:
        await websocket.accept()
        client_info = websocket.client
        connection_id = f"test_{client_info.host}:{client_info.port}" if client_info else "test_unknown"

        logger.bind(tag=TAG).info(f"WebSocket测试连接建立: {connection_id}")

        # 发送欢迎消息
        welcome_message = {
            "type": "test_welcome",
            "message": "WebSocket测试连接已建立",
            "connection_id": connection_id,
            "timestamp": asyncio.get_event_loop().time(),
        }
        await websocket.send_json(welcome_message)

        # 简单的echo服务
        while True:
            try:
                # 接收消息
                message = await websocket.receive_json()

                logger.bind(tag=TAG).debug(f"测试连接收到消息: {message}")

                # 构造响应
                response = {
                    "type": "test_echo",
                    "echo": message,
                    "connection_id": connection_id,
                    "timestamp": asyncio.get_event_loop().time(),
                }

                # 发送响应
                await websocket.send_json(response)

            except WebSocketDisconnect:
                break
            except Exception as e:
                logger.bind(tag=TAG).error(f"测试连接消息处理错误: {e}")
                break

    except WebSocketDisconnect:
        logger.bind(tag=TAG).info(f"WebSocket测试连接断开: {connection_id}")
    except Exception as e:
        logger.bind(tag=TAG).error(f"WebSocket测试连接错误: {e}")
    finally:
        logger.bind(tag=TAG).info(f"WebSocket测试连接清理完成: {connection_id}")


@router.get("/connections")
async def get_websocket_connections():
    """
    获取当前活跃的WebSocket连接统计和管理API

    Returns:
        Dict[str, Any]: 连接统计信息
    """
    try:
        active_connections = GlobalServices.get_active_connections_count()
        connection_ids = GlobalServices.get_connection_ids()

        return {
            "status": "success",
            "active_connections": active_connections,
            "connection_ids": connection_ids[:20],  # 只显示前20个
            "total_connections": len(connection_ids),
            "timestamp": asyncio.get_event_loop().time(),
        }

    except Exception as e:
        logger.bind(tag=TAG).error(f"获取WebSocket连接信息失败: {e}")
        return {
            "status": "error",
            "message": f"获取连接信息失败: {str(e)}",
            "active_connections": 0,
            "connection_ids": [],
            "timestamp": asyncio.get_event_loop().time(),
        }


@router.websocket("/webrtc")  # 注意这里的"/"， 如果尾缀有则请求地址中也需要。
async def webrtc_endpoint(websocket: WebSocket):
    """
    WebRTC端点 - 创建SessionContext并处理连接

    ✅ 安全修复：在accept之前进行认证
    """
    # ✅ 获取session_id，支持标准请求头 X-Session-Id (注意小写d)
    session_id = None
    is_new_session = False
    handler = None

    # 从标准请求头获取session_id (与项目保持一致)
    session_id = websocket.headers.get("x-session-id") or websocket.headers.get("X-Session-Id")

    # ✅ 安全修复：在accept之前进行认证（如果需要）
    headers = dict(websocket.headers)

    # ✅ 认证（封装在静态方法中）
    from core.connection.auth_middleware import AuthMiddleware

    await AuthMiddleware.authenticate_websocket(headers, logger, TAG)

    # ✅ 认证通过后，才accept WebSocket连接
    await websocket.accept()

    # 如果没有session_id，创建一个新的
    if not session_id:
        import uuid

        session_id = f"session_{uuid.uuid4().hex[:12]}_{int(time.time())}"
        is_new_session = True
        logger.bind(tag=TAG).info(f"🆔 为新连接创建session_id: {session_id}")
    else:
        logger.bind(tag=TAG).info(f"📋 使用前端提供的session_id: {session_id}")

    try:
        # 获取全局服务和配置
        service_container = GlobalServices.get_service_container()
        config = GlobalServices.get_config()

        # 创建WebSocketConnector实例来处理SessionContext
        dependency_injector = DependencyInjector(service_container)
        handler = dependency_injector.create(
            WebSocketConnector,
            websocket=websocket,
            config=config,
            session_id=session_id,
        )

        # 注册连接到全局管理器
        GlobalServices.register_connection(session_id, handler)
        logger.bind(tag=TAG).info(f"🔗 WebRTC连接已注册: {session_id}")

        # 创建并注册SessionContext - 简化实现，直接内联逻辑
        await _create_webrtc_session_context(websocket, session_id, handler, service_container, config)

        # 发送连接确认消息，包含session_id信息
        connection_message = {
            "role": "system",
            "content": f"WebRTC WebSocket连接已建立，会话ID: {session_id}",
            "type": "connection_established",
            "session_id": session_id,
            "is_new_session": is_new_session,
            "timestamp": time.time(),
        }
        await websocket.send_text(json.dumps(connection_message))

        logger.bind(tag=TAG).info(f"📡 WebRTC WebSocket连接已建立: {session_id}")

        # 发送测试消息
        test_message = {
            "role": "infolog",
            "content": "这是一条后端测试消息，如果您能看到这条消息，说明WebRTC WebSocket连接正常工作",
            "type": "backend_test",
            "session_id": session_id,
            "timestamp": time.time(),
        }
        await websocket.send_text(json.dumps(test_message))
        logger.bind(tag=TAG).info("📡 发送WebRTC WebSocket欢迎和测试消息")

        # 保持连接活跃，处理后续消息
        while True:
            try:
                data = await websocket.receive_text()
                try:
                    message = json.loads(data)
                    if message.get("type") == "websocket_test":
                        response = {
                            "role": "infolog",
                            "content": f"收到WebSocket测试消息: {message.get('content', '')}",
                            "type": "websocket_test_reply",
                            "session_id": session_id,
                            "timestamp": time.time(),
                        }
                        await websocket.send_text(json.dumps(response))
                        logger.bind(tag=TAG).info(f"回复WebRTC WebSocket测试消息: {session_id}")
                except json.JSONDecodeError:
                    logger.bind(tag=TAG).debug(f"收到非JSON消息: {data}")
            except Exception as e:
                logger.bind(tag=TAG).debug(f"WebRTC WebSocket接收消息错误: {e}")
                break

    except WebSocketDisconnect:
        logger.bind(tag=TAG).info(f"WebRTC WebSocket连接断开: {session_id}")
    except Exception as e:
        logger.bind(tag=TAG).error(f"WebRTC WebSocket错误: {e}", exc_info=True)

        # 检测配置错误类型
        is_config_error = isinstance(e, (FileNotFoundError, RuntimeError))

        # 发送错误响应
        try:
            if websocket.application_state == WebSocketState.CONNECTED:
                error_response = WebSocketErrorHandler.create_connection_error(
                    message=f"WebRTC连接处理错误: {str(e)}",
                    details={
                        "connection_id": session_id,
                        "error_type": type(e).__name__,
                        "is_config_error": is_config_error,
                    },
                )
                await websocket.send_json(error_response)
                await websocket.close(code=status.WS_1011_INTERNAL_ERROR)
        except Exception as send_error:
            logger.bind(tag=TAG).error(f"发送错误响应失败: {send_error}")
    finally:
        # 清理连接
        GlobalServices.unregister_connection(session_id)
        logger.bind(tag=TAG).info(f"📡 WebRTC WebSocket连接已移除: {session_id}")

        # 清理处理器资源
        if handler and hasattr(handler, "cleanup"):
            try:
                await handler.cleanup()
            except Exception as cleanup_error:
                logger.bind(tag=TAG).warning(f"WebRTC连接处理器清理失败: {cleanup_error}")


@router.websocket("/audio")
async def websocket_audio_endpoint(websocket: WebSocket):
    """
    音频专用WebSocket端点 - 专门处理TTS Opus音频流

    完整路径: /chat/v1/audio/

    与文本通道共享同一个SessionContext，通过相同的session_id实现复用。
    这个路由只处理音频消息，避免文本和音频交叉发送导致的播放间断问题。

    注意：
    - 不涉及WebRTC相关内容
    - 必须提供与文本通道一致的session_id
    - 会复用已存在的SessionContext

    Args:
        websocket: WebSocket连接对象
    """
    connection_id = None
    handler = None

    try:
        # ✅ 安全修复：在accept之前进行认证和验证
        headers = dict(websocket.headers)
        device_id = headers.get(HttpHeaders.DEVICE_ID)
        token = headers.get(HttpHeaders.AUTHORIZATION)

        # 🔑 关键：必须提供session_id（与文本通道一致）
        session_id = headers.get("x-session-id") or headers.get("X-Session-Id")

        if not session_id:
            # 音频通道必须提供session_id，无法创建新会话
            logger.bind(tag=TAG).warning("音频WebSocket连接缺少session_id，拒绝连接")
            # WebSocket未accept，直接返回
            return

        connection_id = f"audio_{session_id}"

        logger.bind(tag=TAG).info("===========================音频WebSocket连接请求===========================")
        logger.bind(tag=TAG).info(f"音频通道连接 - session_id: {session_id}, device_id: {device_id}, token: {token}")

        # ✅ 认证（封装在静态方法中）
        from core.connection.auth_middleware import AuthMiddleware

        await AuthMiddleware.authenticate_websocket(headers, logger, TAG)

        # ✅ 认证通过后，才accept WebSocket连接
        await websocket.accept()
        logger.bind(tag=TAG).info("===========================音频WebSocket连接已建立===========================")

        # 获取全局服务和配置
        service_container = GlobalServices.get_service_container()
        config = GlobalServices.get_config()

        # 🆕 创建WebSocketConnector实例，传递channel_type参数
        dependency_injector = DependencyInjector(service_container)
        handler = dependency_injector.create(
            WebSocketConnector,
            websocket=websocket,
            config=config,
            session_id=session_id,  # 使用与文本通道相同的session_id
            channel_type="audio",  # 🆕 传递通道类型
        )

        # 注册连接到全局管理器
        GlobalServices.register_connection(connection_id, handler)

        logger.bind(tag=TAG).info("===========================音频WebSocket连接建立===========================")

        # 处理连接（会自动复用已存在的SessionContext）
        await handler.start_connection()

    except WebSocketDisconnect:
        logger.bind(tag=TAG).info(f"音频WebSocket连接断开: {connection_id}")
    except Exception as e:
        logger.bind(tag=TAG).error(f"音频WebSocket连接处理错误: {traceback.format_exc()}")

        # 检测配置错误类型
        is_config_error = isinstance(e, (FileNotFoundError, RuntimeError))

        # 发送错误响应
        try:
            if websocket.application_state == WebSocketState.CONNECTED:
                error_response = WebSocketErrorHandler.create_connection_error(
                    message=f"音频连接处理错误: {str(e)}",
                    details={
                        "connection_id": connection_id,
                        "error_type": type(e).__name__,
                        "is_config_error": is_config_error,
                    },
                )
                await websocket.send_json(error_response)
                await websocket.close(code=status.WS_1011_INTERNAL_ERROR)
        except Exception as send_error:
            logger.bind(tag=TAG).error(f"发送错误响应失败: {send_error}")
    finally:
        # 清理连接
        if connection_id:
            GlobalServices.unregister_connection(connection_id)

        # 清理处理器资源
        if handler and hasattr(handler, "cleanup"):
            try:
                await handler.cleanup()
            except Exception as cleanup_error:
                logger.bind(tag=TAG).warning(f"音频连接处理器清理失败: {cleanup_error}")
