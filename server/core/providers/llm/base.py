from abc import ABC, abstractmethod
from dataclasses import dataclass
import traceback
from typing import Any, Generator, List, Optional

from config.logger import setup_logging

TAG = __name__
logger = setup_logging()


@dataclass
class LLMResponseInfo:
    """LLM响应的统一信息类"""

    model_name: Optional[str] = None  # 模型名称
    content: Optional[str] = None  # 文本内容
    total_token_count: Optional[int] = None  # 总token数
    prompt_token_count: Optional[int] = None  # 提示词token数
    candidates_token_count: Optional[int] = None  # 候选词token数
    model_response_duration: Optional[float] = None  # 模型响应时间
    tool_calls: Optional[Any] = None  # 函数调用信息
    error: Optional[str] = None  # 错误信息（如果有）
    is_response_end: Optional[bool] = False  # 流式响应是否结束
    is_stream_mode: Optional[bool] = False  # 是否为流式响应


class LLMProviderBase(ABC):
    def __init__(self, config):
        self.config = config
        self.model_name = self.config.get("model_name", "unknown")
        self.api_key = self.config.get("api_key", "")
        # 通用可选参数
        self.max_output_tokens = config.get("max_output_tokens", 4096)
        self.temperature = config.get("temperature", 0.7)
        self.thinking_mode = config.get("thinking_mode", "")
        self.stream_mode = config.get("stream_mode", False)

    @abstractmethod
    def response(self, dialogues, stream_mode=False, **kwargs) -> Generator[LLMResponseInfo, None, None]:
        """LLM响应生成器，返回统一的LLMResponseInfo对象流"""
        pass

    @abstractmethod
    def is_support_stream_mode(self):
        """是否支持流式输出, 根据模型厂商的规则进行判断"""
        return self.stream_mode

    def validate_dialogue_format(self, dialogues: List) -> List:
        """验证对话格式, 过滤掉每个遍历的字典中role不是system、user、assistant和tool的项"""
        return [dialogue for dialogue in dialogues if dialogue.get("role") in ["system", "user", "assistant", "tool"]]

    def chat_completion(
        self, dialogues: List, stream_mode: bool = False, **kwargs
    ) -> Generator[LLMResponseInfo, None, None]:
        """
        LLM响应函数，统一使用生成器接口

        Args:
            dialogues: 对话历史列表
            stream_mode: 是否流式模式
            **kwargs: 其他参数

        Yields:
            LLMResponseInfo: 响应信息对象
        """
        try:
            dialogues = self.validate_dialogue_format(dialogues)

            # 统一使用 yield 返回响应
            for response in self.response(dialogues, stream_mode=stream_mode, **kwargs):
                yield response

        except Exception as e:
            logger.bind(tag=TAG).error(f"chat_completion 错误: {e}, 追踪: {traceback.format_exc()}")
            # 即使出错也要 yield 一个错误响应
            yield LLMResponseInfo(
                model_name=self.model_name, error=str(e), is_stream_mode=stream_mode, is_response_end=True
            )
