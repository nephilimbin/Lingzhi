from contextlib import AsyncExitStack
from datetime import timedelta
import os
import shutil
from typing import Optional

from config.logger import setup_logging
from mcp import ClientSession, StdioServerParameters
from mcp.client.sse import sse_client
from mcp.client.stdio import stdio_client

TAG = __name__


class McpRegistry:
    def __init__(self, config):
        # Initialize session and client objects
        self.session: Optional[ClientSession] = None
        self.exit_stack = AsyncExitStack()
        self.logger = setup_logging()
        self.config = config
        self.tools = []
        # 判断连接类型：URL (SSE) 或 Command (stdio)
        self.connection_type = "sse" if config.get("url") else "stdio"

    async def initialize(self):
        if self.connection_type == "sse":
            await self._initialize_sse()
        else:
            await self._initialize_stdio()

        # 尝试初始化会话，处理roots兼容性问题
        try:
            await self.session.initialize()
        except Exception as e:
            # 处理所有MCP协议兼容性问题
            error_msg = str(e)
            if any(keyword in error_msg for keyword in ["List roots not supported", "-32600", "Method not found", "Unsupported"]):
                self.logger.bind(tag=TAG).warning(f"MCP服务兼容性警告，使用基本功能继续: {e}")
                # 继续使用基本功能，不中断连接
            else:
                self.logger.bind(tag=TAG).error(f"MCP会话初始化失败: {e}")
                raise

        # List available tools
        try:
            response = await self.session.list_tools()
            tools = response.tools
            self.tools = tools
            # self.logger.bind(tag=TAG).info(f"Connected to server via {self.connection_type} with tools:{[tool.name for tool in tools]}")
        except Exception as e:
            self.logger.bind(tag=TAG).error(f"获取工具列表失败: {e}")
            raise

    async def _initialize_sse(self):
        """初始化 SSE 连接"""
        url = self.config["url"]

        # 使用 SSE 客户端连接
        sse_transport = await self.exit_stack.enter_async_context(sse_client(url))

        time_out_delta = timedelta(seconds=60)  # 增加超时时间到60秒
        self.session = await self.exit_stack.enter_async_context(
            ClientSession(
                read_stream=sse_transport[0],
                write_stream=sse_transport[1],
                read_timeout_seconds=time_out_delta,
            )
        )

    async def _initialize_stdio(self):
        """初始化 stdio 连接"""
        args = self.config.get("args", [])

        command = shutil.which("npx") if self.config["command"] == "npx" else self.config["command"]

        env = {**os.environ}
        if self.config.get("env"):
            env.update(self.config["env"])

        server_params = StdioServerParameters(command=command, args=args, env=env)
        # self.logger.bind(tag=TAG).info(f"Initializing stdio connection with command: {command}")

        # 使用asyncio.run_coroutine_threadsafe来运行stdio_client
        stdio_transport = await self.exit_stack.enter_async_context(stdio_client(server_params))
        self.stdio, self.write = stdio_transport
        time_out_delta = timedelta(seconds=60)  # 增加超时时间到60秒

        self.session = await self.exit_stack.enter_async_context(
            ClientSession(
                read_stream=self.stdio,
                write_stream=self.write,
                read_timeout_seconds=time_out_delta,
            )
        )

    def has_tool(self, tool_name):
        return any(tool.name == tool_name for tool in self.tools)

    def get_available_tools(self):
        available_tools = [
            {
                "type": "function",
                "function": {
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": tool.inputSchema,
                },
            }
            for tool in self.tools
        ]
        return available_tools

    async def call_tool(self, tool_name: str, tool_args: dict):
        self.logger.bind(tag=TAG).info(f"MCPClient Calling tool {tool_name} with args: {tool_args}")
        try:
            response = await self.session.call_tool(tool_name, tool_args)
        except Exception as e:
            self.logger.bind(tag=TAG).error(f"Error calling tool {tool_name}: {e}")
            from types import SimpleNamespace

            error_content = SimpleNamespace(type="text", text=f"Error calling tool {tool_name}: {e}")
            error_response = SimpleNamespace(content=[error_content], isError=True)
            return error_response
        # self.logger.bind(tag=TAG).info(f"MCPClient Response from tool {tool_name}: {response}")
        return response

    async def cleanup(self):
        """Clean up resources"""
        try:
            self.logger.bind(tag=TAG).debug("Attempting to close AsyncExitStack...")
            await self.exit_stack.aclose()
            self.logger.bind(tag=TAG).debug("AsyncExitStack closed successfully.")
        except RuntimeError as e:
            if "Attempted to exit cancel scope in a different task" in str(e):
                self.logger.bind(tag=TAG).warning(f"Ignoring expected anyio task mismatch error during stack cleanup: {e}")
            else:
                # Log other unexpected RuntimeErrors
                self.logger.bind(tag=TAG).error(f"RuntimeError during AsyncExitStack cleanup: {e}", exc_info=True)
        except Exception as e:
            # Catch any other potential errors during cleanup
            self.logger.bind(tag=TAG).error(f"Unexpected error during AsyncExitStack cleanup: {e}", exc_info=True)
