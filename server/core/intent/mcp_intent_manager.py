"""MCP服务管理器"""

import asyncio
import json
import os
import time
import traceback
from typing import TYPE_CHECKING, Any, Dict, List

from config.logger import setup_logging
from config.server_config import ServerConfiger
from core.models import Action, ActionResponse, ToolType
from core.models.intent_models import IntentCall
from core.registries import register_function
from core.registries.mcp_registry import McpRegistry

if TYPE_CHECKING:
    from core.session.session_context import SessionContext

TAG = __name__


class McpIntentManager:
    """管理多个MCP服务的集中管理器"""

    def __init__(self, context: "SessionContext") -> None:
        """
        初始化MCP管理器
        """
        self.context = context
        self.function_registry = context.function_registry
        self.logger = setup_logging()

        self.config_path = ServerConfiger.get_project_dir() + "config/.mcp_server_settings.json"
        if not os.path.exists(self.config_path):
            self.config_path = ""
            self.logger.bind(tag=TAG).warning("请检查mcp服务配置文件：config/.mcp_server_settings.json")
        self.client: Dict[str, McpRegistry] = {}
        self.tools = []
        # 异步初始化MCP服务，不阻塞主流程
        asyncio.create_task(self.initialize_servers())

    async def initialize_servers(self) -> None:
        """初始化所有MCP服务"""
        try:
            if len(self.config_path) == 0:
                return {}
            with open(self.config_path, "r", encoding="utf-8") as f:
                config = json.load(f)
            config = config.get("mcpServers", {})
            if not config:
                self.logger.bind(tag=TAG).info("没有配置MCP服务，跳过初始化")
                return

            for name, srv_config in config.items():
                if not srv_config.get("command") and not srv_config.get("url"):
                    self.logger.bind(tag=TAG).warning(f"Skipping server {name}: neither command nor url specified")
                    continue

                try:
                    service_start_time = time.time()
                    client = McpRegistry(srv_config)

                    # 使用asyncio.wait_for添加超时控制，防止单个服务阻塞整个系统
                    await asyncio.wait_for(client.initialize(), timeout=5.0)

                    service_time = time.time() - service_start_time
                    self.logger.bind(tag=TAG).info(f"MCP服务 {name} 初始化成功，耗时: {service_time:.2f}秒")

                    self.client[name] = client
                    client_tools = client.get_available_tools()
                    self.logger.bind(tag=TAG).info(
                        f"MCP服务 {name} 提供的工具: {[tool['function']['name'] for tool in client_tools]}"
                    )
                    self.tools.extend(client_tools)
                    # 注册MCP工具到函数注册表
                    self._register_mcp_tools(client_tools)

                except asyncio.TimeoutError:
                    self.logger.bind(tag=TAG).warning(f"MCP服务 {name} 初始化超时(5秒)，跳过该服务")
                except Exception as e:
                    self.logger.bind(tag=TAG).warning(f"Failed to initialize MCP server {name}: {e}，跳过该服务")

        except Exception as e:
            self.logger.bind(tag=TAG).warning(f"MCP服务初始化过程中出现错误: {e}，但不影响主服务运行")
            self.logger.bind(tag=TAG).debug(traceback.format_exc())

    def get_all_tools(self) -> List[Dict[str, Any]]:
        """获取所有服务的工具function定义
        Returns:
            List[Dict[str, Any]]: 所有工具的function定义列表
        """
        return self.tools

    async def _execute_mcp_tool(self, tool_name: str, arguments: Dict[str, Any]) -> Any:
        """执行工具调用
        Args:
            tool_name: 工具名称
            arguments: 工具参数
        Returns:
            Any: 工具执行结果
        Raises:
            ValueError: 工具未找到时抛出
        """
        self.logger.bind(tag=TAG).info(f"Executing tool {tool_name} with arguments: {arguments}")
        for client in self.client.values():
            if client.has_tool(tool_name):
                return await client.call_tool(tool_name, arguments)

        raise ValueError(f"Tool {tool_name} not found in any MCP server")

    def _register_mcp_tools(self, client_tools: List[Dict[str, Any]]) -> None:
        """注册MCP工具到函数注册表"""
        for tool in client_tools:
            func_name = tool["function"]["name"]

            # 创建MCP工具的包装函数 - 使用默认参数避免闭包问题
            def create_mcp_wrapper(tool_name=func_name):
                async def mcp_wrapper(context, **kwargs):
                    try:
                        result = await self._execute_mcp_tool(tool_name, kwargs)

                        return ActionResponse(action=Action.RESPONSE, result=result, response=str(result))
                    except Exception as e:
                        self.logger.bind(tag=TAG).error(f"MCP工具 {tool_name} 执行失败: {e}")
                        return ActionResponse(action=Action.NOTFOUND, result=str(e), response="")

                return mcp_wrapper

            # 注册到全局函数注册表
            register_function(func_name, tool, ToolType.MCP_CLIENT)(create_mcp_wrapper())

            # 注册到本地函数注册表
            self.context.function_intent_manager.function_registry.register_function(func_name)

    async def cleanup_all_mcp_tools(self) -> None:
        for name, client in self.client.items():
            try:
                await client.cleanup()
                self.logger.bind(tag=TAG).info(f"Cleaned up MCP client: {name}")
            except Exception as e:
                self.logger.bind(tag=TAG).exception(f"Error cleaning up MCP client {name}: {e}")
        self.client.clear()

    async def handle_mcp_tool_call(self, intent_call: "IntentCall") -> ActionResponse:
        """处理MCP工具调用，专门用于意图识别后的调用

        Args:
            function_call_data: 函数调用数据，包含name和arguments

        Returns:
            ActionResponse: 返回REQLLM动作，将结果传递给LLM处理
        """
        function_arguments = intent_call.arguments
        function_name = intent_call.name

        try:
            args_dict = function_arguments
            if isinstance(function_arguments, str):
                try:
                    args_dict = json.loads(function_arguments)
                except json.JSONDecodeError:
                    self.logger.bind(tag=TAG).error(f"无法解析 function_arguments: {function_arguments}")
                    return ActionResponse(action=Action.REQLLM, result="参数解析失败", response="")

            # 添加超时控制，防止MCP工具调用阻塞主程序

            tool_result = await asyncio.wait_for(
                self._execute_mcp_tool(function_name, args_dict),
                timeout=30.0,  # 30秒超时
            )
            self.logger.bind(tag=TAG).info(f"MCP工具 {function_name} 调用成功，结果: {tool_result}")

            content_text = ""
            if tool_result is not None and tool_result.content is not None:
                for content in tool_result.content:
                    content_type = content.type
                    if content_type == "text":
                        content_text = content.text
                    elif content_type == "image":
                        pass

            if len(content_text) > 0:
                return ActionResponse(action=Action.REQLLM, result=content_text, response="")

        except asyncio.TimeoutError:
            self.logger.bind(tag=TAG).error(f"MCP工具 {function_name} 调用超时(30秒)")
            return ActionResponse(action=Action.REQLLM, result="工具调用超时，请稍后重试", response="")
        except Exception as e:
            self.logger.bind(tag=TAG).error(f"MCP工具调用错误: {e}, 追踪: {traceback.format_exc()}")
            return ActionResponse(action=Action.REQLLM, result="工具调用出错", response="")

    def get_current_mcp_tools_with_names(self):
        """获取当前注册的MCP工具列表"""
        mcp_tools = []
        function_desc = self.function_registry.get_all_function_desc()
        for func in function_desc:
            func_name = func["function"]["name"]
            # 获取对应的FunctionItem来检查类型
            function_item = self.function_registry.get_function(func_name)
            # 只包含MCP工具
            if function_item and function_item.type == ToolType.MCP_CLIENT:
                mcp_tools.append(func_name)
        return mcp_tools

    def get_current_mcp_tools_with_details(self) -> List[Dict[str, Any]]:
        """
        获取当前可用MCP工具的详细信息列表
        返回格式与系统函数保持一致，便于统一处理

        Returns:
            List[Dict[str, Any]]: MCP工具信息列表，每个元素包含:
                - name: 工具名称
                - description: 工具描述
                - parameters: 工具参数定义
        """
        current_mcp_names = self.get_current_mcp_tools_with_names()
        all_tools = self.get_all_tools()

        tool_details = []
        for tool in all_tools:
            tool_name = tool["function"]["name"]
            if tool_name in current_mcp_names:
                # 直接提取函数信息，保持与系统函数相同的格式
                function_info = tool["function"]
                tool_details.append(
                    {
                        "name": function_info["name"],
                        "description": function_info["description"],
                        "parameters": function_info["parameters"],
                    }
                )
        return tool_details
