import re
from typing import Dict

from api.headers import HttpHeaders
from config.logger import setup_logging

TAG = __name__
logger = setup_logging()


class AuthenticationException(Exception):
    """认证异常"""

    pass


class AuthMiddleware:
    """认证中间件
    1. 验证连接请求
    2. 验证token与MAC地址的绑定关系
    3. 验证设备白名单
    4. 验证设备绑定状态
    5. 验证MAC地址格式
    """

    # MAC地址格式正则表达式（支持 XX:XX:XX:XX:XX:XX 和 XX-XX-XX-XX-XX-XX）
    MAC_ADDRESS_PATTERN = re.compile(r"^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$")

    @staticmethod
    def is_valid_mac_address(device_id: str) -> bool:
        """验证是否为有效的MAC地址格式

        Args:
            device_id: 待验证的设备ID

        Returns:
            格式正确返回True，否则返回False
        """
        if not device_id:
            return False
        return AuthMiddleware.MAC_ADDRESS_PATTERN.match(device_id) is not None

    def __init__(self, config):
        self.config = config
        self.auth_config = config["server"].get("auth", {})
        # 构建token查找表: token -> MAC地址列表
        # ⚠️ name字段现在必须存储设备的MAC地址
        # ✅ 允许多个设备使用相同的token
        token_map = {}
        for item in self.auth_config.get("tokens", []):
            token = item["token"]
            mac_address = item["name"]
            if token not in token_map:
                token_map[token] = []
            token_map[token].append(mac_address)
        self.tokens = token_map
        # 设备白名单
        self.allowed_devices = set(self.auth_config.get("allowed_devices", []))

    async def start_authenticate(self, headers: Dict[str, str]) -> bool:
        """验证连接请求

        Args:
            headers: WebSocket连接的HTTP头部

        Returns:
            认证成功返回True，失败抛出AuthenticationException

        Raises:
            AuthenticationException: 认证失败时抛出
        """
        # 检查是否启用认证
        if not self.auth_config.get("enabled", False):
            return True

        # 获取认证信息
        device_id = headers.get(HttpHeaders.DEVICE_ID, "")
        auth_header = headers.get(HttpHeaders.AUTHORIZATION, "")

        # 白名单检查（可选，优先级高于token验证）
        if self.allowed_devices and device_id in self.allowed_devices:
            logger.bind(tag=TAG).info(f"Device in whitelist: {device_id}")
            return True

        # 验证device-id是否存在
        if not device_id:
            logger.bind(tag=TAG).error(f"Missing {HttpHeaders.DEVICE_ID} header")
            raise AuthenticationException(f"Missing {HttpHeaders.DEVICE_ID} header")

        # 验证device-id格式（必须是有效的MAC地址）
        if not self.is_valid_mac_address(device_id):
            logger.bind(tag=TAG).error(
                f"Invalid device-id format: {device_id}. Expected MAC address format (XX:XX:XX:XX:XX:XX)"
            )
            raise AuthenticationException(
                f"Invalid device-id format. Expected MAC address format (XX:XX:XX:XX:XX:XX), got: {device_id}"
            )

        # 验证Authorization header格式
        if not auth_header or not auth_header.startswith(HttpHeaders.AUTHORIZATION_BEARER_PREFIX):
            logger.bind(tag=TAG).error("Missing or invalid Authorization header")
            raise AuthenticationException("Missing or invalid Authorization header. Expected format: 'Bearer <token>'")

        # 提取token
        token = auth_header.split(" ")[1]

        # 验证token是否存在
        if token not in self.tokens:
            logger.bind(tag=TAG).warning(f"Authentication failed - Invalid token. Device: {device_id}")
            raise AuthenticationException("Invalid token")

        # ✅ 验证device-id是否在token允许的MAC地址列表中
        allowed_mac_addresses = self.tokens[token]
        if device_id not in allowed_mac_addresses:
            logger.bind(tag=TAG).warning(
                f"Authentication failed - Device ID not in allowed list. "
                f"Token: {token}, Allowed MACs: {allowed_mac_addresses}, Got MAC: {device_id}"
            )
            raise AuthenticationException(f"Device ID not authorized for this token. Device: {device_id}")

        # 认证成功
        logger.bind(tag=TAG).info(
            f"Authentication successful - Device: {device_id}, Token: {token}"
        )

        return True

    def get_token_mac_address(self, token: str) -> list:
        """获取token允许的MAC地址列表

        Args:
            token: 认证令牌

        Returns:
            该token允许的MAC地址列表
        """
        return self.tokens.get(token, [])

    def get_token_name(self, token: str) -> list:
        """获取token允许的MAC地址列表（向后兼容方法）

        Args:
            token: 认证令牌

        Returns:
            该token允许的MAC地址列表
        """
        return self.get_token_mac_address(token)

    @staticmethod
    async def authenticate_websocket(headers: Dict[str, str], logger_instance=None, tag: str = None) -> bool:
        """WebSocket连接认证的静态工具方法

        封装完整的认证流程，包括：
        - 获取全局配置
        - 检查认证是否启用
        - 执行认证验证
        - 记录日志

        Args:
            headers: WebSocket连接的HTTP头部
            logger_instance: 可选的logger实例（用于日志记录）
            tag: 可选的日志标签

        Returns:
            认证成功返回True

        Raises:
            AuthenticationException: 认证失败时抛出
        """
        from core.global_services import GlobalServices

        # 获取配置
        config = GlobalServices.get_config()
        auth_enabled = config["server"].get("auth", {}).get("enabled", False)

        # 认证未启用，直接返回成功
        if not auth_enabled:
            if logger_instance:
                logger_instance.bind(tag=tag or TAG).info("⚠️ 认证未启用，跳过认证检查")
            return True

        # 创建认证中间件并执行认证
        auth_middleware = AuthMiddleware(config)

        # 提取device_id用于日志
        device_id = headers.get(HttpHeaders.DEVICE_ID, "")

        try:
            await auth_middleware.start_authenticate(headers)
            if logger_instance:
                logger_instance.bind(tag=tag or TAG).info(f"✅ 认证成功，准备建立连接: {device_id}")
            return True
        except AuthenticationException as e:
            if logger_instance:
                logger_instance.bind(tag=tag or TAG).error(f"❌ 认证失败: {str(e)}")
            raise
