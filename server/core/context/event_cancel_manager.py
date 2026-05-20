"""
任务取消管理器 - 统一管理所有可取消的任务，实现事件驱动的即时中断
"""

import asyncio
from dataclasses import dataclass, field
from typing import TYPE_CHECKING, Dict, Optional, Set
from venv import logger

from config.logger import setup_logging
from core.context.event_bus import Event
from core.context.event_types import EventTypes

if TYPE_CHECKING:
    from core.session.session_context import SessionContext

# logger = setup_logging()
TAG = __name__


class CancellableTaskType:
    """任务类型"""

    AUDIO_ASR_REGISTER_TASK = "audio_ars_register_task"
    AUDIO_ASR_MONITOR_TASK = "audio_asr_monitor_task"
    AUDIO_ASR_PROCESS_TASK = "audio_asr_process_task"
    TEXT_READ_TASK = "text_read_task"
    TEXT_PROCESS_TASK = "text_process_task"
    AUDIO_TTS_PROCESS_TASK = "audio_tts_process_task"
    AUDIO_TTS_OUTPUT_TASK = "audio_tts_output_task"


@dataclass(frozen=True, unsafe_hash=True)
class CancellableTask:
    """可取消任务的包装"""

    task: asyncio.Task = field(hash=True)
    task_type: str
    created_at: float = field(default_factory=lambda: asyncio.get_event_loop().time(), hash=False, compare=False)

    def cancel(self) -> bool:
        """取消任务"""
        # 类型检查，防止非任务对象调用done()方法
        if not hasattr(self.task, "done") or not callable(getattr(self.task, "done")):
            # 记录错误但不抛出异常，避免中断整个取消流程
            logger.bind(tag=TAG).warning(
                f"CancellableTask.task is not a valid asyncio.Task: {type(self.task)}, value: {self.task}"
            )
            return False

        if not self.task.done():
            self.task.cancel()
            return True
        return False

    @property
    def is_done(self) -> bool:
        """检查任务是否完成"""
        # 类型检查，防止非任务对象调用done()方法
        if not hasattr(self.task, "done") or not callable(getattr(self.task, "done")):
            logger.bind(tag=TAG).warning(
                f"CancellableTask.task is not a valid asyncio.Task: {type(self.task)}, value: {self.task}"
            )
            return True
        return self.task.done()

    @property
    def is_cancelled(self) -> bool:
        """检查任务是否已被取消"""
        # 类型检查，防止非任务对象调用cancelled()方法
        if not hasattr(self.task, "cancelled") or not callable(getattr(self.task, "cancelled")):
            logger.bind(tag=TAG).warning(
                f"CancellableTask.task is not a valid asyncio.Task: {type(self.task)}, value: {self.task}"
            )
            return False  # 假设未取消，避免进一步错误
        return self.task.cancelled()


