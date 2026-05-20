import asyncio

from config.logger import setup_logging
from core.context.event_bus import Event
from core.context.event_types import EventTypes
from core.models import Action, ActionResponse, ToolType
from core.models.message_models import MessageInfo, SessionInfo
from core.registries import register_function

TAG = __name__
logger = setup_logging()

handle_exit_intent_function_desc = {
    "type": "function",
    "function": {
        "name": "handle_exit_intent",
        "description": "当用户想结束对话或需要退出系统时调用",
        "parameters": {
            "type": "object",
            "properties": {"say_goodbye": {"type": "string", "description": "和用户友好结束对话的告别语"}},
            "required": ["say_goodbye"],
        },
    },
}


@register_function("handle_exit_intent", handle_exit_intent_function_desc, ToolType.SYSTEM_CTL)
def handle_exit_intent(conn, say_goodbye: str):
    # 处理退出意图
    try:
        conn.close_after_chat = True
        logger.bind(tag=TAG).info(f"退出意图已处理:{say_goodbye}")

        # 发布客户端中断请求事件，通知前端停止等待气泡
        request_message_info = MessageInfo(
            type="request.abort",
            session=SessionInfo(session_id=conn.session_id, session_request_id=""),
        )
        asyncio.create_task(
            conn.event_bus.publish(
                Event(
                    event_type=EventTypes.CLIENT_ABORT_REQUESTED,
                    session_id=conn.session_id,
                    data=request_message_info,
                )
            )
        )
        logger.bind(tag=TAG).debug("已发布 CLIENT_ABORT_REQUESTED 事件")

        return ActionResponse(action=Action.RESPONSE, result="退出意图已处理", response=say_goodbye)
    except Exception as e:
        logger.bind(tag=TAG).error(f"处理退出意图错误: {e}")
        return ActionResponse(action=Action.NONE, result="退出意图处理失败", response="")
