"""
Qwen VLM Provider - 基于通义千问多模态模型的视觉理解实现
支持图像和视频的内容理解与分析
"""

import asyncio
import base64
import os
import traceback
from typing import List, Union

from config.logger import setup_logging
from core.models.vlm_models import VLMResponseInfo
from core.providers.vlm.base import VLMProviderBase
from dashscope import MultiModalConversation

TAG = __name__
logger = setup_logging()


class VLMProvider(VLMProviderBase):
    """
    Qwen VLM服务提供商，基于通义千问多模态模型实现视觉理解功能
    设计模式：
        - 适配器模式：将dashscope API适配到项目的VLM基类接口
        - 单例模式：每个会话共享同一个provider实例
    主要功能：
        - 图像内容理解：支持单张或多张图像的内容分析
        - 视频内容理解：支持视频文件的场景理解
        - 多模态对话：结合文本和视觉信息进行理解
        - 思考模式：支持深度分析的思考模式
    注意事项：
        - 不开启流式模式，因为图像理解后会总结输出，不影响响应形式
        - 图像和视频输入支持文件路径或base64编码
        - API调用为同步操作，使用asyncio.to_thread异步包装
    """

    def __init__(self, config: dict):
        """
        初始化Qwen VLM Provider
        :param config: 配置字典。
        """
        super().__init__(config)
        self.logger = setup_logging()

        # 从配置中获取参数
        self.api_key = config.get("api_key", "")
        self.model_name = config.get("model_name", "qwen2.5-vl-7b-instruct")
        self.thinking_mode = config.get("thinking_mode", "disabled")

    def _encode_media_to_base64(self, media_path: str) -> str:
        """
        将本地媒体文件（图片或视频）编码为Base64字符串
        :param media_path: 媒体文件的本地路径
        :return: Base64编码的字符串
        :raises: FileNotFoundError 文件不存在时抛出
        :raises: IOError 文件读取失败时抛出
        """
        try:
            with open(media_path, "rb") as media_file:
                encoded_data = base64.b64encode(media_file.read()).decode("utf-8")
            self.logger.bind(tag=TAG).debug(f"[QwenVLM] 文件编码成功: {media_path}")
            return encoded_data
        except FileNotFoundError:
            self.logger.bind(tag=TAG).error(f"[QwenVLM] 文件不存在: {media_path}")
            raise
        except IOError as e:
            self.logger.bind(tag=TAG).error(f"[QwenVLM] 文件读取失败: {media_path}, 错误: {str(e)}")
            raise

    def _build_message_content(self, video_data: Union[str, List[str]], client_prompt: str) -> List[dict]:
        """
        构建MultiModalConversation的消息内容
        :param video_data: 图像/视频数据，支持单个路径或路径列表
        :param prompt: 用户提示文本
        :return: 消息内容列表
        """
        content = []

        # 标准化输入为列表格式
        media_list = [video_data] if isinstance(video_data, str) else video_data

        # 添加媒体内容
        for media_path in media_list:
            if not os.path.exists(media_path):
                self.logger.bind(tag=TAG).warning(f"[QwenVLM] 媒体文件不存在，将跳过: {media_path}")
                continue

            # 判断文件类型
            file_ext = os.path.splitext(media_path)[1].lower()

            # 支持的图片格式
            image_extensions = {".jpg", ".jpeg", ".png", ".gif", ".bmp", ".webp"}
            # 支持的视频格式
            video_extensions = {".mp4", ".avi", ".mov", ".mkv", ".flv"}

            try:
                if file_ext in image_extensions:
                    # 图片文件：直接使用路径
                    content.append({"image": media_path})
                    self.logger.bind(tag=TAG).debug(f"[QwenVLM] 添加图片: {media_path}")
                elif file_ext in video_extensions:
                    # 视频文件：编码为base64
                    base64_video = self._encode_media_to_base64(media_path)
                    content.append(
                        {
                            "video": f"data:video/mp4;base64,{base64_video}",
                            "fps": 2,  # 控制视频抽帧数量，表示每隔1/fps 秒抽取一帧
                        }
                    )
                    self.logger.bind(tag=TAG).debug(f"[QwenVLM] 添加视频: {media_path}")
                else:
                    self.logger.bind(tag=TAG).warning(f"[QwenVLM] 不支持的文件格式: {media_path}")
            except Exception as e:
                self.logger.bind(tag=TAG).error(f"[QwenVLM] 处理媒体文件失败: {media_path}, 错误: {str(e)}")

        # 添加文本提示
        prompt = self.system_prompt + "用户的问题是:" + client_prompt
        content.append({"text": prompt})

        return content

    def _process_video_to_text(self, messages: List[dict]) -> VLMResponseInfo:
        """
        同步调用VLM API进行图像/视频理解
        :param messages: 消息列表
        :return: VLM响应信息
        """
        try:
            # 调用通义千问多模态API
            response = MultiModalConversation.call(
                api_key=self.api_key,
                model=self.model_name,
                messages=messages,
                stream=False,
                enable_thinking=(self.thinking_mode == "enabled"),
            )

            # 检查响应状态
            if response.status_code != 200:
                error_msg = f"API调用失败，状态码: {response.status_code}"
                if hasattr(response, "message"):
                    error_msg += f", 错误信息: {response.message}"
                self.logger.bind(tag=TAG).error(f"[QwenVLM] {error_msg}")
                return VLMResponseInfo(text="理解失败，请稍后重试", is_final=True, model_name=self.model_name)

            # 提取响应文本
            if (
                response.output
                and response.output.choices
                and len(response.output.choices) > 0
                and response.output.choices[0].message
                and response.output.choices[0].message.content
                and len(response.output.choices[0].message.content) > 0
            ):
                text = response.output.choices[0].message.content[0].get("text", "")
                self.logger.bind(tag=TAG).info(f"[QwenVLM] 理解成功，结果长度: {len(text)}")
                return VLMResponseInfo(text=text, is_final=True, model_name=self.model_name)
            else:
                self.logger.bind(tag=TAG).warning("[QwenVLM] API响应为空")
                return VLMResponseInfo(text="未能获取到理解结果", is_final=True, model_name=self.model_name)

        except Exception as e:
            error_msg = f"VLM处理异常: {type(e).__name__}: {str(e)}"
            self.logger.bind(tag=TAG).error(f"[QwenVLM] {error_msg}\n{traceback.format_exc()}")
            return VLMResponseInfo(text="理解过程出现错误", is_final=True, model_name=self.model_name)

    async def video_to_text(
        self, video_data: Union[str, List[str]], client_prompt: str = "请描述这张图片的内容"
    ) -> VLMResponseInfo:
        """
        异步处理图像/视频内容理解
        设计模式：
            - 异步包装模式：将同步API调用包装为异步方法
        业务处理逻辑：
            1. 输入验证：检查输入数据的有效性
            2. 消息构建：根据输入类型构建API消息格式
            3. API调用：调用通义千问多模态API进行理解
            4. 结果解析：提取并返回理解结果
        :param video_data: 图像/视频数据，支持：
            - str: 单个文件路径
            - List[str]: 多个文件路径列表
        :param prompt: 用户提示文本，用于引导理解方向
        :return: VLMResponseInfo 包含理解结果和状态信息
        """
        try:
            # 输入验证
            if not video_data:
                self.logger.bind(tag=TAG).warning("[QwenVLM] 输入数据为空")
                return VLMResponseInfo(text="请提供有效的图像或视频", is_final=True, model_name=self.model_name)

            # 构建消息内容
            messages = [{"role": "user", "content": self._build_message_content(video_data, client_prompt)}]

            self.logger.bind(tag=TAG).debug(f"[QwenVLM] 开始处理，输入数量: {len(messages[0]['content']) - 1}")

            # 使用asyncio.to_thread将同步调用转为异步
            loop = asyncio.get_event_loop()
            result = await loop.run_in_executor(None, self._process_video_to_text, messages)

            return result

        except Exception as e:
            error_msg = f"video_to_text处理失败: {type(e).__name__}: {str(e)}"
            self.logger.bind(tag=TAG).error(f"[QwenVLM] {error_msg}\n{traceback.format_exc()}")
            return VLMResponseInfo(text="理解过程出现异常", is_final=True, model_name=self.model_name)

    def close(self):
        """
        关闭资源，清理连接
        注意事项：
            - Qwen VLM使用无状态API调用，无需清理连接
            - 此方法为接口兼容性保留
        """
        try:
            # Qwen VLM API是无状态的，无需清理连接
            # self.logger.bind(tag=TAG).debug("[QwenVLM] 资源清理完成")
            return
        except Exception as e:
            self.logger.bind(tag=TAG).error(f"[QwenVLM] 关闭资源时发生异常: {str(e)}", exc_info=True)
