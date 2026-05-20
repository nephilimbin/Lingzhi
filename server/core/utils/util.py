from datetime import datetime
import json
import logging
import os
import re
import socket
import subprocess
import uuid

import yaml


def get_project_dir():
    """获取项目根目录"""
    return os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))) + "/"


def get_local_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        # Connect to Google's DNS servers
        s.connect(("8.8.8.8", 80))
        local_ip = s.getsockname()[0]
        s.close()
        return local_ip
    except Exception:
        return "127.0.0.1"


def get_current_time(format="%Y%m%d%H%M%S"):
    return datetime.now().strftime(format)


def set_unique_id(id_type: str, id_timestamp: str = None, id_random: str = None):
    """
    Generates a unique ID string.

    Args:
        id_type: The type of ID.
        id_timestamp: An optional timestamp string. If None, the current time is used.
        id_random: An optional random string. If None, a UUID4 is generated.

    Returns:
        A unique ID string in the format "id_type_id_timestamp_id_random".
    """
    try:
        if id_timestamp is None:
            id_timestamp = get_current_time()
        if id_random is None:
            id_random = str(uuid.uuid4().hex)
        unique_id = f"{id_type}_{id_timestamp}_{id_random}"
        # 将unique_id转换为适合文件路径的安全格式
        unique_id = safe_path_component(unique_id)
        return unique_id
    except Exception as e:
        logging.error(f"Error generating unique ID: {e}")  # Basic error handling
        return None


def safe_path_component(name: str) -> str:
    """将字符串转换为适合文件路径的安全格式"""
    if name is None:
        return "unknown"
    return re.sub(r'[<>:"/\\|?*@.]', "-", str(name))


def read_config(config_path):
    with open(config_path, "r", encoding="utf-8") as file:
        config = yaml.safe_load(file)
    return config


def write_json_file(file_path, data):
    """将数据写入 JSON 文件"""
    with open(file_path, "w", encoding="utf-8") as file:
        json.dump(data, file, ensure_ascii=False, indent=4)


def is_punctuation_or_emoji(char):
    """检查字符是否为空格、指定标点或表情符号"""
    # 定义需要去除的中英文标点（包括全角/半角）
    punctuation_set = {
        "，",
        ",",  # 中文逗号 + 英文逗号
        "。",
        ".",  # 中文句号 + 英文句号
        "！",
        "!",  # 中文感叹号 + 英文感叹号
        "-",
        "－",  # 英文连字符 + 中文全角横线
        "、",  # 中文顿号
    }
    if char.isspace() or char in punctuation_set:
        return True
    # 检查表情符号（保留原有逻辑）
    code_point = ord(char)
    emoji_ranges = [
        (0x1F600, 0x1F64F),
        (0x1F300, 0x1F5FF),
        (0x1F680, 0x1F6FF),
        (0x1F900, 0x1F9FF),
        (0x1FA70, 0x1FAFF),
        (0x2600, 0x26FF),
        (0x2700, 0x27BF),
    ]
    return any(start <= code_point <= end for start, end in emoji_ranges)


def get_string_no_punctuation_or_emoji(s):
    """去除字符串首尾的空格、标点符号和表情符号，并去除中间所有表情符号"""
    chars = list(s)
    # 处理开头的字符
    start = 0
    while start < len(chars) and is_punctuation_or_emoji(chars[start]):
        start += 1
    # 处理结尾的字符
    end = len(chars) - 1
    while end >= start and is_punctuation_or_emoji(chars[end]):
        end -= 1
    # 只保留首尾处理后的部分
    trimmed = chars[start : end + 1]
    # 去除中间所有 emoji（但保留标点和空格）
    result = [c for c in trimmed if not is_emoji(c)]
    return "".join(result)


def is_emoji(char):
    code_point = ord(char)
    emoji_ranges = [
        (0x1F600, 0x1F64F),
        (0x1F300, 0x1F5FF),
        (0x1F680, 0x1F6FF),
        (0x1F900, 0x1F9FF),
        (0x1FA70, 0x1FAFF),
        (0x2600, 0x26FF),
        (0x2700, 0x27BF),
    ]
    return any(start <= code_point <= end for start, end in emoji_ranges)


def remove_punctuation_and_length(text):
    """去除字符串全角标点符号和半角标点符号"""
    # 处理None或非字符串输入
    if text is None or not isinstance(text, str):
        return 0, ""

    # 全角符号和半角符号的Unicode范围
    full_width_punctuations = "！＂＃＄％＆＇（）＊＋，－。／：；＜＝＞？＠［＼］＾＿｀｛｜｝～"
    half_width_punctuations = r'!"#$%&\'()*+,-./:;<=>?@[\]^_`{|}~'
    space = " "  # 半角空格
    full_width_space = "　"  # 全角空格

    # 去除全角和半角符号以及空格
    result = "".join(
        [
            char
            for char in text
            if char not in full_width_punctuations
            and char not in half_width_punctuations
            and char not in space
            and char not in full_width_space
        ]
    )

    if result == "Yeah":
        return 0, ""
    return len(result), result


def check_model_key(modelType, modelKey):
    if "你" in modelKey:
        logging.error("你还没配置" + modelType + "的密钥，请在配置文件中配置密钥，否则无法正常工作")
        return False
    return True


def check_ffmpeg_installed():
    ffmpeg_installed = False
    try:
        # 执行ffmpeg -version命令，并捕获输出
        result = subprocess.run(
            ["ffmpeg", "-version"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=True,  # 如果返回码非零则抛出异常
        )
        # 检查输出中是否包含版本信息（可选）
        output = result.stdout + result.stderr
        if "ffmpeg version" in output.lower():
            ffmpeg_installed = True
        return False
    except (subprocess.CalledProcessError, FileNotFoundError):
        # 命令执行失败或未找到
        ffmpeg_installed = False
    if not ffmpeg_installed:
        error_msg = "您的电脑还没正确安装ffmpeg\n"
        error_msg += "\n建议您：\n"
        error_msg += "1、按照项目的安装文档，正确进入conda环境\n"
        error_msg += "2、查阅安装文档，如何在conda环境中安装ffmpeg\n"
        raise ValueError(error_msg)


def extract_json_from_string(input_string):
    """提取字符串中的 JSON 部分"""
    pattern = r"(\{.*\})"
    match = re.search(pattern, input_string)
    if match:
        return match.group(1)  # 返回提取的 JSON 字符串
    return None
