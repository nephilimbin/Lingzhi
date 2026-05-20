import json
import os
from typing import TYPE_CHECKING, Dict, List, Optional

from core.utils.util import get_current_time, set_unique_id

if TYPE_CHECKING:
    from core.providers.llm.base import LLMResponseInfo

TAG = __name__


class DialogueMessage:
    """对话消息基类"""

    def __init__(
        self,
        role: str,
        content: str = None,
        uniq_id: str = None,
        current_time: str = None,
        session_request_id: str = None,
    ):
        self.uniq_id = uniq_id if uniq_id is not None else set_unique_id("dialogue_message")
        self.role = role
        self.content = content
        self.current_time = current_time or get_current_time(format="%Y-%m-%d %H:%M:%S")
        self.session_request_id = session_request_id  # 请求ID，用于关联同一次对话请求的所有消息

    def to_dict(self):
        """将消息转换为字典格式以便保存"""
        return {
            "uniq_id": self.uniq_id,
            "role": self.role,
            "content": self.content,
            "current_time": self.current_time,
            "session_request_id": self.session_request_id,
        }

    @classmethod
    def from_dict(cls, data: Dict):
        """从字典格式恢复消息"""
        role = data["role"]

        # 根据角色创建对应的子类实例
        if role == "system":
            return SystemMessage.from_dict(data)
        elif role == "user":
            return UserMessage.from_dict(data)
        elif role == "assistant":
            return AssistantMessage.from_dict(data)
        elif role == "tool":
            return ToolMessage.from_dict(data)
        else:
            # 默认创建基类实例
            return cls(
                role=role,
                content=data.get("content"),
                uniq_id=data.get("uniq_id"),
                current_time=data.get("current_time"),
                session_request_id=data.get("session_request_id"),
            )


class SystemMessage(DialogueMessage):
    """系统消息"""

    def __init__(
        self,
        content: str = None,
        uniq_id: str = None,
        current_time: str = None,
        session_request_id: str = None,
    ):
        super().__init__("system", content, uniq_id, current_time, session_request_id)

    @classmethod
    def from_dict(cls, data: Dict):
        return cls(
            content=data.get("content"),
            uniq_id=data.get("uniq_id"),
            current_time=data.get("current_time"),
            session_request_id=data.get("session_request_id"),
        )


class UserMessage(DialogueMessage):
    """用户消息"""

    def __init__(
        self,
        content: str = None,
        uniq_id: str = None,
        current_time: str = None,
        session_request_id: str = None,
    ):
        super().__init__("user", content, uniq_id, current_time, session_request_id)

    @classmethod
    def from_dict(cls, data: Dict):
        return cls(
            content=data.get("content"),
            uniq_id=data.get("uniq_id"),
            current_time=data.get("current_time"),
            session_request_id=data.get("session_request_id"),
        )


class AssistantMessage(DialogueMessage):
    """助手消息，包含统计信息"""

    def __init__(
        self,
        content: str = None,
        uniq_id: str = None,
        current_time: str = None,
        model_name: str = None,
        total_token_count: int = None,
        prompt_token_count: int = None,
        candidates_token_count: int = None,
        model_response_duration: float = None,
        tool_calls=None,
        session_request_id: str = None,
    ):
        super().__init__("assistant", content, uniq_id, current_time, session_request_id)

        # 统计信息字段
        self.model_name = model_name
        self.total_token_count = total_token_count
        self.prompt_token_count = prompt_token_count
        self.candidates_token_count = candidates_token_count
        self.model_response_duration = model_response_duration
        self.tool_calls = tool_calls

    def to_dict(self):
        """将消息转换为字典格式以便保存"""
        base_dict = super().to_dict()
        base_dict.update(
            {
                "model_name": self.model_name,
                "total_token_count": self.total_token_count,
                "prompt_token_count": self.prompt_token_count,
                "candidates_token_count": self.candidates_token_count,
                "model_response_duration": self.model_response_duration,
                "tool_calls": self.tool_calls,
            }
        )
        return base_dict

    @classmethod
    def from_dict(cls, data: Dict):
        return cls(
            content=data.get("content"),
            uniq_id=data.get("uniq_id"),
            current_time=data.get("current_time"),
            model_name=data.get("model_name"),
            total_token_count=data.get("total_token_count"),
            prompt_token_count=data.get("prompt_token_count"),
            candidates_token_count=data.get("candidates_token_count"),
            model_response_duration=data.get("model_response_duration"),
            tool_calls=data.get("tool_calls"),
            session_request_id=data.get("session_request_id"),
        )


