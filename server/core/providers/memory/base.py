from abc import ABC, abstractmethod

from config.logger import setup_logging

TAG = __name__
logger = setup_logging()


class MemoryProviderBase(ABC):
    def __init__(self, config):
        self.config = config
        self.role_id = None
        self.llm = None
        self.session_id = None

    @abstractmethod
    async def save_memory(self, msgs):
        """Save a new memory for specific role and return memory ID"""
        return

    @abstractmethod
    async def query_memory(self, query: str) -> str:
        """Query memories for specific role based on similarity"""
        return None

    def init_memory(self, role_id, llm, session_id=None):
        self.role_id = role_id
        self.llm = llm
        self.session_id = session_id

    def close(self):
        # Implementation of close method
        pass
