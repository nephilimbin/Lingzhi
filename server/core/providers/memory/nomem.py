"""
不使用记忆，可以选择此模块
"""

from core.providers.memory.base import MemoryProviderBase

TAG = __name__


class MemoryProvider(MemoryProviderBase):
    def __init__(self, config):
        super().__init__(config)

    async def save_memory(self, msgs):
        return None

    async def query_memory(self, query: str) -> str:
        return ""
