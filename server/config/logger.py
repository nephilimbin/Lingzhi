from datetime import datetime
import os
import sys

from config.server_config import ServerConfiger
from loguru import logger


def get_module_abbreviation(module_name, module_dict):
    """获取模块名称的缩写，如果为空则返回00"""
    return module_dict.get(module_name, "")[:2] if module_dict.get(module_name) else "00"


def build_module_string(selected_module):
    """构建模块字符串"""
    return (
        get_module_abbreviation("VAD", selected_module)
        + get_module_abbreviation("ASR", selected_module)
        + get_module_abbreviation("LLM", selected_module)
        + get_module_abbreviation("TTS", selected_module)
        + get_module_abbreviation("Memory", selected_module)
        + get_module_abbreviation("Intent", selected_module)
    )


def formatter(record):
    """为没有 tag 的日志添加默认值"""
    record["extra"].setdefault("tag", record["name"])
    return record["message"]


# 全局变量用于存储已生成的日志文件名
_cached_log_filename = None


def generate_timestamped_filename():
    """生成带时间戳的日志文件名（只生成一次）"""
    global _cached_log_filename
    if _cached_log_filename is None:
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        _cached_log_filename = f"server_{timestamp}.log"
    return _cached_log_filename


def setup_logging():
    """从配置文件中读取日志配置，并设置日志输出格式和级别"""
    global _cached_log_filename

    # 如果logger已经配置过，直接返回
    if _cached_log_filename is not None:
        return logger

    config = ServerConfiger.load_config()
    log_config = config["log"]
    log_format = log_config.get(
        "log_format",
        "<green>{time:YYMMDD HH:mm:ss}</green>[{version}_{selected_module}][<light-blue>{extra[tag]}</light-blue>]-<level>{level}</level>-<light-green>{message}</light-green>",
    )
    log_format_file = log_config.get(
        "log_format_file",
        "{time:YYMMDD HH:mm:ss.SSS}[{version}_{selected_module}][{extra[tag]}]-{level}-{message}",
    )
    selected_module_str = build_module_string(config.get("selected_module", {}))

    # 从配置文件中读取版本信息
    server_version = config.get("server", {}).get("app", {}).get("version", "1.0.0")

    log_format = log_format.replace("{version}", server_version)
    log_format = log_format.replace("{selected_module}", selected_module_str)
    log_format_file = log_format_file.replace("{version}", server_version)
    log_format_file = log_format_file.replace("{selected_module}", selected_module_str)

    log_level = log_config.get("log_level", "INFO")
    log_dir = log_config.get("log_dir", "log")

    # 生成带时间戳的日志文件名（只生成一次）
    log_file = generate_timestamped_filename()

    data_dir = log_config.get("data_dir", "data")

    os.makedirs(log_dir, exist_ok=True)
    if not os.path.exists(log_file):
        os.makedirs(log_dir, exist_ok=True)
    os.makedirs(data_dir, exist_ok=True)

    # 配置日志输出
    logger.remove()

    # 输出到控制台
    logger.add(sys.stdout, format=log_format, level=log_level, filter=formatter)

    # 输出到文件
    log_file_path = os.path.join(log_dir, log_file)
    logger.add(
        log_file_path,
        format=log_format_file,
        level=log_level,
        filter=formatter,
    )

    # 在控制台输出日志文件路径信息（只输出一次）
    print(f"📝 日志文件: {log_file_path}")

    return logger
