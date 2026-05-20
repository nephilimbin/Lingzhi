from abc import ABC, abstractmethod
from copy import deepcopy
from pathlib import Path
import time
from typing import Any, Dict, Optional

from config.logger import setup_logging
from core.utils.lock_manager import FileLockManager
from core.utils.util import safe_path_component
import yaml

TAG = __name__


class BaseConfig(ABC):
    """配置基类，定义通用属性和方法"""

    def __init__(self, device_id: str, default_config: Dict[str, Any]):
        self.device_id = safe_path_component(device_id)
        self.default_config = default_config
        self.logger = setup_logging()
        self.lock_manager = FileLockManager()
        self.config_data = {}

    @abstractmethod
    async def load_or_create(self) -> None:
        """加载或创建配置"""
        pass

    @abstractmethod
    async def save_config(self) -> None:
        """保存配置"""
        pass


class PrivateConfiger(BaseConfig):
    """私有配置管理类，负责设备特定的配置"""

    def __init__(
        self,
        device_id: str,
        default_config: Dict[str, Any],
        profile_name: str = "session",
        client_session_dir: str = None,
        client_config_filename: str = None,
    ):
        super().__init__(device_id, default_config)

        if not client_session_dir or not client_config_filename:
            raise ValueError("client_session_dir 和 client_config_filename 都是必需的参数")

        # 配置文件相关属性
        self.profile_name = self._extract_profile_name(client_config_filename, profile_name)
        self.device_dir = Path(client_session_dir)
        self.config_path = self.device_dir / f"{safe_path_component(client_config_filename)}.yaml"

        # 将config_data重命名为private_config以保持向后兼容
        self.private_config = self.config_data

    def _extract_profile_name(self, client_config_filename: str, profile_name: str) -> str:
        """从配置文件名提取profile名称"""
        if client_config_filename.startswith("config_"):
            return safe_path_component(client_config_filename[7:])
        return safe_path_component(profile_name)

    async def load_or_create(self) -> None:
        """加载或创建设备配置文件"""
        try:
            # 确保设备目录存在
            self.device_dir.mkdir(parents=True, exist_ok=True)

            await self.lock_manager.acquire_lock(str(self.config_path))
            try:
                if self.config_path.exists():
                    await self._load_existing_config()
                else:
                    await self._create_new_config()
            finally:
                self.lock_manager.release_lock(str(self.config_path))

        except Exception as e:
            self.logger.bind(tag=TAG).error(f"Error handling private config: {e}")
            self.private_config = {}

    async def _load_existing_config(self) -> None:
        """加载现有配置"""
        with open(self.config_path, "r", encoding="utf-8") as f:
            self.private_config = yaml.safe_load(f) or {}

    async def _create_new_config(self) -> None:
        """创建新配置"""
        # 处理prompt内容，支持从文件读取
        prompt_content = self._get_prompt_content(self.default_config)

        config = {
            "device_id": self.device_id,
            "profile_name": self.profile_name,
            "selected_module": deepcopy(self.default_config["selected_module"]),
            "prompt": prompt_content,
            "created_time": int(time.time()),
        }

        # 动态获取所有provider配置节
        from core.container.service_container import ServiceContainer

        provider_sections = ServiceContainer.get_all_provider_config_keys()
        for section in provider_sections:
            if section in self.default_config:
                config[section] = deepcopy(self.default_config[section])
        # 保存配置
        self.private_config = config
        await self.save_config()

    async def save_config(self) -> None:
        """保存配置到文件"""
        with open(self.config_path, "w", encoding="utf-8") as f:
            yaml.dump(self.private_config, f, allow_unicode=True, default_flow_style=False)

    def _get_prompt_content(self, config: Dict[str, Any]) -> str:
        """获取prompt内容，支持从文件读取或直接使用配置中的prompt"""
        # 如果配置了system_prompt_template，则从文件读取
        if "system_prompt_template" in config:
            prompt_file_path = config["system_prompt_template"]
            try:
                # 构建完整的文件路径
                project_root = Path(__file__).parent.parent.parent
                full_path = project_root / prompt_file_path

                if full_path.exists():
                    with open(full_path, "r", encoding="utf-8") as f:
                        return f.read().strip()
                else:
                    self.logger.bind(tag=TAG).warning(f"Prompt文件不存在: {full_path}")
                    return "默认系统提示词"
            except Exception as e:
                self.logger.bind(tag=TAG).error(f"读取prompt文件失败: {e}")
                return "默认系统提示词"

        # 如果没有system_prompt_template，使用配置中的prompt
        return config.get("prompt", "默认系统提示词")

    async def update_config(self, selected_modules: Dict[str, str], prompt: str) -> bool:
        """
        更新设备配置

        注意：此方法执行合并更新，保留未指定的现有模块配置

        Args:
            selected_modules: 要更新的模块配置字典
            prompt: 系统提示词

        Returns:
            bool: 更新是否成功
        """
        try:
            self.logger.bind(tag=TAG).info("==========开始更新配置==========")

            await self.lock_manager.acquire_lock(str(self.config_path))
            try:
                # 更新前记录当前配置
                existing_modules = self.private_config.get("selected_module", {})

                # 合并更新：只更新指定的模块，保留其他已存在的模块
                merged_modules = existing_modules.copy()
                merged_modules.update(selected_modules)

                self.private_config.update(
                    {
                        "selected_module": merged_modules,
                        "prompt": prompt,
                        "updated_time": int(time.time()),
                    }
                )

                # 更新后记录配置
                self.logger.bind(tag=TAG).info(f"保存后配置: {self.private_config.get('selected_module', {})}")

                await self.save_config()
                return True
            finally:
                self.lock_manager.release_lock(str(self.config_path))
        except Exception as e:
            self.logger.bind(tag=TAG).error(f"Error updating config: {e}", exc_info=True)
            return False

    async def update_last_chat_time(self, timestamp: Optional[int] = None) -> bool:
        """更新最近聊天时间"""
        if not self.private_config:
            return False

        try:
            await self.lock_manager.acquire_lock(str(self.config_path))
            try:
                if timestamp is None:
                    timestamp = int(time.time())

                self.private_config["last_chat_time"] = timestamp
                await self.save_config()
                return True
            finally:
                self.lock_manager.release_lock(str(self.config_path))
        except Exception as e:
            self.logger.bind(tag=TAG).error(f"Error updating last chat time: {e}")
            return False

    def create_private_service_container(self):
        """为会话创建私有的服务容器"""
        if not self.private_config:
            self.logger.bind(tag=TAG).debug("私有配置不存在，无法创建服务容器")
            return None

        try:
            # 延迟导入避免循环依赖
            from core.container.service_container import ServiceContainer

            # 使用私有配置创建服务容器
            private_container = ServiceContainer(self.private_config)
            private_container.initialize_services()

            return private_container
        except Exception as e:
            self.logger.bind(tag=TAG).error(f"创建私有服务容器失败: {e}", exc_info=True)
            return None
