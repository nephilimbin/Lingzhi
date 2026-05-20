import asyncio
from dataclasses import dataclass
import inspect
from typing import Any, Callable, Dict, List

from config.logger import setup_logging

TAG = __name__


@dataclass
class Event:
    """基础事件类"""

    event_type: str
    session_id: str
    data: Any


class EventBus:
    """异步事件总线 - 与现有系统并行运行"""

    def __init__(self):
        self.logger = setup_logging()
        self._handlers: Dict[str, List[Callable]] = {}
        self._event_history: List[Event] = []
        self._max_history = 1000  # 限制历史记录数量
        self._is_enabled = True  # 事件总线开关

    def get_caller_info(self, depth=1):
        """获取指定深度的调用者信息"""
        # 如果深度小于1，返回空字符串
        if depth < 1:
            return ""
        #  获取调用栈信息
        frame = inspect.currentframe()
        for _ in range(depth + 1):  # +1 to account for the current frame
            if frame and frame.f_back:
                frame = frame.f_back
            else:
                return ""  # 调用栈深度不够

        caller_function = frame.f_code.co_name
        caller_class = frame.f_locals.get("self", None)
        if caller_class:
            caller_class_name = caller_class.__class__.__name__ + "."
        else:
            caller_class_name = ""

        return f" (调用者: {caller_class_name}{caller_function})"

    def subscribe(self, event_type: str, handler: Callable):
        """订阅事件"""
        if event_type not in self._handlers:
            self._handlers[event_type] = []
        self._handlers[event_type].append(handler)

        handler_name = handler.__name__ if hasattr(handler, "__name__") else str(handler)
        class_name = ""

        # 检查是否是绑定方法
        if hasattr(handler, "__self__") and hasattr(handler.__self__, "__class__"):
            class_name = handler.__self__.__class__.__name__ + "."

        # 获取调用者信息
        caller_info = self.get_caller_info(depth=0)

        self.logger.bind(tag=TAG).debug(f"订阅事件: {class_name}{handler_name}{caller_info}")

    def unsubscribe(self, event_type: str, handler: Callable):
        """取消订阅"""
        if event_type in self._handlers and handler in self._handlers[event_type]:
            self._handlers[event_type].remove(handler)
            self.logger.bind(tag=TAG).debug(f"取消订阅事件: {event_type}")

    async def publish(self, event: Event):
        """发布事件 - 异步非阻塞"""
        if not self._is_enabled:
            return

        try:
            # 记录事件历史
            self._event_history.append(event)
            if len(self._event_history) > self._max_history:
                self._event_history.pop(0)

            # 异步分发事件
            if event.event_type in self._handlers:
                tasks = []
                for handler in self._handlers[event.event_type]:
                    task = asyncio.create_task(self._safe_call_handler(handler, event))
                    tasks.append(task)

                # 不等待完成，让事件处理并行进行
                if tasks:
                    # 使用gather但不等待，让事件处理在后台进行
                    asyncio.gather(*tasks, return_exceptions=True)

        except Exception as e:
            self.logger.bind(tag=TAG).error(f"发布事件时出错: {e}", exc_info=True)

    async def _safe_call_handler(self, handler: Callable, event: Event):
        """安全调用事件处理器"""
        try:
            if asyncio.iscoroutinefunction(handler):
                await handler(event)
            else:
                handler(event)
        except Exception as e:
            # 记录错误但不影响其他处理器
            self.logger.bind(tag=TAG).error(
                f"事件处理器错误 [{handler.__name__ if hasattr(handler, '__name__') else str(handler)}]: {e}",
                exc_info=True,
            )

    def enable(self):
        """启用事件总线"""
        self._is_enabled = True
        self.logger.bind(tag=TAG).info("事件总线已启用")

    def disable(self):
        """禁用事件总线（用于回滚）"""
        self._is_enabled = False
        self.logger.bind(tag=TAG).info("事件总线已禁用")

    def get_event_history(self, session_id: str = None, event_type: str = None, limit: int = 100) -> List[Event]:
        """获取事件历史（用于调试）"""
        events = self._event_history

        if session_id:
            events = [e for e in events if e.session_id == session_id]
        if event_type:
            events = [e for e in events if e.event_type == event_type]

        return events[-limit:] if limit else events

    def get_subscribers_count(self, event_type: str = None) -> int:
        """获取订阅者数量（用于监控）"""
        if event_type:
            return len(self._handlers.get(event_type, []))
        else:
            return sum(len(handlers) for handlers in self._handlers.values())
