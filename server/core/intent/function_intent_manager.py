import json
from typing import TYPE_CHECKING

from config.logger import setup_logging
from core.models import Action, ActionResponse, ToolType
from core.models.intent_models import IntentCall
from plugins.functions.hass_init import append_devices_to_prompt

if TYPE_CHECKING:
    from core.session.session_context import SessionContext

TAG = __name__


class FunctionIntentManager:
    def __init__(self, context: "SessionContext"):
        self.context = context
        self.config = context.config
        self.logger = setup_logging()
        self.function_registry = context.function_registry
        self.selected_function_plugins = self.config.get("selected_function_plugins", {})
        self.finish_init = True
        self._register_config_functions()
        self.functions_desc = self.function_registry.get_all_function_desc()

    def modify_plugin_loader_des(self, func_names):
        """
        修改plugin_loader的描述，去掉plugin_loader
        """
        if "plugin_loader" not in func_names:
            return
        # 可编辑的列表中去掉plugin_loader
        surport_plugins = [func for func in func_names if func != "plugin_loader"]
        func_names = ",".join(surport_plugins)
        for function_desc in self.functions_desc:
            if function_desc["function"]["name"] == "plugin_loader":
                function_desc["function"]["description"] = function_desc["function"]["description"].replace("[plugins]", func_names)
                break

    def _register_config_functions(self):
        """注册配置中的函数,可以不同客户端使用不同的配置"""
        # 优先使用新的function_plugins配置
        function_plugins = self.selected_function_plugins
        # 注册必要函数
        required_functions = function_plugins.get("required", [])

        if required_functions:
            for func in required_functions:
                self.function_registry.register_function(func)
        else:
            # 否则使用默认的必要函数
            self.function_registry.register_function("handle_exit_intent")
            self.function_registry.register_function("plugin_loader")
            self.function_registry.register_function("handle_device")

        # 注册可选函数
        optional_functions = function_plugins.get("optional", [])
        for func in optional_functions:
            self.function_registry.register_function(func)

        """home assistant需要初始化提示词"""
        append_devices_to_prompt(self.context)

    def _get_function(self, name):
        return self.function_registry.get_function(name)

    async def handle_llm_function_call(self, intent_call: "IntentCall") -> ActionResponse:
        try:
            function_name = intent_call.name
            funcItem = self._get_function(function_name)
            if not funcItem:
                return ActionResponse(action=Action.NOTFOUND, result="没有找到对应的函数", response="")
            func = funcItem.func
            arguments = intent_call.arguments
            # 检查arguments类型，如果是字符串才需要JSON解析
            if isinstance(arguments, str):
                try:
                    arguments = json.loads(arguments) if arguments else {}
                except json.JSONDecodeError as e:
                    self.logger.bind(tag=TAG).error(f"无法解析arguments参数: {arguments}, 错误: {e}")
                    return ActionResponse(
                        action=Action.REQLLM,
                        result="参数解析失败",
                        response="抱歉，函数参数格式错误，请重新尝试。",
                    )
            # 如果已经是字典类型，直接使用
            elif arguments is None:
                arguments = {}
            self.logger.bind(tag=TAG).info(f"调用函数: {function_name}, 参数: {arguments}")
            if funcItem.type == ToolType.SYSTEM_CTL or funcItem.type == ToolType.IOT_CTL:
                return func(self.context, **arguments)
            elif funcItem.type == ToolType.WAIT:
                return func(**arguments)
            elif funcItem.type == ToolType.CHANGE_SYS_PROMPT:
                return func(self.context, **arguments)
            else:
                return ActionResponse(action=Action.NOTFOUND, result="没有找到对应的函数", response="")
        except Exception as e:
            self.logger.bind(tag=TAG).error(f"处理function call错误: {e}")
            # 返回错误信息而不是None，让流程继续执行
            return ActionResponse(
                action=Action.REQLLM,
                result=f"函数调用失败: {e}",
                response="抱歉，执行时出现错误，请重新尝试。",
            )

    def get_current_function_tools_with_names(self):
        func_names = []
        for func in self.functions_desc:
            func_name = func["function"]["name"]
            # 获取对应的FunctionItem来检查类型
            function_item = self.function_registry.get_function(func_name)
            # 排除MCP工具的函数
            if function_item and function_item.type != ToolType.MCP_CLIENT:
                func_names.append(func_name)
        return func_names

    def get_current_function_tools_with_details(self):
        func_details = []
        for func_name in self.get_current_function_tools_with_names():
            if func_desc := self.function_registry.get_function_desc(func_name):
                func_schema = func_desc["function"]
                func_name = func_schema.get("name", "")
                func_description = func_schema.get("description", {})
                func_parameters = func_schema.get("parameters", {})
                func_parameters_type = func_parameters.get("type", "")
                func_parameters_properties = func_parameters.get("properties", {})
                func_parameters_required = func_parameters.get("required", [])
                properties_names = list(func_parameters_properties.keys())
                properties_infos = list(func_parameters_properties.values())

                func_details.append(
                    {
                        "name": func_name,
                        "description": func_description,
                        "parameters": func_parameters,
                        "parameters_type": func_parameters_type,
                        "parameters_properties": func_parameters_properties,
                        "parameters_required": func_parameters_required,
                        "properties_names": properties_names,
                        "properties_infos": properties_infos,
                    }
                )

        return func_details
