from collections.abc import Mapping
import os
from typing import Any, Dict, List, Optional

from config.manage_api_client import get_agent_models, get_server_config, init_service
import yaml


class ServerConfiger:
    """统一的配置管理器，负责服务器配置的加载、验证和管理"""

    _config_cache: Optional[Dict[str, Any]] = None
    _project_dir: Optional[str] = None

    @classmethod
    def get_project_dir(cls) -> str:
        """获取项目根目录"""
        if cls._project_dir is None:
            cls._project_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) + "/"
        return cls._project_dir

    @classmethod
    def read_config(cls, config_path: str) -> Dict[str, Any]:
        """读取配置文件"""
        try:
            with open(config_path, encoding="utf-8") as file:
                lines = file.readlines()
                file.seek(0)
                return yaml.safe_load("".join(lines)) or {}
        except Exception as e:
            print(f"[ERROR] 加载YAML文件时出错: {e}")
            raise

    @classmethod
    def get_config_file_path(cls) -> str:
        """获取配置文件路径，优先使用私有配置文件（若存在）"""
        project_dir = cls.get_project_dir()

        # 检查服务器配置文件
        server_config_path = "config/.server_config.yaml"
        if os.path.exists(project_dir + server_config_path):
            return server_config_path

        return server_config_path

    @classmethod
    def find_missing_keys(cls, new_config: Dict, old_config: Dict, parent_key: str = "") -> List[str]:
        """递归查找缺失的配置项"""
        missing_keys = []

        if not isinstance(new_config, Mapping):
            return missing_keys

        for key, value in new_config.items():
            full_path = f"{parent_key}.{key}" if parent_key else key

            if key not in old_config:
                missing_keys.append(full_path)
                continue

            if isinstance(value, Mapping):
                sub_missing = cls.find_missing_keys(value, old_config[key], parent_key=full_path)
                missing_keys.extend(sub_missing)

        return missing_keys

    @classmethod
    def validate_config_compatibility(cls) -> None:
        """检查配置文件兼容性"""
        project_dir = cls.get_project_dir()
        old_config_file = project_dir + "config/.server_config.yaml"

        if not os.path.exists(old_config_file):
            return

        old_config = cls.read_config(old_config_file)

        # 如果使用API配置，跳过检查
        if old_config.get("read_config_from_api", False):
            return

        # 检查默认配置文件是否存在
        default_config_file = project_dir + "server_config.yaml"
        if not os.path.exists(default_config_file):
            # 如果默认配置文件不存在，跳过兼容性检查
            return

        new_config = cls.read_config(default_config_file)
        missing_keys = cls.find_missing_keys(new_config, old_config)

        if missing_keys:
            missing_keys_str = "\n".join(f"- {key}" for key in missing_keys)
            error_msg = (
                "您的配置文件太旧了，缺少了：\n"
                f"{missing_keys_str}\n"
                "建议您：\n"
                "1、备份config/.server_config.yaml文件\n"
                "2、将根目录的server_config.yaml文件复制到config下，重命名为.server_config.yaml\n"
                "3、将密钥逐个复制到新的配置文件中\n"
            )
            raise ValueError(error_msg)

    @classmethod
    def get_config_from_api(cls, config: Dict[str, Any]) -> Dict[str, Any]:
        """从管理API获取配置"""
        init_service(config)

        config_data = get_server_config()
        if config_data is None:
            raise Exception("Failed to fetch server config from API")

        config_data["read_config_from_api"] = True
        config_data["manager-api"] = {
            "url": config["manager-api"].get("url", ""),
            "secret": config["manager-api"].get("secret", ""),
        }
        return config_data

    @classmethod
    def ensure_directories(cls, config: Dict[str, Any]) -> None:
        """确保所有配置路径存在"""
        dirs_to_create = set()
        project_dir = cls.get_project_dir()

        # 日志文件目录
        log_dir = config.get("log", {}).get("log_dir", "tmp")
        dirs_to_create.add(os.path.join(project_dir, log_dir))

        # ASR/TTS模块输出目录
        for module in ["ASR", "TTS", "VLM"]:
            for provider in config.get(module, {}).values():
                if isinstance(provider, dict) and provider.get("output_dir"):
                    dirs_to_create.add(provider["output_dir"])

        # 根据selected_module创建模型目录
        selected_modules = config.get("selected_module", {})
        for module_type in ["ASR", "LLM", "TTS", "VLM"]:
            selected_provider = selected_modules.get(module_type)
            if not selected_provider:
                continue

            provider_config = config.get(module_type, {}).get(selected_provider, {})
            output_dir = provider_config.get("output_dir")
            if output_dir:
                full_model_dir = os.path.join(project_dir, output_dir)
                dirs_to_create.add(full_model_dir)

        # 创建目录
        for dir_path in dirs_to_create:
            try:
                os.makedirs(dir_path, exist_ok=True)
            except PermissionError:
                print(f"警告：无法创建目录 {dir_path}，请检查写入权限")

    @classmethod
    def load_config(cls) -> Dict[str, Any]:
        """加载配置文件"""
        if cls._config_cache is not None:
            return cls._config_cache

        import sys

        args = getattr(sys, "argv", None)
        config_path = (
            getattr(args, "config_path", "config/.server_config.yaml") if args else "config/.server_config.yaml"
        )
        try:
            config = cls.read_config(config_path)

            # 处理system_prompt_template，如果存在则读取文件内容作为prompt
            if "system_prompt_template" in config:
                config["prompt"] = cls._load_prompt_from_file(config["system_prompt_template"])

            # 检查配置兼容性
            cls.validate_config_compatibility()

            # 从API获取配置（如果配置了）
            if config.get("manager-api", {}).get("url"):
                config = cls.get_config_from_api(config)

            # 初始化目录
            cls.ensure_directories(config)

            cls._config_cache = config
            return config
        except Exception as e:
            print(f"[ERROR] load_config异常: {e}")
            raise

    @classmethod
    def get_private_config_from_api(
        cls, config: Dict[str, Any], device_id: str, client_id: str
    ) -> Optional[Dict[str, Any]]:
        """从管理API获取私有配置"""
        return get_agent_models(device_id, client_id, config["selected_module"])

    @classmethod
    def _load_prompt_from_file(cls, prompt_file_path: str) -> str:
        """从文件加载prompt内容"""
        try:
            # 构建完整的文件路径
            full_path = os.path.join(cls.get_project_dir(), prompt_file_path)

            if os.path.exists(full_path):
                with open(full_path, "r", encoding="utf-8") as f:
                    return f.read().strip()
            else:
                print(f"[WARNING] Prompt文件不存在: {full_path}")
                return "默认系统提示词"
        except Exception as e:
            print(f"[ERROR] 读取prompt文件失败: {e}")
            return "默认系统提示词"

    @classmethod
    def clear_cache(cls) -> None:
        """清除配置缓存"""
        cls._config_cache = None


# 向后兼容的函数接口已移除，请直接使用 ServerConfiger 类方法
# 例如: ServerConfiger.load_config() 而不是 load_config()
