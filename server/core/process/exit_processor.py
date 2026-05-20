from typing import TYPE_CHECKING, Optional

from core.context.event_bus import Event
from core.context.event_types import EventTypes
from core.models import Action, ActionResponse
from core.models.message_models import MessageInfo, SessionInfo
from core.utils.util import remove_punctuation_and_length

if TYPE_CHECKING:
    from core.session.session_context import SessionContext

TAG = __name__


class ExitProcessor:
    """
    退出意图处理器

    职责：
    - 检测和处理用户的退出命令和意图
    - 管理退出流程的触发和状态控制
    - 通过事件系统发布客户端中断请求
    - 协调各个组件的优雅退出过程

    组件关系：
    - 依赖SessionContext获取配置、日志记录器和事件总线
    - 通过EventBus发布退出事件，实现组件间的解耦通信
    - 使用配置系统获取退出命令列表，支持动态配置
    - 与StateManager协作管理会话状态

    设计模式：
    - 策略模式：支持多种退出命令的灵活配置和扩展
    - 观察者模式：通过事件系统通知其他组件退出意图
    - 责任链模式：在处理器链中优先处理退出意图
    """

    def __init__(self, context: "SessionContext"):
        """
        初始化退出处理器

        :param context: 会话上下文，提供配置、日志记录器和事件总线等必要依赖
        """
        self.context = context
        self.logger = context.logger
        self.event_bus = context.event_bus
        self.session_request_id = ""

    async def process_exit_intent(
        self,
        text: str,
    ) -> Optional[ActionResponse]:
        """
        处理用户的退出意图
        :param text: 用户输入的文本内容
        :return: 检测到退出时返回ActionResponse，否则返回None
        """
        if await self.has_direct_exit_intent(text):
            return ActionResponse(action=Action.NONE, result="用户退出", response="")
        else:
            return None

    async def has_direct_exit_intent(self, text: str) -> bool:
        """
        检测用户输入中是否包含明确的退出命令
        :param text: 用户输入的原始文本
        :return: 检测到退出命令返回True，否则返回False
        """
        try:
            # 预处理文本：移除标点符号并标准化格式
            _, processed_text = remove_punctuation_and_length(text)
            processed_text = processed_text.rstrip("。！？")

            # 从配置获取退出命令列表
            cmd_exit = self.context.session_runtime_config.session_exit_config.cmd_exit

            # 创建中断请求消息实例，用于事件传递
            request_message_info = MessageInfo(
                type="request.abort",
                session=SessionInfo(session_id=self.context.session_id, session_request_id=self.session_request_id),
            )

            # 遍历配置的退出命令进行精确匹配
            for cmd in cmd_exit:
                if processed_text == cmd:
                    # 发布客户端中断请求事件
                    self.logger.bind(tag=TAG).info(f"识别到退出命令 '{cmd}'，发布客户端中断请求事件")
                    await self.event_bus.publish(
                        Event(
                            event_type=EventTypes.CLIENT_ABORT_REQUESTED,
                            session_id=self.context.session_id,
                            data=request_message_info,
                        )
                    )
                    return True

            return False

        except Exception as e:
            self.logger.bind(tag=TAG).error(f"检测退出意图时发生错误: {e}")
            return False
