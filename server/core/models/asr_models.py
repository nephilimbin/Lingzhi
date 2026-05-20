"""
ASR（语音识别）数据模型

统一管理语音识别的返回结果类型。
"""

from dataclasses import dataclass
from typing import Optional


@dataclass
class ASRResponseInfo:
    """ASR响应统一数据模型"""

    text: str
    is_final: bool = False
    begin_time: Optional[float] = None
    end_time: Optional[float] = None
    sentence_id: Optional[int] = None
    provider_name: Optional[str] = None
