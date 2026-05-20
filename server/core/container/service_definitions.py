from dataclasses import dataclass
from typing import Any, Callable

from core.container.factories import (
    asr_factory,
    llm_factory,
    memory_factory,
    tts_factory,
    vad_factory,
    vlm_factory,
)


@dataclass
class ServiceDefinition:
    name: str
    config_key: str
    factory: Callable[..., Any]
    is_singleton: bool = True
    is_core: bool = False


# 服务定义列表
# 新增服务时，只需在此处添加一个新的ServiceDefinition即可
SERVICE_DEFINITIONS = [
    ServiceDefinition(
        name="vad",
        config_key="VAD",
        factory=vad_factory.create_instance,
        is_singleton=True,
        is_core=True,
    ),
    ServiceDefinition(
        name="asr",
        config_key="ASR",
        factory=asr_factory.create_instance,
        is_singleton=True,
        is_core=True,
    ),
    ServiceDefinition(
        name="llm",
        config_key="LLM",
        factory=llm_factory.create_instance,
        is_singleton=True,
        is_core=True,
    ),
    ServiceDefinition(
        name="tts",
        config_key="TTS",
        factory=tts_factory.create_instance,
        is_singleton=True,
        is_core=True,
    ),
    ServiceDefinition(
        name="memory",
        config_key="Memory",
        factory=memory_factory.create_instance,
        is_singleton=True,
    ),
    ServiceDefinition(
        name="vlm",
        config_key="VLM",
        factory=vlm_factory.create_instance,
        is_singleton=True,
        is_core=False,
    ),
]
