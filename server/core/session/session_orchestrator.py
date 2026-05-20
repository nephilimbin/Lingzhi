import os
import traceback
from typing import Any, Dict, Optional, Tuple
from urllib.parse import parse_qs, urlparse

from api.headers import HttpHeaders
from config.logger import setup_logging
from config.private_config import PrivateConfiger
from config.server_config import ServerConfiger
from core.utils.util import safe_path_component, set_unique_id

TAG = __name__


class SessionOrchestrator:
    """会话编排器 - 统一管理会话的完整生命周期，包括基础设置和私有配置"""

    def __init__(self):
        self.logger = setup_logging()

    async def initialize_session_info(
        self, websocket, config: Dict[str, Any], session_id: str = None
    ) -> Dict[str, Any]:
        """
        完整的会话初始化，支持传入已存在的session_id

        Args:
            websocket: WebSocket连接对象
            config: 全局配置
            session_id: 已存在的session_id（可选）

        Returns:
            dict: 包含所有session相关信息的字典，包括私有配置和服务实例
        """
        try:
            # 基础会话设置
            headers, client_ip, device_id = self._setup_headers_and_auth(websocket)
            client_id, client_info_dir = self._setup_session_directories(headers)

            # 如果没有传入session_id，则创建新的
            if not session_id:
                session_id = self.get_or_create_session_id(headers)

            # 创建目录和检查恢复状态
            client_session_dir, is_session_restore = self.create_session_directory_and_check_restore(
                session_id, client_info_dir, headers
            )

            # 加载私有配置和创建私有服务实例
            private_config, is_device_verified = await self._load_private_config(
                headers, config, client_session_dir, session_id
            )

            # 创建私有服务容器
            private_service_container = None
            if private_config:
                device_id_safe = safe_path_component(device_id) if device_id else "unknown"

                # 如果设备已验证，更新最后聊天时间
                if is_device_verified:
                    await private_config.update_last_chat_time()

                # 创建私有服务容器
                private_service_container = private_config.create_private_service_container()
                if private_service_container:
                    services = private_service_container.get_all_services()
                    active_instances = len([s for s in services.values() if s is not None])
                    self.logger.bind(tag=TAG).info(f"为设备 {device_id_safe} 创建了 {active_instances} 个私有服务实例")

            # 4. 返回完整的会话信息
            session_info = {
                "headers": headers,
                "client_ip": client_ip,
                "device_id": device_id,
                "client_id": client_id,
                "client_info_dir": client_info_dir,
                "session_id": session_id,
                "client_session_dir": client_session_dir,
                "is_session_restore": is_session_restore,
                "private_config": private_config,
                "is_device_verified": is_device_verified,
                "private_service_container": private_service_container,
            }

            return session_info

        except Exception as e:
            self.logger.bind(tag=TAG).error(f"初始私有会话时出错: {e}, 追踪: {traceback.format_exc()}")
            raise

    def _setup_headers_and_auth(self, websocket) -> Tuple[Dict[str, str], str, str]:
        """
        设置headers和认证信息

        功能：
            - 适配FastAPI WebSocket和websockets库的不同实现
            - 从headers或URL参数中提取device-id、client-id和token
            - 将URL参数中的token转换为Authorization header

        Returns:
            Tuple[Dict[str, str], str, str]: (headers字典, 客户端IP, 设备ID)
        """
        # 适配FastAPI WebSocket和websockets库
        if hasattr(websocket, "request"):
            # websockets库的WebSocket对象
            raw_headers = dict(websocket.request.headers)
            client_ip = websocket.remote_address[0]
            parsed_url = urlparse(websocket.request.path)
        else:
            # FastAPI的WebSocket对象
            raw_headers = dict(websocket.headers)
            client_ip = websocket.client.host if websocket.client else "unknown"
            parsed_url = None

        headers = {k.lower(): v for k, v in raw_headers.items()}
        self.logger.bind(tag=TAG).info(f"服务端响应头: {raw_headers}")

        # 首先尝试从headers中获取device_id
        device_id = headers.get(HttpHeaders.DEVICE_ID)

        # 处理URL参数中的device-id、client-id和token
        try:
            if parsed_url:
                # websockets库环境：从解析的URL获取查询参数（parse_qs返回列表）
                query_params = parse_qs(parsed_url.query)
                is_parsed_qs = True  # 标记为parse_qs结果
            elif hasattr(websocket, "query_params"):
                # FastAPI环境：直接访问query_params属性（已经是字典）
                query_params = dict(websocket.query_params)
                is_parsed_qs = False  # 标记为普通字典
            else:
                query_params = {}
                is_parsed_qs = False

            # 处理device-id参数
            if not device_id and query_params:
                device_id = query_params.get("device-id")
                if is_parsed_qs:
                    device_id = device_id[0] if device_id else None  # parse_qs返回列表
                if device_id:
                    headers[HttpHeaders.DEVICE_ID] = device_id
                    self.logger.bind(tag=TAG).info(f"从URL参数获取device-id: {device_id}")

            # 处理client-id参数
            if query_params:
                client_id = query_params.get("client-id")
                if is_parsed_qs:
                    client_id = client_id[0] if client_id else None  # parse_qs返回列表
                if client_id:
                    headers["client-id"] = client_id
                    self.logger.bind(tag=TAG).info(f"从URL参数获取client-id: {client_id}")

            # 处理token参数：如果Authorization header不存在，从URL参数获取
            if HttpHeaders.AUTHORIZATION not in headers and query_params:
                token = query_params.get("token")
                if is_parsed_qs:
                    token = token[0] if token else None  # parse_qs返回列表
                if token:
                    headers[HttpHeaders.AUTHORIZATION] = f"{HttpHeaders.AUTHORIZATION_BEARER_PREFIX}{token}"
                    self.logger.bind(tag=TAG).info(f"从URL参数获取token并添加到headers: {token}")

        except Exception as e:
            self.logger.bind(tag=TAG).warning(f"解析URL参数时出错: {e}, 追踪: {traceback.format_exc()}")

        return headers, client_ip, device_id

    def _setup_session_directories(self, headers: Dict[str, str]) -> Tuple[str, str]:
        """创建客户端相关目录"""
        try:
            data_dir = os.path.join(ServerConfiger.get_project_dir(), "data")
            device_id_safe = safe_path_component(headers.get(HttpHeaders.DEVICE_ID))
            client_id = f"{device_id_safe}"
            client_info_dir = os.path.join(data_dir, client_id)
            os.makedirs(client_info_dir, exist_ok=True)
        except Exception as e:
            self.logger.bind(tag=TAG).error(f"创建客户端目录时出错: {e}, 追踪: {traceback.format_exc()}")
            raise

        return client_id, client_info_dir

    def _setup_session_id(self, headers: Dict[str, str], client_info_dir: str) -> Tuple[str, str, bool]:
        """设置session_id并返回是否为恢复的session"""
        client_provided_session_id = headers.get(HttpHeaders.X_SESSION_ID)
        is_session_restore = False
        try:
            if client_provided_session_id:
                session_id = safe_path_component(client_provided_session_id)
                client_session_dir = os.path.join(client_info_dir, session_id)
                # 检查现有session历史是否存在
                if os.path.exists(client_session_dir):
                    self.logger.bind(tag=TAG).info(f"Restoring existing session: {session_id}")
                    is_session_restore = True
            else:
                # 生成新的session_id
                session_id = set_unique_id("session_id")
                client_session_dir = os.path.join(client_info_dir, session_id)
                is_session_restore = False
                self.logger.bind(tag=TAG).info(f"创建新会话: {session_id}")
        except Exception as e:
            self.logger.bind(tag=TAG).error(f"设置session_id时出错: {e}")
            raise
        return session_id, client_session_dir, is_session_restore

    def get_or_create_session_id(self, headers: Dict[str, str]) -> str:
        """
        从headers中获取或创建session_id

        职责：只负责session_id的获取或创建，不涉及目录操作

        Args:
            headers: HTTP头部信息

        Returns:
            str: 处理后的session_id
        """
        try:
            client_provided_session_id = headers.get(HttpHeaders.X_SESSION_ID)

            if client_provided_session_id:
                # 客户端提供了session_id，进行安全处理
                session_id = safe_path_component(client_provided_session_id)
                self.logger.bind(tag=TAG).info(f"使用客户端提供的session_id: {session_id}")
            else:
                # 生成新的session_id
                session_id = set_unique_id("session_id")
                self.logger.bind(tag=TAG).info(f"生成新的session_id: {session_id}")
        except Exception as e:
            self.logger.bind(tag=TAG).error(f"设置session_id时出错: {e}")
            raise
        return session_id

    def create_session_directory_and_check_restore(
        self, session_id: str, client_info_dir: str, headers: Dict[str, str]
    ) -> Tuple[str, bool]:
        """
        创建会话目录并检查是否为会话恢复

        职责：根据已确定的session_id创建目录结构，判断是否为恢复场景

        Args:
            session_id: 已确定的session_id
            client_info_dir: 客户端信息目录
            headers: HTTP头部信息

        Returns:
            Tuple[str, bool]: (client_session_dir, is_session_restore)
        """
        client_session_dir = os.path.join(client_info_dir, session_id)

        # 判断是否为会话恢复
        is_session_restore = False
        client_provided_session_id = headers.get(HttpHeaders.X_SESSION_ID)

        if client_provided_session_id and client_provided_session_id == session_id:
            # 检查现有session历史是否存在
            if os.path.exists(client_session_dir):
                self.logger.bind(tag=TAG).info(f"恢复存在会话历史: {session_id}")
                is_session_restore = True
            else:
                is_session_restore = False

        return client_session_dir, is_session_restore

    def _get_config_filename(self, session_id: str) -> str:
        """生成配置文件名"""
        return "private_config"

    async def _create_private_config(
        self,
        device_id: str,
        config: Dict[str, Any],
        client_session_dir: str,
        session_id: str,
    ) -> PrivateConfiger:
        """创建并加载私有配置实例"""
        device_id_safe = safe_path_component(device_id)
        client_config_filename = self._get_config_filename(session_id)

        private_configer = PrivateConfiger(
            device_id_safe,
            config,
            profile_name="session",
            client_session_dir=client_session_dir,
            client_config_filename=client_config_filename,
        )
        await private_configer.load_or_create()
        return private_configer

    async def _load_private_config(
        self,
        headers: Dict[str, str],
        config: Dict[str, Any],
        client_session_dir: str,
        session_id: str,
    ) -> Tuple[Optional[PrivateConfiger], bool]:
        """加载或创建设备的私有配置"""
        device_id = headers.get("device-id")

        if not device_id:
            self.logger.bind(tag=TAG).debug("请求头中未提供 device-id，无法加载私有配置")
            return None, False

        try:
            device_id_safe = safe_path_component(device_id)
            config_filename = self._get_config_filename(session_id)
            self.logger.bind(tag=TAG).info(
                f"尝试为设备加载基于会话的私有配置: {device_id_safe}/{config_filename} 在目录: {client_session_dir}"
            )
            private_config = await self._create_private_config(device_id, config, client_session_dir, session_id)

            # 简化验证逻辑：如果私有配置存在且加载成功，就认为设备已验证
            is_device_verified = private_config.private_config is not None and len(private_config.private_config) > 0
            self.logger.bind(tag=TAG).info(
                f"设备 {device_id_safe} 基于会话的私有配置加载完成。配置文件: {config_filename}.yaml，验证状态: {is_device_verified}"
            )

            return private_config, is_device_verified

        except Exception as e:
            device_id_safe = safe_path_component(device_id)
            self.logger.bind(tag=TAG).error(f"设备 {device_id_safe} 基于会话的私有配置初始化失败: {e}", exc_info=True)
            return None, False

    async def update_device_config(
        self,
        device_id: str,
        selected_modules: Dict[str, str],
        prompt: str,
        config: Dict[str, Any],
        client_session_dir: str,
        session_id: str,
    ) -> bool:
        """
        更新设备配置 - 提供给API使用

        Args:
            device_id: 设备ID
            selected_modules: 选择的模块配置
            prompt: 提示词
            config: 全局配置
            client_session_dir: 用户会话目录路径
            session_id: 会话ID

        Returns:
            bool: 更新是否成功
        """
        try:
            private_config = await self._create_private_config(device_id, config, client_session_dir, session_id)
            success = await private_config.update_config(selected_modules, prompt)
            config_filename = self._get_config_filename(session_id)
            if success:
                self.logger.bind(tag=TAG).info(f"设备 {device_id} 会话配置更新成功: {config_filename}.yaml")
            else:
                self.logger.bind(tag=TAG).error(f"设备 {device_id} 会话配置更新失败: {config_filename}.yaml")

            return success

        except Exception as e:
            self.logger.bind(tag=TAG).error(f"更新设备 {device_id} 会话配置时出错: {e}")
            return False

    async def get_device_config(
        self,
        device_id: str,
        config: Dict[str, Any],
        client_session_dir: str,
        session_id: str,
    ) -> Optional[Dict[str, Any]]:
        """
        获取设备配置 - 提供给API使用

        Args:
            device_id: 设备ID
            config: 全局配置
            client_session_dir: 用户会话目录路径
            session_id: 会话ID

        Returns:
            设备的私有配置或None
        """
        try:
            private_config = await self._create_private_config(device_id, config, client_session_dir, session_id)
            return private_config.private_config if private_config.private_config else None

        except Exception as e:
            self.logger.bind(tag=TAG).error(f"获取设备 {device_id} 会话配置时出错: {e}")
            return None
