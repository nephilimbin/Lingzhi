import importlib
import os
import sys

from config.logger import setup_logging

# 添加项目根目录到Python路径
current_dir = os.path.dirname(os.path.abspath(__file__))
project_root = os.path.abspath(os.path.join(current_dir, "..", ".."))
sys.path.insert(0, project_root)

logger = setup_logging()


def create_instance(class_name, *args, **kwargs):
    # 创建Memory实例
    if os.path.exists(os.path.join("core", "providers", "memory", f"{class_name}.py")):
        lib_name = f"core.providers.memory.{class_name}"
        if lib_name not in sys.modules:
            sys.modules[lib_name] = importlib.import_module(f"{lib_name}")
        return sys.modules[lib_name].MemoryProvider(*args, **kwargs)

    raise ValueError(f"不支持的Memory类型: {class_name}，请检查该配置的type是否设置正确")
