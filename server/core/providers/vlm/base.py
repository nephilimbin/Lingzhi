from abc import ABC, abstractmethod
import os
from typing import List, Union

from config.logger import setup_logging
from core.models.vlm_models import VLMResponseInfo

TAG = __name__


class VLMProviderBase(ABC):
    """
    视频理解模型基类
    注意点：
    1. 不开启流式模式，因为图像理解后仍会总结输出。不影响响应形式。
    2. 不同模型对输入格式和尺寸可能有不同要求，在实现类中处理。
    3. 输出格式需要统一为VLMResponseInfo
    """

    def __init__(self, config: dict):
        self.logger = setup_logging()
        self.model_name = config.get("model_name")
        self.type = config.get("type")
        self.api_key = config.get("api_key")
        self.model_dir = config.get("model_dir", "")
        self.output_dir = ""
        self.thinking_mode = config.get("thinking_mode", "")
        self.system_prompt = "根据用户问题用简单的话回答，如果没有对应的内容，回复未发现相关图像内容。如果有的，请简要说明图像中的主要元素和场景。不要输出多余的内容。"

    def set_output_directory(self, output_dir):
        """动态设置输出目录"""
        self.output_dir = output_dir
        os.makedirs(output_dir, exist_ok=True)

    @abstractmethod
    async def video_to_text(self, video_data: Union[str, List[str]], client_prompt: str) -> VLMResponseInfo:
        return

    @abstractmethod
    def close(self):
        """
        关闭资源
        """
        return
