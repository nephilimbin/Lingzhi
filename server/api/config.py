"""
配置管理API模块

提供WebSocket连接测试和WebRTC配置管理功能。
"""

import asyncio
from datetime import datetime
import ssl
from typing import Any, Dict, List, Optional

from api.error import ErrorLogger, HTTPErrorHandler
from config.logger import setup_logging
from core.global_services import GlobalServices
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
import websockets.client

router = APIRouter()
logger = setup_logging()
TAG = __name__


# 请求/响应模型


class ModulesResponse(BaseModel):
    """模块列表响应模型"""

    success: bool
    message: str
    modules: Dict[str, List[Dict[str, Any]]] = {}
    default_selected_module: Dict[str, str] = {}
    timestamp: str = datetime.utcnow().isoformat()


class ConnectionTestRequest(BaseModel):
    """连接测试请求模型"""

    server_url: str
    mac_address: str
    token: Optional[str] = None


class ConnectionErrorType:
    """连接错误类型常量"""

    INVALID_FORMAT = "invalid_format"  # URL格式错误（不是ws://或wss://开头）
    PATH_DUPLICATION = "path_duplication"  # 路径重复（已包含/chat/v1）
    INVALID_HOST = "invalid_host"  # 主机地址无效
    MISSING_PATH = "missing_path"  # 缺少路径
    CONNECTION_TIMEOUT = "connection_timeout"  # 连接超时
    CONNECTION_REFUSED = "connection_refused"  # 连接被拒绝
    HANDSHAKE_FAILED = "handshake_failed"  # 握手失败
    AUTH_FAILED = "auth_failed"  # 认证失败
    PROTOCOL_MISMATCH = "protocol_mismatch"  # 协议不匹配（ws://与wss://）


class ConnectionTestResponse(BaseModel):
    """连接测试响应模型"""

    success: bool
    message: str
    error_type: Optional[str] = None  # 新增：错误类型
    details: Optional[Dict[str, Any]] = None
    timestamp: str = datetime.utcnow().isoformat()


@router.get("/health")
async def health_check():
    """配置管理API健康检查接口"""
    return {"status": "ok", "message": "配置管理API正在运行"}


@router.get("/server-info")
async def get_server_info():
    """
    获取服务器配置信息

    返回服务器的SSL状态和推荐连接协议，帮助前端正确配置连接。
    """
    try:
        from config.server_config import ServerConfiger

        config = ServerConfiger.load_config()
        ssl_config = config.get("server", {}).get("ssl", {})
        ssl_enabled = ssl_config.get("enabled", False)
        server_config = config.get("server", {})
        port = server_config.get("port", 8000)

        return {
            "success": True,
            "ssl_enabled": ssl_enabled,
            "recommended_protocol": "wss" if ssl_enabled else "ws",
            "recommended_port": port,
            "message": "服务器已启用SSL加密，建议使用 wss:// 协议"
            if ssl_enabled
            else "服务器未启用SSL加密，建议使用 ws:// 协议",
            "timestamp": datetime.utcnow().isoformat(),
        }
    except Exception as e:
        logger.bind(tag=TAG).error(f"获取服务器信息失败: {e}")
        raise HTTPException(
            status_code=500,
            detail=HTTPErrorHandler.create_internal_error(message="获取服务器配置信息失败", details={"error": str(e)}),
        )


@router.get("/modules", response_model=ModulesResponse)
async def get_available_modules():
    """
    获取可用的模块列表

    Returns:
        ModulesResponse: 可用模块列表

    Raises:
        HTTPException: 获取模块列表失败时
    """
    try:
        # 获取全局配置
        config = GlobalServices.get_config()

        logger.bind(tag=TAG).info("获取可用模块列表请求")

        modules = {}

        # 获取各种模块类型
        for module_type in ["VAD", "ASR", "LLM", "TTS", "Memory", "Intent", "VLM"]:
            # Intent 模块使用与 LLM 相同的模型列表
            if module_type == "Intent":
                if "LLM" in config:
                    modules[module_type] = []
                    for module_name, module_config in config["LLM"].items():
                        modules[module_type].append(
                            {
                                "name": module_name,
                                "type": module_config.get("type", module_name),
                                "model_name": module_config.get("model_name", ""),
                                "description": f"{module_name} 模块",
                                "enabled": module_config.get("enabled", True),
                            }
                        )
            elif module_type in config:
                modules[module_type] = []
                for module_name, module_config in config[module_type].items():
                    modules[module_type].append(
                        {
                            "name": module_name,
                            "type": module_config.get("type", module_name),
                            "model_name": module_config.get("model_name", ""),
                            "description": f"{module_name} 模块",
                            "enabled": module_config.get("enabled", True),
                        }
                    )

        logger.bind(tag=TAG).info(f"可用模块列表获取成功，共 {len(modules)} 种模块类型")

        # 获取系统默认配置
        default_selected_module = config.get("selected_module", {})

        return ModulesResponse(
            success=True,
            message="可用模块列表获取成功",
            modules=modules,
            default_selected_module=default_selected_module,
        )

    except Exception as e:
        ErrorLogger.log_http_error(
            error_code="MODULES_GET_ERROR",
            message=f"获取可用模块失败: {str(e)}",
            request_path="/config/modules",
            method="GET",
            details={"error": str(e)},
        )
        raise HTTPException(
            status_code=500,
            detail=HTTPErrorHandler.create_internal_error(message="获取模块列表时出错", details={"error": str(e)}),
        )