class ToolMessage(DialogueMessage):
    """工具调用结果消息"""

    def __init__(
        self,
        content: str = None,
        tool_call_id: str = None,
        uniq_id: str = None,
        current_time: str = None,
        session_request_id: str = None,
    ):
        super().__init__("tool", content, uniq_id, current_time, session_request_id)
        self.tool_call_id = tool_call_id

    def to_dict(self):
        """将消息转换为字典格式以便保存"""
        base_dict = super().to_dict()
        base_dict["tool_call_id"] = self.tool_call_id
        return base_dict

    @classmethod
    def from_dict(cls, data: Dict):
        return cls(
            content=data.get("content"),
            tool_call_id=data.get("tool_call_id"),
            uniq_id=data.get("uniq_id"),
            current_time=data.get("current_time"),
            session_request_id=data.get("session_request_id"),
        )


class ErrorMessage(DialogueMessage):
    """错误消息"""

    def __init__(
        self,
        content: str = None,
        uniq_id: str = None,
        current_time: str = None,
        session_request_id: str = None,
    ):
        super().__init__("error", content, uniq_id, current_time, session_request_id)

    @classmethod
    def from_dict(cls, data: Dict):
        return cls(
            content=data.get("content"),
            uniq_id=data.get("uniq_id"),
            current_time=data.get("current_time"),
            session_request_id=data.get("session_request_id"),
        )


