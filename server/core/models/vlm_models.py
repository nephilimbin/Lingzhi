"""
VLM（视觉语言模型）数据模型

统一管理视觉语言模型的返回结果类型。
"""

from dataclasses import dataclass
from typing import Optional


@dataclass
class VLMResponseInfo:
    """VLM响应统一数据模型"""

    text: str
    is_final: bool = False
    sentence_id: Optional[int] = None
    model_name: Optional[str] = None