class CancellationManager:
    """任务取消管理器 - 统一管理所有任务的生命周期"""

    def __init__(self, context: "SessionContext"):
        self.context = context
        self.event_bus = context.event_bus
        self.logger = setup_logging()

        # 初始化任务类型
        self.task_types = CancellableTaskType

        # 按会话ID组织的任务集合
        self._session_tasks: Dict[str, Set[CancellableTask]] = {}

        # 当前文本任务跟踪 (用于替代StateManager的current_text_task)
        self._current_text_tasks: Dict[str, CancellableTask] = {}

        # 订阅相关事件
        self._subscribe_to_events()

    def _subscribe_to_events(self):
        """订阅相关事件"""
        self.event_bus.subscribe(
            event_type=EventTypes.SESSION_TASKS_CANCEL_REQUESTED,
            handler=self._handle_session_tasks_cancel_requested,
        )

    async def register_task(self, session_id: str, task: asyncio.Task, task_type: str) -> CancellableTask:
        """注册一个可取消的任务"""
        # 类型检查，确保传入的是asyncio.Task对象
        if not isinstance(task, asyncio.Task):
            self.logger.bind(tag=TAG).error(f"传入的task不是asyncio.Task对象，实际类型: {type(task)}, 值: {task}")
            raise TypeError(f"Expected asyncio.Task, got {type(task)}")

        cancellable_task = CancellableTask(
            task=task,
            task_type=task_type,
        )

        # 添加到会话任务集合
        if session_id not in self._session_tasks:
            self._session_tasks[session_id] = set()

        self._session_tasks[session_id].add(cancellable_task)

        # 如果是文本处理任务，记录为当前文本任务
        if task_type == self.task_types.TEXT_PROCESS_TASK:
            self._current_text_tasks[session_id] = cancellable_task

        # 任务完成时自动清理
        def cleanup_callback(fut):
            self._remove_task(session_id, cancellable_task)

        task.add_done_callback(cleanup_callback)

        # self.logger.bind(tag=TAG).debug(f"注册可取消任务: {session_id}, 类型: {task_type}")
        return cancellable_task

    def _remove_task(self, session_id: str, cancellable_task: CancellableTask):
        """移除任务（内部方法）"""
        if session_id in self._session_tasks:
            self._session_tasks[session_id].discard(cancellable_task)
            if not self._session_tasks[session_id]:
                del self._session_tasks[session_id]

        # 如果是当前文本任务，也要清理
        if session_id in self._current_text_tasks and self._current_text_tasks[session_id] == cancellable_task:
            del self._current_text_tasks[session_id]
            self.logger.bind(tag=TAG).debug(f"清理当前文本任务: {session_id}")

    async def _handle_session_tasks_cancel_requested(self, event: Event):
        """处理会话任务取消请求事件 - 立即取消所有相关任务"""
        session_id = event.session_id
        task_types = event.data.get("task_types", [])

        # 取消指定类型的任务，如果task_types为空则取消所有任务
        task_types_set = set(task_types) if task_types else None
        cancelled_count = await self.cancel_session_tasks(session_id, task_types_set)

        if cancelled_count > 0:
            self.logger.bind(tag=TAG).info(f"任务取消请求处理完成，取消了 {cancelled_count} 个任务")
        else:
            self.logger.bind(tag=TAG).warning("任务取消请求处理完成，没有需要取消的任务")

    async def cancel_session_tasks(self, session_id: str, task_types: Optional[Set[str]] = None) -> int:
        """取消指定会话的任务"""
        if session_id not in self._session_tasks:
            return 0

        tasks_to_cancel = self._session_tasks[session_id].copy()
        cancelled_count = 0

        for cancellable_task in tasks_to_cancel:
            # 如果指定了任务类型过滤
            if task_types and cancellable_task.task_type not in task_types:
                continue

            if cancellable_task.cancel():
                cancelled_count += 1
                self.logger.bind(tag=TAG).info(f"取消任务类型: {cancellable_task.task_type}, ")
        return cancelled_count

    def get_session_task_count(self, session_id: str) -> int:
        """获取指定会话的活跃任务数量"""
        if session_id not in self._session_tasks:
            return 0
        return len([t for t in self._session_tasks[session_id] if not t.is_done])

    def get_current_text_task(self, session_id: str) -> Optional[CancellableTask]:
        """获取当前文本任务 (替代StateManager的current_text_task)"""
        task = self._current_text_tasks.get(session_id)
        if task and task.is_done:
            # 清理已完成的任务
            del self._current_text_tasks[session_id]
            return None
        return task

    def has_active_tasks(self, session_id: str, task_types: Optional[Set[str]] = None) -> bool:
        """检查是否有活跃任务"""
        if session_id not in self._session_tasks:
            return False

        for task in self._session_tasks[session_id]:
            if task.is_done:
                continue
            if task_types and task.task_type not in task_types:
                continue
            return True
        return False

    def get_all_active_tasks(self) -> Dict[str, list]:
        """获取所有活跃任务信息（用于调试）"""
        result = {}
        for session_id, tasks in self._session_tasks.items():
            active_tasks = []
            for task in tasks:
                if not task.is_done:
                    active_tasks.append(
                        {
                            "type": task.task_type,
                            "age": asyncio.get_event_loop().time() - task.created_at,
                        }
                    )
            if active_tasks:
                result[session_id] = active_tasks
        return result

    def get_session_tasks_by_type(self, session_id: str, task_type: str) -> list[CancellableTask]:
        """根据类型获取会话任务"""
        if session_id not in self._session_tasks:
            return []

        return [task for task in self._session_tasks[session_id] if task.task_type == task_type and not task.is_done]