class SessionDialogue:
    def __init__(self, session_id: str = None, dialogue_context_num: int = 20):
        self.session_id = session_id or set_unique_id("session_id")
        self.dialogue_message: List[DialogueMessage] = []
        self.dialogue_context_num = dialogue_context_num  # 对话上下文数量限制

    def add_message(self, message: DialogueMessage):
        self.dialogue_message.append(message)

    def _format_message(self, m: DialogueMessage) -> Dict:
        """格式化单条消息为LLM需要的格式"""
        message_data = {
            "role": m.role,
            "current_time": m.current_time or get_current_time(format="%Y-%m-%d %H:%M:%S"),
        }

        if isinstance(m, AssistantMessage) and m.tool_calls is not None:
            message_data["tool_calls"] = m.tool_calls
        elif isinstance(m, ToolMessage):
            message_data.update({"tool_call_id": m.tool_call_id, "content": m.content})
        else:
            message_data["content"] = m.content
        return message_data

    def _get_limited_dialogue(self, messages: List[DialogueMessage]) -> List[DialogueMessage]:
        """获取受限制的对话历史，保留系统消息和最近的对话"""

        # 分离系统消息和其他消息
        system_messages = [msg for msg in messages if isinstance(msg, SystemMessage)]
        other_messages = [msg for msg in messages if isinstance(msg, (AssistantMessage, UserMessage, ToolMessage))]

        # 计算可用的非系统消息数量
        available_slots = self.dialogue_context_num - len(system_messages)
        if available_slots <= 0:
            # 如果系统消息过多，只保留最新的系统消息
            return system_messages[-self.dialogue_context_num :]

        # 保留最近的非系统消息
        recent_other_messages = other_messages[-available_slots:]

        return system_messages + recent_other_messages

    def get_llm_dialogue(self, return_objects: bool = False) -> List:
        """获取当前对话的LLM格式，受设定的上下文数量限制

        Args:
            return_objects: 是否返回对象列表而不是字典格式

        Returns:
            如果 return_objects=True: 返回 DialogueMessage 对象列表
            如果 return_objects=False: 返回字典格式列表（默认行为，保持向后兼容）
        """
        limited_dialogue = self._get_limited_dialogue(self.dialogue_message)
        if return_objects:
            return limited_dialogue
        else:
            return [self._format_message(m) for m in limited_dialogue]

    def get_system_role_dialogue(self) -> List[Dict[str, SystemMessage]]:
        """获取仅包含系统角色的对话内容"""
        system_messages = [msg for msg in self.dialogue_message if isinstance(msg, SystemMessage)]
        return [self._format_message(m) for m in system_messages]

    def get_assistant_role_dialogue(self) -> List[Dict[str, AssistantMessage]]:
        """获取仅包含助手角色的对话内容"""
        assistant_messages = [msg for msg in self.dialogue_message if isinstance(msg, AssistantMessage)]
        return [self._format_message(m) for m in assistant_messages]

    def get_llm_dialogue_with_memory(self, memory_str: str = None) -> List[Dict[str, str]]:
        """获取带记忆内容的LLM格式对话，受上下文数量限制"""
        limited_dialogue = self._get_limited_dialogue(self.dialogue_message)

        if memory_str is None or len(memory_str) == 0:
            return [self._format_message(m) for m in limited_dialogue]

        dialogue = []
        # 添加系统提示和记忆
        system_messages = [msg for msg in limited_dialogue if isinstance(msg, SystemMessage)]
        if system_messages:
            # 增强最后一个系统消息
            enhanced_system_msg = system_messages[-1]
            enhanced_system_prompt = f"{enhanced_system_msg.content}\n\n相关记忆：\n{memory_str}"
            dialogue.append({"role": "system", "content": enhanced_system_prompt})

            # 添加其他系统消息（如果有多个）
            for msg in system_messages[:-1]:
                dialogue.append(self._format_message(msg))

        # 添加用户和助手的对话
        for m in limited_dialogue:
            if not isinstance(m, SystemMessage):
                dialogue.append(self._format_message(m))
        return dialogue

    def set_system_prompt(self, new_content: str):
        """更新或添加系统消息"""
        system_msg = None
        for msg in self.dialogue_message:
            if isinstance(msg, SystemMessage):
                system_msg = msg
        if system_msg:
            system_msg.content = new_content
        else:
            self.add_message(SystemMessage(content=new_content))

    def get_system_prompt(self) -> Optional[str]:
        """获取当前系统消息内容"""
        for msg in self.dialogue_message:
            if isinstance(msg, SystemMessage):
                return msg.content
        return None

    def add_system_message(self, content: str, session_request_id: str = None) -> SystemMessage:
        """添加系统消息的便捷方法"""
        msg = SystemMessage(content=content, session_request_id=session_request_id)
        self.add_message(msg)
        return msg

    def add_user_message(self, content: str, session_request_id: str = None) -> UserMessage:
        """添加用户消息的便捷方法，会自动生成新的session_request_id"""
        if session_request_id is None:
            session_request_id = set_unique_id("session_request_id")  # 用户消息开始新的请求，生成新的session_request_id
        msg = UserMessage(content=content, session_request_id=session_request_id)
        self.add_message(msg)
        return msg

    def add_assistant_message(
        self,
        content: str = None,
        model_name: str = None,
        total_token_count: int = None,
        prompt_token_count: int = None,
        candidates_token_count: int = None,
        model_response_duration: float = None,
        tool_calls=None,
        session_request_id: str = None,
        llm_response_info: Optional["LLMResponseInfo"] = None,
    ) -> AssistantMessage:
        """添加助手消息的便捷方法

        Args:
            content: 助手消息内容
            model_name: 模型名称
            total_token_count: 总token数量
            prompt_token_count: 提示token数量
            candidates_token_count: 候选token数量
            model_response_duration: 模型响应时长（秒）
            tool_calls: 工具调用信息
            session_request_id: 请求ID
            llm_response_info: LLM响应信息对象，自动提取统计字段（当其他参数为None时使用）
        """
        # 从 LLMResponseInfo 自动提取缺失的字段
        if llm_response_info:
            model_name = model_name or llm_response_info.model_name
            total_token_count = total_token_count or llm_response_info.total_token_count
            prompt_token_count = prompt_token_count or llm_response_info.prompt_token_count
            candidates_token_count = candidates_token_count or llm_response_info.candidates_token_count
            model_response_duration = model_response_duration or llm_response_info.model_response_duration
            tool_calls = tool_calls or llm_response_info.tool_calls

        msg = AssistantMessage(
            content=content,
            model_name=model_name,
            total_token_count=total_token_count,
            prompt_token_count=prompt_token_count,
            candidates_token_count=candidates_token_count,
            model_response_duration=model_response_duration,
            tool_calls=tool_calls,
            session_request_id=session_request_id,
        )
        self.add_message(msg)
        return msg

    def add_tool_message(self, content: str, tool_call_id: str, session_request_id: str = None) -> ToolMessage:
        """添加工具消息的便捷方法"""
        msg = ToolMessage(content=content, tool_call_id=tool_call_id, session_request_id=session_request_id)
        self.add_message(msg)
        return msg

    def get_dialogue_context_num(self) -> int:
        """获取对话上下文数量限制"""
        return self.dialogue_context_num

    def set_dialogue_context_num(self, num: int):
        """设置对话上下文数量限制"""
        self.dialogue_context_num = max(1, num)  # 确保至少为1

    def get_session_id(self) -> str:
        """获取会话ID"""
        return self.session_id

    def get_messages_by_session_request_id(self, session_request_id: str) -> List[DialogueMessage]:
        """根据session_request_id获取相关的所有消息"""
        return [msg for msg in self.dialogue_message if msg.session_request_id == session_request_id]

    def get_latest_session_request_id(self) -> Optional[str]:
        """获取最新的请求ID（最后一个用户消息的session_request_id）"""
        for msg in reversed(self.dialogue_message):
            if isinstance(msg, UserMessage) and msg.session_request_id:
                return msg.session_request_id
        return None

    def save_to_file(self, filepath: str, save_limited_only: bool = False):
        """将对话保存到文件

        Args:
            filepath: 保存路径
            save_limited_only: 是否只保存受限制的对话（根据dialogue_context_num）
        """
        try:
            # 确保目录存在
            os.makedirs(os.path.dirname(filepath), exist_ok=True)

            # 选择要保存的对话
            dialogue_to_save = (
                self._get_limited_dialogue(self.dialogue_message) if save_limited_only else self.dialogue_message
            )

            # 转换为字典格式
            dialogue_data = {
                "session_id": self.session_id,
                "dialogue_context_num": self.dialogue_context_num,
                "messages": [msg.to_dict() for msg in dialogue_to_save],
            }

            # 保存到文件
            with open(filepath, "w", encoding="utf-8") as f:
                json.dump(dialogue_data, f, ensure_ascii=False, indent=2)

        except Exception as e:
            self.logger.bind(tag=TAG).error(f"保存对话到文件失败: {e}")

    def get_dialogue_stats(self) -> Dict:
        """获取对话统计信息"""
        stats = {
            "total_messages": len(self.dialogue_message),
            "system_messages": len([msg for msg in self.dialogue_message if isinstance(msg, SystemMessage)]),
            "user_messages": len([msg for msg in self.dialogue_message if isinstance(msg, UserMessage)]),
            "assistant_messages": len([msg for msg in self.dialogue_message if isinstance(msg, AssistantMessage)]),
            "tool_messages": len([msg for msg in self.dialogue_message if isinstance(msg, ToolMessage)]),
            "dialogue_context_num": self.dialogue_context_num,
        }

        # 统计token使用情况（只统计助手消息）
        total_tokens = 0
        prompt_tokens = 0
        candidates_tokens = 0

        for msg in self.dialogue_message:
            if isinstance(msg, AssistantMessage):
                if msg.total_token_count:
                    total_tokens += msg.total_token_count
                if msg.prompt_token_count:
                    prompt_tokens += msg.prompt_token_count
                if msg.candidates_token_count:
                    candidates_tokens += msg.candidates_token_count

        stats.update(
            {
                "total_tokens": total_tokens,
                "prompt_tokens": prompt_tokens,
                "candidates_tokens": candidates_tokens,
            }
        )

        return stats

    def load_from_file(self, filepath: str) -> bool:
        """从文件加载对话"""
        try:
            with open(filepath, "r", encoding="utf-8") as f:
                dialogue_file = json.load(f)

            self.session_id = dialogue_file.get("session_id", set_unique_id("session_id"))
            self.dialogue_context_num = dialogue_file.get("dialogue_context_num", 20)
            self.dialogue_message = []

            for msg in dialogue_file.get("messages", []):
                msg = DialogueMessage.from_dict(msg)
                self.dialogue_message.append(msg)

            return True
        except Exception as e:
            self.logger.bind(tag=TAG).error(f"从文件加载对话失败: {e}")
            return False
