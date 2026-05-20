"""
版本管理模块

提供服务版本信息和客户端版本兼容性检查功能。
版本配置从 config/version.yaml 读取。
"""

import os
from datetime import datetime
from enum import Enum
from typing import Dict, List, Optional

from config.logger import setup_logging
import yaml

logger = setup_logging()
TAG = __name__


class CompatibilityStatus(Enum):
    """版本兼容性状态"""
    COMPATIBLE = "compatible"                      # 兼容，可以正常使用
    UPDATE_RECOMMENDED = "update_recommended"      # 建议更新，有新版本可用
    UPDATE_REQUIRED = "update_required"            # 需要更新，版本过低
    SERVER_TOO_OLD = "server_too_old"             # 服务器版本过低


class VersionInfo:
    """版本信息类"""

    def __init__(self, major: int, minor: int, patch: int):
        self.major = major
        self.minor = minor
        self.patch = patch

    def __str__(self) -> str:
        return f"{self.major}.{self.minor}.{self.patch}"

    @classmethod
    def from_string(cls, version_str: str) -> "VersionInfo":
        """从字符串创建版本对象

        支持格式：
        - "1.0.0"
        - "1.0.0+2" (Flutter 格式，build number 会被忽略)
        """
        try:
            # 移除可能的 build number (如 "1.0.0+2")
            version_str = version_str.split("+")[0]

            parts = version_str.split(".")
            if len(parts) != 3:
                raise ValueError(f"版本号格式错误，应为 x.y.z 格式")

            return cls(
                major=int(parts[0]),
                minor=int(parts[1]),
                patch=int(parts[2])
            )
        except (ValueError, IndexError) as e:
            raise ValueError(f"无效的版本字符串: {version_str}") from e

    def __eq__(self, other) -> bool:
        if not isinstance(other, VersionInfo):
            return False
        return (self.major, self.minor, self.patch) == (other.major, other.minor, other.patch)

    def __lt__(self, other) -> bool:
        if not isinstance(other, VersionInfo):
            return NotImplemented
        return (self.major, self.minor, self.patch) < (other.major, other.minor, other.patch)

    def __le__(self, other) -> bool:
        return self < other or self == other

    def __gt__(self, other) -> bool:
        if not isinstance(other, VersionInfo):
            return NotImplemented
        return (self.major, self.minor, self.patch) > (other.major, other.minor, other.patch)

    def __ge__(self, other) -> bool:
        return self > other or self == other


class CompatibilityCheckResult:
    """版本兼容性检查结果"""

    def __init__(
        self,
        status: CompatibilityStatus,
        server_version: str,
        client_version: str,
        message: str,
        min_supported_version: Optional[str] = None,
        max_supported_version: Optional[str] = None,
        recommended_version: Optional[str] = None,
        download_url: Optional[str] = None,
    ):
        self.status = status
        self.server_version = server_version
        self.client_version = client_version
        self.message = message
        self.min_supported_version = min_supported_version
        self.max_supported_version = max_supported_version
        self.recommended_version = recommended_version
        self.download_url = download_url

    def to_dict(self) -> Dict:
        """转换为字典"""
        return {
            "status": self.status.value,
            "server_version": self.server_version,
            "client_version": self.client_version,
            "message": self.message,
            "min_supported_version": self.min_supported_version,
            "max_supported_version": self.max_supported_version,
            "recommended_version": self.recommended_version,
            "download_url": self.download_url,
        }


