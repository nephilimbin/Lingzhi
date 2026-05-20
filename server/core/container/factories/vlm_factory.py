import importlib
import os
import sys

from config.logger import setup_logging
from core.providers.vlm.base import VLMProviderBase

# 添加项目根目录到Python路径
current_dir = os.path.dirname(os.path.abspath(__file__))
project_root = os.path.abspath(os.path.join(current_dir, "..", ".."))
sys.path.insert(0, project_root)

TAG = __name__
logger = setup_logging()


def create_instance(class_name: str, *args, **kwargs) -> VLMProviderBase:
    """
    工厂方法创建VLM实例
    设计模式：
        - 工厂模式：根据配置的type动态创建对应的VLM Provider实例
        - 延迟加载：只在需要时才导入具体的provider模块
    主要功能：
        - 动态导入core.providers.vlm.{class_name}模块
        - 创建并返回VLMProvider实例
        - 支持多种VLM提供商（qwen、gemini等）
    :param class_name: VLM类型名称（如qwen、gemini等）
    :param args: 位置参数，传递给VLMProvider构造函数
    :param kwargs: 关键字参数，传递给VLMProvider构造函数
    :return: VLMProviderBase实例
    :raises ValueError: 当指定的VLM类型不存在时抛出异常
    """
    try:
        # 检查对应的VLM provider文件是否存在
        if os.path.exists(os.path.join("core", "providers", "vlm", f"{class_name}.py")):
            # 构建模块路径
            lib_name = f"core.providers.vlm.{class_name}"

            # 延迟导入：如果模块尚未加载，则导入它
            if lib_name not in sys.modules:
                sys.modules[lib_name] = importlib.import_module(f"{lib_name}")

            # 创建并返回VLM Provider实例
            provider_instance = sys.modules[lib_name].VLMProvider(*args, **kwargs)
            return provider_instance

        # 如果文件不存在，抛出异常
        raise ValueError(f"不支持的VLM类型: {class_name}，请检查该配置的type是否设置正确")

    except ValueError:
        # 重新抛出值错误（类型不支持）
        raise
    except Exception as e:
        # 捕获并记录其他异常
        error_msg = f"创建VLM实例失败: {type(e).__name__}: {str(e)}"
        logger.bind(tag=TAG).error(f"[VLMFactory] {error_msg}")
        raise ValueError(f"{error_msg}")