@router.get("/info")
async def get_config_info():
    """
    获取配置管理服务信息

    Returns:
        Dict[str, Any]: 配置管理服务信息
    """
    try:
        # 获取配置信息
        config = GlobalServices.get_config()

        return {
            "service_name": "配置管理API",
            "version": "1.0.0",
            "description": "WebSocket连接测试和WebRTC配置管理服务",
            "features": ["WebSocket连接测试", "WebRTC配置管理", "模块查询"],
            "supported_endpoints": [
                "POST /api/v1/config/test-connection",
                "GET /api/v1/config/modules",
                "GET /api/v1/config/health",
                "GET /api/v1/config/info",
                "GET /api/v1/config/webrtc",
            ],
            "config_info": {
                "server_config_loaded": config is not None,
                "available_modules": list(config.keys()) if config else [],
            },
            "timestamp": datetime.utcnow().isoformat(),
        }

    except Exception as e:
        logger.bind(tag=TAG).error(f"获取配置管理信息失败: {e}")
        raise HTTPException(
            status_code=500,
            detail=HTTPErrorHandler.create_internal_error(message="获取配置管理信息失败", details={"error": str(e)}),
        )


@router.post("/test-connection", response_model=ConnectionTestResponse)
async def test_connection(request: ConnectionTestRequest):
    """
    测试WebSocket服务器连接

    验证指定的WebSocket服务器是否可达，并进行握手测试。
    仅测试文本通道连接，快速验证服务器配置是否正确。

    Args:
        request: 连接测试请求

    Returns:
        ConnectionTestResponse: 测试结果
    """
    try:
        logger.bind(tag=TAG).info(f"连接测试请求: server_url={request.server_url}, mac_address={request.mac_address}")

        # ========== URL校验 ==========
        url = request.server_url.strip()

        # 检查协议
        if not url.startswith(("ws://", "wss://")):
            logger.bind(tag=TAG).warning("URL校验失败: 不是ws://或wss://开头")
            return ConnectionTestResponse(
                success=False,
                message="请输入有效的服务器地址（ws://或wss://开头）",
                error_type=ConnectionErrorType.INVALID_FORMAT,
            )

        # ========== SSL协议匹配检查 ==========
        from config.server_config import ServerConfiger

        config = ServerConfiger.load_config()
        ssl_enabled = config.get("server", {}).get("ssl", {}).get("enabled", False)
        uses_wss = url.startswith("wss://")

        # 检查协议是否与SSL配置匹配
        if ssl_enabled and not uses_wss:
            logger.bind(tag=TAG).warning("协议不匹配: 后端启用SSL但用户使用ws://")
            return ConnectionTestResponse(
                success=False,
                message="服务器已启用SSL加密，请使用 wss:// 协议连接",
                error_type=ConnectionErrorType.PROTOCOL_MISMATCH,
            )
        elif not ssl_enabled and uses_wss:
            logger.bind(tag=TAG).warning("协议不匹配: 后端未启用SSL但用户使用wss://")
            return ConnectionTestResponse(
                success=False,
                message="服务器未启用SSL加密，请使用 ws:// 协议连接",
                error_type=ConnectionErrorType.PROTOCOL_MISMATCH,
            )

        # 检查URL格式和主机
        try:
            from urllib.parse import urlparse

            parsed = urlparse(url)

            # 检查主机
            if not parsed.netloc or not parsed.hostname:
                logger.bind(tag=TAG).warning("URL校验失败: 主机地址无效")
                return ConnectionTestResponse(
                    success=False,
                    message="服务器地址无效，请检查主机名",
                    error_type=ConnectionErrorType.INVALID_HOST,
                )

            # 检查路径（灵活校验：只要有路径即可，不限制具体内容）
            path = parsed.path.rstrip("/")
            if not path or path == "/":
                logger.bind(tag=TAG).warning("URL校验失败: 缺少路径")
                return ConnectionTestResponse(
                    success=False,
                    message="请输入完整的服务器地址，例如：ws://192.168.1.2:8000/chat/v1",
                    error_type=ConnectionErrorType.MISSING_PATH,
                )

        except Exception as e:
            logger.bind(tag=TAG).error(f"URL解析失败: {e}")
            return ConnectionTestResponse(
                success=False, message=f"URL解析失败: {str(e)}", error_type=ConnectionErrorType.INVALID_FORMAT
            )

        # URL校验通过，直接使用用户输入的URL
        ws_url = url
        logger.bind(tag=TAG).info(f"测试连接URL: {ws_url}")

        # 构建请求头
        headers = {}
        if request.token:
            headers["Authorization"] = f"Bearer {request.token}"
        # ✅ 添加device-id头部（用于测试连接时的认证）
        if request.mac_address:
            headers["device-id"] = request.mac_address
            logger.bind(tag=TAG).info(f"📋 测试连接添加device-id头部: {request.mac_address}")
        # ✅ 添加测试连接标记（避免创建完整session）
        headers["X-Test-Connection"] = "true"
        logger.bind(tag=TAG).info("🧪 添加测试连接标记: X-Test-Connection=true")

        # 记录开始时间
        start_time = datetime.utcnow()

        try:
            # 检查是否为WSS连接
            is_wss = ws_url.startswith("wss://")

            # 创建SSL上下文（用于WSS连接）
            ssl_context = None
            if is_wss:
                # 在开发环境中，允许自签名证书
                ssl_context = ssl.create_default_context()
                ssl_context.check_hostname = False
                ssl_context.verify_mode = ssl.CERT_NONE
                logger.bind(tag=TAG).info("使用SSL上下文（允许自签名证书）")

            # 建立WebSocket连接（5秒超时）
            async with websockets.client.connect(
                ws_url,
                extra_headers=headers,
                timeout=5,
                ping_interval=None,
                ssl=ssl_context,
            ) as websocket:
                connection_time = (datetime.utcnow() - start_time).total_seconds() * 1000
                logger.bind(tag=TAG).info(f"WebSocket连接建立成功，耗时: {connection_time:.0f}ms")

                # 🧪 测试连接：等待服务器主动发送的响应（不需要发送hello）
                try:
                    response = await asyncio.wait_for(websocket.recv(), timeout=3.0)
                    handshake_time = (datetime.utcnow() - start_time).total_seconds() * 1000

                    # 尝试解析响应
                    try:
                        response_data = __import__("json").loads(response)
                        response_type = response_data.get("type", "")

                        # 连接测试成功 = 能建立连接 + 收到任何有效JSON响应
                        if response_type == "response.hello":
                            # 理想情况：握手成功
                            data = response_data.get("data", {})
                            status = data.get("status", "success")
                            server_version = data.get("server_version", "1.0.0")

                            logger.bind(tag=TAG).info(
                                f"测试连接成功: status={status}, server_version={server_version}, 握手耗时: {handshake_time:.0f}ms"
                            )

                            return ConnectionTestResponse(
                                success=True,
                                message="连接成功",
                                details={
                                    "handshake_time": round(handshake_time),
                                    "connection_time": round(connection_time),
                                    "server_version": server_version,
                                },
                            )
                        else:
                            # 其他响应类型也视为连接成功
                            logger.bind(tag=TAG).info(f"测试连接成功，收到响应类型: {response_type}")
                            return ConnectionTestResponse(
                                success=True,
                                message="连接成功",
                                details={
                                    "handshake_time": round(handshake_time),
                                    "connection_time": round(connection_time),
                                    "response_type": response_type,
                                },
                            )
                    except __import__("json").JSONDecodeError:
                        logger.bind(tag=TAG).warning(f"无法解析服务器响应: {response[:100]}")
                        return ConnectionTestResponse(success=False, message="服务器响应格式错误")

                except asyncio.TimeoutError:
                    logger.bind(tag=TAG).warning("等待服务器响应超时")
                    return ConnectionTestResponse(
                        success=False,
                        message="服务器响应超时，请检查服务器是否正常运行",
                        error_type=ConnectionErrorType.HANDSHAKE_FAILED,
                    )

        except __import__("websockets").exceptions.InvalidURI as e:
            logger.bind(tag=TAG).warning(f"无效的WebSocket URL: {e}")
            return ConnectionTestResponse(
                success=False, message="服务器地址格式无效", error_type=ConnectionErrorType.INVALID_FORMAT
            )

        except __import__("websockets").exceptions.InvalidHandshake as e:
            # 解析握手失败的具体原因
            error_msg = str(e)
            logger.bind(tag=TAG).warning(f"WebSocket握手失败: {error_msg}")

            # 从异常消息中提取HTTP状态码
            status_code = None
            if "HTTP 401" in error_msg or "401" in error_msg:
                status_code = 401
            elif "HTTP 403" in error_msg or "403" in error_msg:
                status_code = 403
            elif "HTTP 500" in error_msg or "500" in error_msg:
                # 后端返回500，通常是认证失败
                # ⚠️ 注意：WebSocket端点的认证异常会被转换为HTTP 500
                status_code = 500
                # 检查是否是认证场景（有token且有device-id）
                if request.token:
                    return ConnectionTestResponse(
                        success=False,
                        message="认证失败，请检查Token和MAC地址配置",
                        error_type=ConnectionErrorType.AUTH_FAILED,
                    )
                else:
                    return ConnectionTestResponse(
                        success=False,
                        message="连接被拒绝，请检查Token和服务器配置",
                        error_type=ConnectionErrorType.AUTH_FAILED,
                    )

            # 根据状态码返回具体的错误提示
            if status_code == 401:
                # 认证失败：可能是token错误或device-id错误
                if not request.token:
                    return ConnectionTestResponse(
                        success=False,
                        message="Token认证失败，请检查Token是否正确",
                        error_type=ConnectionErrorType.AUTH_FAILED,
                    )
                else:
                    return ConnectionTestResponse(
                        success=False,
                        message="认证失败，请检查Token和MAC地址是否正确配置",
                        error_type=ConnectionErrorType.AUTH_FAILED,
                    )
            elif status_code == 403:
                # 权限拒绝
                return ConnectionTestResponse(
                    success=False,
                    message="访问被拒绝，请检查Token权限",
                    error_type=ConnectionErrorType.AUTH_FAILED,
                )
            else:
                # 其他握手失败
                return ConnectionTestResponse(
                    success=False,
                    message=f"连接被拒绝: {error_msg}",
                    error_type=ConnectionErrorType.HANDSHAKE_FAILED,
                )

        except (OSError, ConnectionRefusedError) as e:
            logger.bind(tag=TAG).warning(f"连接被拒绝: {e}")
            return ConnectionTestResponse(
                success=False,
                message="服务器不可达，请检查地址和网络",
                error_type=ConnectionErrorType.CONNECTION_REFUSED,
            )

        except asyncio.TimeoutError:
            logger.bind(tag=TAG).warning("连接超时")
            return ConnectionTestResponse(
                success=False, message="连接超时，服务器可能未启动", error_type=ConnectionErrorType.CONNECTION_TIMEOUT
            )

        except Exception as e:
            logger.bind(tag=TAG).error(f"连接测试失败: {e}")
            return ConnectionTestResponse(success=False, message=f"连接失败: {str(e)}")

    except Exception as e:
        ErrorLogger.log_http_error(
            error_code="CONNECTION_TEST_ERROR",
            message=f"连接测试失败: {str(e)}",
            request_path="/config/test-connection",
            method="POST",
            details={
                "server_url": request.server_url,
                "mac_address": request.mac_address,
                "error": str(e),
            },
        )
        raise HTTPException(
            status_code=500,
            detail=HTTPErrorHandler.create_internal_error(message="连接测试时出错", details={"error": str(e)}),
        )


