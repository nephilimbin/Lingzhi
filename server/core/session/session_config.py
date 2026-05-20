from dataclasses import dataclass
from typing import Any, Dict, Optional


@dataclass
class SessionTTSConfig:
    """TTS相关配置"""

    tts_response_timeout: int = 10
    tts_silent_timeout_shutdown_duration: int = 700

    @classmethod
    def from_config(cls, config: Dict[str, Any]) -> "SessionTTSConfig":
        """从全局配置创建TTS配置"""
        return cls(
            tts_response_timeout=config.get("tts_response_timeout", 10),
            tts_silent_timeout_shutdown_duration=config.get("tts_silent_timeout_shutdown_duration", 120),
        )


@dataclass
class SessionVADConfig:
    """VAD相关配置"""

    silence_threshold_ms: int = 1000

    @classmethod
    def from_config(cls, config: Dict[str, Any]) -> "SessionVADConfig":
        """从全局配置创建VAD配置"""
        # 从VAD配置中获取silence_duration_ms参数
        silence_duration_ms = config.get("silence_threshold_ms", 1000)

        return cls(silence_threshold_ms=silence_duration_ms)


@dataclass
class SessionExitConfig:
    """退出命令配置"""

    cmd_exit: Any = None
    max_length: int = 0

    @classmethod
    def from_config(cls, config: Dict[str, Any]) -> "SessionExitConfig":
        """从全局配置创建退出命令配置"""
        cmd_exit = config.get("cmd_exit", [])
        max_cmd_length = 0

        if isinstance(cmd_exit, list):
            for cmd in cmd_exit:
                if isinstance(cmd, str) and len(cmd) > max_cmd_length:
                    max_cmd_length = len(cmd)
        elif isinstance(cmd_exit, str):
            max_cmd_length = len(cmd_exit)

        return cls(cmd_exit=cmd_exit, max_length=max_cmd_length)


@dataclass
class SessionDialogueConfig:
    """对话配置"""

    dialogue_context_num: int = 20

    @classmethod
    def from_config(cls, config: Dict[str, Any]) -> "SessionDialogueConfig":
        """从全局配置创建对话配置"""
        return cls(dialogue_context_num=config.get("dialogue_context_num", 20))


@dataclass
class SessionLLMConfig:
    """LLM配置管理"""

    llm_configs: Dict[str, Any] = None

    def __post_init__(self):
        if self.llm_configs is None:
            self.llm_configs = {}

    def get_llm_config(self, llm_name: str) -> Optional[Dict[str, Any]]:
        """获取指定LLM的配置"""
        return self.llm_configs.get(llm_name)

    def get_llm_type(self, llm_name: str) -> str:
        """获取指定LLM的类型，如果未配置则使用LLM名称作为默认类型"""
        llm_config = self.get_llm_config(llm_name)
        if llm_config:
            return llm_config.get("type", llm_name)
        return llm_name

    def has_llm(self, llm_name: str) -> bool:
        """检查是否存在指定LLM配置"""
        return llm_name in self.llm_configs

    @classmethod
    def from_config(cls, config: Dict[str, Any]) -> "SessionLLMConfig":
        """从全局配置创建LLM配置"""
        llm_configs = config.get("LLM", {})
        return cls(llm_configs=llm_configs)


@dataclass
class SessionIntentConfig:
    """意图识别配置"""

    intent_llm_name: str = ""
    wakeup_words: list = None
    wakeup_words_notify_voice: str = ""
    enable_wakeup_words_response: bool = True

    def __post_init__(self):
        if self.wakeup_words is None:
            self.wakeup_words = []

    @classmethod
    def from_config(cls, config: Dict[str, Any]) -> "SessionIntentConfig":
        """从全局配置创建意图配置"""
        selected_modules = config.get("selected_module", {})
        intent_llm_name = selected_modules.get("Intent", "")

        # 从配置文件获取唤醒词相关配置
        wakeup_words = config.get("wakeup_words", [])
        wakeup_words_notify_voice = config.get("wakeup_words_notify_voice", "")
        enable_wakeup_words_response = config.get("enable_wakeup_words_response", True)

        return cls(
            intent_llm_name=intent_llm_name,
            wakeup_words=wakeup_words,
            wakeup_words_notify_voice=wakeup_words_notify_voice,
            enable_wakeup_words_response=enable_wakeup_words_response,
        )


@dataclass
class SessionFunctionConfig:
    """功能调用配置"""

    use_function_call_mode: bool = False

    @classmethod
    def from_config(cls, config: Dict[str, Any]) -> "SessionFunctionConfig":
        """从全局配置创建功能配置"""
        selected_intent = config.get("selected_module", {}).get("Intent", "")
        return cls(use_function_call_mode=(selected_intent == "function_call"))


@dataclass
class SessionPromptTemplate:
    """提示词模板配置管理"""

    intent_prompt_template: str = "template/intent_prompt_template.md"
    system_prompt_template: str = "template/system_prompt_template.md"

    def get_intent_prompt_template_path(self) -> str:
        """获取意图提示词模板路径"""
        return self.intent_prompt_template

    def get_system_prompt_template_path(self) -> str:
        """获取系统提示词模板路径"""
        return self.system_prompt_template

    @classmethod
    def from_config(cls, config: Dict[str, Any]) -> "SessionPromptTemplate":
        """从全局配置创建提示词模板配置"""
        return cls(
            intent_prompt_template=config.get("intent_prompt_template", "template/intent_prompt_template.md"),
            system_prompt_template=config.get("system_prompt_template", "template/system_prompt_template.md"),
        )


@dataclass
class SessionRuntimeConfig:
    """会话运行时配置的集合"""

    session_tts_config: SessionTTSConfig
    session_exit_config: SessionExitConfig
    session_dialogue_config: SessionDialogueConfig
    session_llm_config: SessionLLMConfig
    session_intent_config: SessionIntentConfig
    session_function_config: SessionFunctionConfig
    session_vad_config: SessionVADConfig
    session_prompt_template: SessionPromptTemplate

    @classmethod
    def from_config(cls, config: Dict[str, Any]) -> "SessionRuntimeConfig":
        """从全局配置创建运行时配置"""
        return cls(
            session_tts_config=SessionTTSConfig.from_config(config),
            session_exit_config=SessionExitConfig.from_config(config),
            session_dialogue_config=SessionDialogueConfig.from_config(config),
            session_llm_config=SessionLLMConfig.from_config(config),
            session_intent_config=SessionIntentConfig.from_config(config),
            session_function_config=SessionFunctionConfig.from_config(config),
            session_vad_config=SessionVADConfig.from_config(config),
            session_prompt_template=SessionPromptTemplate.from_config(config),
        )