class VersionManager:
    """版本管理器"""

    _version_config: Optional[Dict] = None
    _config_path: Optional[str] = None

    @classmethod
    def _get_config_path(cls) -> str:
        """获取版本配置文件路径"""
        if cls._config_path is None:
            # 获取当前文件所在目录 (server/core/)
            current_dir = os.path.dirname(os.path.abspath(__file__))
            # 获取 server 目录
            server_dir = os.path.dirname(current_dir)
            # 配置文件路径: server/config/version.yaml
            cls._config_path = os.path.join(server_dir, "config", "version.yaml")
        return cls._config_path

    @classmethod
    def _load_config(cls) -> Dict:
        """加载版本配置"""
        if cls._version_config is not None:
            return cls._version_config

        config_path = cls._get_config_path()

        try:
            with open(config_path, "r", encoding="utf-8") as f:
                cls._version_config = yaml.safe_load(f)
                logger.bind(tag=TAG).info(f"版本配置加载成功: {config_path}")
                return cls._version_config
        except FileNotFoundError:
            logger.bind(tag=TAG).warning(f"版本配置文件不存在: {config_path}，使用默认配置")
            # 返回默认配置
            cls._version_config = {
                "server": {"version": "1.0.0", "release_date": "2025-01-20"},
                "client": {
                    "supported_ranges": [
                        {
                            "server_major": 1,
                            "min_version": "1.0.0",
                            "max_version": "1.0.99",
                            "force_upgrade": False,
                            "recommended_version": "1.0.3"
                        }
                    ],
                    "download_urls": {
                        "ios": "",
                        "android": "",
                    }
                },
                "policy": {
                    "strict_mode": False,
                    "cache_ttl": 3600,
                    "show_update_prompt": True
                }
            }
            return cls._version_config
        except Exception as e:
            logger.bind(tag=TAG).error(f"加载版本配置失败: {e}")
            raise

    @classmethod
    def get_server_version(cls) -> str:
        """获取服务器版本"""
        config = cls._load_config()
        return config["server"]["version"]

    @classmethod
    def get_server_version_info(cls) -> VersionInfo:
        """获取服务器版本对象"""
        version_str = cls.get_server_version()
        return VersionInfo.from_string(version_str)

    @classmethod
    def check_client_compatibility(
        cls,
        client_version_str: str,
        platform: str = "ios"
    ) -> CompatibilityCheckResult:
        """
        检查客户端版本兼容性

        Args:
            client_version_str: 客户端版本字符串
            platform: 客户端平台 (ios/android)

        Returns:
            CompatibilityCheckResult: 兼容性检查结果
        """
        config = cls._load_config()
        server_version_str = config["server"]["version"]
        policy = config.get("policy", {})

        try:
            client_version = VersionInfo.from_string(client_version_str)
            server_version = VersionInfo.from_string(server_version_str)
        except ValueError as e:
            return CompatibilityCheckResult(
                status=CompatibilityStatus.UPDATE_REQUIRED,
                server_version=server_version_str,
                client_version=client_version_str,
                message=f"无效的客户端版本: {e}",
                download_url=cls._get_download_url(platform, config)
            )

        # 获取兼容性配置
        supported_ranges = config.get("client", {}).get("supported_ranges", [])

        # 查找匹配的版本范围
        matched_range = None
        for range_config in supported_ranges:
            if range_config.get("server_major") == server_version.major:
                matched_range = range_config
                break

        if matched_range is None:
            # 没有找到匹配的配置
            return CompatibilityCheckResult(
                status=CompatibilityStatus.SERVER_TOO_OLD,
                server_version=server_version_str,
                client_version=str(client_version),
                message=f"服务器版本 {server_version} 没有配置客户端兼容性规则"
            )

        # 解析版本范围
        min_version = VersionInfo.from_string(matched_range["min_version"])
        max_version = VersionInfo.from_string(matched_range["max_version"])
        recommended_version_str = matched_range.get("recommended_version")
        force_upgrade = matched_range.get("force_upgrade", False)

        # 严格模式检查
        if policy.get("strict_mode", False):
            if client_version > max_version:
                return CompatibilityCheckResult(
                    status=CompatibilityStatus.SERVER_TOO_OLD,
                    server_version=server_version_str,
                    client_version=str(client_version),
                    message=f"客户端版本过高。当前: {client_version}, 服务器支持最高: {max_version}",
                    min_supported_version=str(min_version),
                    max_supported_version=str(max_version),
                )

        # 检查客户端主版本是否过高（跨主版本不兼容）
        if client_version.major > server_version.major:
            return CompatibilityCheckResult(
                status=CompatibilityStatus.SERVER_TOO_OLD,
                server_version=server_version_str,
                client_version=str(client_version),
                message=f"客户端版本过高。当前: {client_version}, 服务器版本: {server_version}",
                min_supported_version=str(min_version),
                max_supported_version=str(max_version),
            )

        # 检查客户端版本是否超过最大支持版本
        if client_version > max_version:
            return CompatibilityCheckResult(
                status=CompatibilityStatus.SERVER_TOO_OLD,
                server_version=server_version_str,
                client_version=str(client_version),
                message=f"客户端版本过高。当前: {client_version}, 服务器支持最高: {max_version}",
                min_supported_version=str(min_version),
                max_supported_version=str(max_version),
            )

        # 检查版本是否过低
        if client_version < min_version:
            return CompatibilityCheckResult(
                status=CompatibilityStatus.UPDATE_REQUIRED,
                server_version=server_version_str,
                client_version=str(client_version),
                message=f"客户端版本过低。当前: {client_version}, 最低要求: {min_version}",
                min_supported_version=str(min_version),
                max_supported_version=str(max_version),
                recommended_version=recommended_version_str,
                download_url=cls._get_download_url(platform, config)
            )

        # 检查强制升级
        if force_upgrade and client_version < VersionInfo.from_string(recommended_version_str or str(max_version)):
            return CompatibilityCheckResult(
                status=CompatibilityStatus.UPDATE_REQUIRED,
                server_version=server_version_str,
                client_version=str(client_version),
                message=f"需要升级到最新版本才能继续使用",
                min_supported_version=str(min_version),
                max_supported_version=str(max_version),
                recommended_version=recommended_version_str,
                download_url=cls._get_download_url(platform, config)
            )

        # 检查是否推荐更新
        if recommended_version_str:
            recommended_version = VersionInfo.from_string(recommended_version_str)
            if client_version < recommended_version:
                return CompatibilityCheckResult(
                    status=CompatibilityStatus.UPDATE_RECOMMENDED,
                    server_version=server_version_str,
                    client_version=str(client_version),
                    message=f"有新版本可用。当前: {client_version}, 最新: {recommended_version}",
                    min_supported_version=str(min_version),
                    max_supported_version=str(max_version),
                    recommended_version=recommended_version_str,
                    download_url=cls._get_download_url(platform, config)
                )

        # 版本完全兼容
        return CompatibilityCheckResult(
            status=CompatibilityStatus.COMPATIBLE,
            server_version=server_version_str,
            client_version=str(client_version),
            message=f"版本兼容。客户端: {client_version}, 服务器: {server_version}",
            min_supported_version=str(min_version),
            max_supported_version=str(max_version)
        )

    @classmethod
    def _get_download_url(cls, platform: str, config: Dict) -> Optional[str]:
        """获取下载链接"""
        download_urls = config.get("client", {}).get("download_urls", {})
        return download_urls.get(platform)

    @classmethod
    def get_supported_versions(cls) -> Dict[str, str]:
        """
        获取支持的版本范围

        Returns:
            Dict: 包含最小和最大支持版本的字典
        """
        config = cls._load_config()
        supported_ranges = config.get("client", {}).get("supported_ranges", [])

        server_version = cls.get_server_version_info()

        for range_config in supported_ranges:
            if range_config.get("server_major") == server_version.major:
                return {
                    "server_version": str(server_version),
                    "min_client_version": range_config["min_version"],
                    "max_client_version": range_config["max_version"],
                    "recommended_client_version": range_config.get("recommended_version", ""),
                }

        return {
            "server_version": str(server_version),
            "min_client_version": "unknown",
            "max_client_version": "unknown",
            "recommended_client_version": "",
        }

    @classmethod
    def reload_config(cls):
        """重新加载配置（用于配置更新后）"""
        cls._version_config = None
        logger.bind(tag=TAG).info("版本配置已重新加载")
