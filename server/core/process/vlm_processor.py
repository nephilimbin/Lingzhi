"""
VLM (Vision Language Model) 处理器模块

该模块负责处理视觉语言模型相关的图像识别和分析功能。
主要功能包括：
1. 从 WebRTC 视频队列中获取图像帧
2. 调用 VLM 进行图像识别和分析
3. 构造包含图像信息的提示文本，将视觉上下文合并到用户消息中

工作流程：
图像队列获取 -> VLM识别 -> 构造增强文本 -> 返回处理结果
"""

from typing import TYPE_CHECKING, NamedTuple

from core.models.vlm_models import VLMResponseInfo

if TYPE_CHECKING:
    from core.session.session_context import SessionContext

TAG = __name__


class VLMProcessResult(NamedTuple):
    """VLM 处理结果

    Attributes:
        text: 包含图像信息的提示文本
        vlm_result: VLM 识别结果对象
        has_image: 是否处理了图像
    """

    text: str
    vlm_result: VLMResponseInfo | None
    has_image: bool


class VLMProcessor:
    """VLM 处理器 - 负责图像识别和视觉语言处理

    该处理器专门处理从 WebRTC 视频流中获取的图像帧，
    使用视觉语言模型进行内容识别和分析，并将结果
    整合到对话流程中。

    主要职责：
    1. 从状态管理器的 VLM 视频队列中获取图像帧路径
    2. 调用 VLM 服务进行图像识别和分析
    3. 构造包含图像信息的提示文本，将视觉上下文合并到用户消息中

    组件关系：
    - 依赖 SessionContext 获取 VLM 服务、状态管理器等必要依赖
    - 使用 StateManager 的 webrtc_vlm_video_queue 获取待处理图像
    - 与 IntentProcessor 协作，将视觉信息整合到意图处理流程

    注意事项：
    - VLM 结果不再作为 assistant 消息添加到对话历史
    - 视觉信息通过增强用户消息文本的方式传递给后续 LLM

    设计模式：
    - 单一职责：专注于视觉语言处理
    - 依赖注入：通过 SessionContext 获取依赖服务
    """

    def __init__(self, context: "SessionContext"):
        """
        初始化 VLM 处理器

        :param context: 会话上下文，提供 VLM 服务、状态管理器、对话历史等必要依赖
        """
        self.context = context
        self.logger = context.logger
        self.session_request_id = ""

        self.logger.bind(tag=TAG).info("VLM处理器初始化完成")

    async def process_vlm_images(self, user_text: str) -> VLMProcessResult:
        """
        处理 VLM 图像的主入口方法

        从 VLM 视频队列中获取所有待处理的图像帧，使用 VLM 进行识别，
        将视觉描述作为上下文前缀合并到用户消息文本中返回。
        不会将 VLM 结果作为 assistant 消息添加到对话历史。

        :param user_text: 用户输入的原始文本
        :return: VLMProcessResult，包含处理后的文本、VLM 结果和是否有图像的标志
        """
        try:
            # 从队列中获取所有待处理的图像路径
            image_paths = []
            while not self.context.state_manager.webrtc_vlm_video_queue.empty():
                # 串行处理图片结果（同步队列，不需要 await）
                image_paths.append(self.context.state_manager.webrtc_vlm_video_queue.get())

            # 如果没有图像，直接返回原始文本
            if not image_paths:
                return VLMProcessResult(
                    text=user_text,
                    vlm_result=None,
                    has_image=False,
                )

            # 检查 VLM 服务是否可用
            if not self.context.vlm:
                self.logger.bind(tag=TAG).warning("VLM服务不可用，无法处理图像")
                return VLMProcessResult(
                    text=user_text,
                    vlm_result=None,
                    has_image=False,
                )

            # 调用 VLM 进行图像识别
            self.logger.bind(tag=TAG).info(f"开始处理 {len(image_paths)} 个图像帧")
            vlm_result = await self.context.vlm.video_to_text(video_data=image_paths, client_prompt=user_text)

            # 构造包含视觉上下文的增强文本，将 VLM 描述作为上下文前缀合并到用户消息中
            text = f"（视觉信息：{vlm_result.text}）{user_text}"

            self.logger.bind(tag=TAG).info(f"VLM处理完成，增强文本: {text}")

            return VLMProcessResult(
                text=text,
                vlm_result=vlm_result,
                has_image=True,
            )

        except Exception as e:
            # 异常处理：记录错误但继续处理，不阻塞整个流程
            self.logger.bind(tag=TAG).error(f"VLM图像处理失败: {e}")
            # 出错时返回原始文本，不影响后续流程
            return VLMProcessResult(
                text=user_text,
                vlm_result=None,
                has_image=False,
            )