@router.get("/webrtc")
async def get_webrtc_config():
    """
    获取全局 WebRTC 配置

    返回服务器全局的 WebRTC RTC 配置，供前端使用。
    不需要 session_id，因为这是全局共享的配置。

    Returns:
        Dict[str, Any]: WebRTC RTC 配置
    """
    try:
        from config.server_config import ServerConfiger

        # 加载全局配置
        config = ServerConfiger.load_config()
        webrtc_config = config.get("server", {}).get("webrtc", {})

        # 构建符合 WebRTC 标准的响应格式
        ice_servers = webrtc_config.get("ice_servers", [{"urls": ["stun:stun.l.google.com:19302"]}])

        result = {
            "iceServers": ice_servers,
            "iceCandidatePoolSize": webrtc_config.get("ice_candidate_pool_size", 4),
            "iceTransportPolicy": webrtc_config.get("ice_transport_policy", "all"),
            "bundlePolicy": webrtc_config.get("bundle_policy", "max-bundle"),
            "rtcpMuxPolicy": webrtc_config.get("rtcp_mux_policy", "require"),
        }

        logger.bind(tag=TAG).info("全局 WebRTC 配置获取成功")

        return {
            "success": True,
            "message": "全局 WebRTC 配置获取成功",
            "config": result,
            "timestamp": datetime.utcnow().isoformat(),
        }

    except Exception as e:
        ErrorLogger.log_http_error(
            error_code="WEBRTC_CONFIG_GET_ERROR",
            message=f"获取全局 WebRTC 配置失败: {str(e)}",
            request_path="/config/webrtc",
            method="GET",
            details={"error": str(e)},
        )
        raise HTTPException(
            status_code=500,
            detail=HTTPErrorHandler.create_internal_error(message="获取 WebRTC 配置时出错", details={"error": str(e)}),
        )
