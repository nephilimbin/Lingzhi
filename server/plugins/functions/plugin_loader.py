from config.logger import setup_logging
from core.models import Action, ActionResponse, ToolType
from core.registries import register_function

TAG = __name__
logger = setup_logging()

plugin_loader_function_desc = {
    "type": "function",
    "function": {
        "name": "plugin_loader",
        "description": "当用户想加载或卸载插件/function时，调用此函数：支持的插件列表为[plugins]",
        "parameters": {
            "type": "object",
            "properties": {
                "oper": {"type": "string", "description": "load or unload"},
                "name": {"type": "string", "description": "要加载或卸载的插件名字"},
            },
            "required": ["oper", "name"],
        },
    },
}


@register_function("plugin_loader", plugin_loader_function_desc, ToolType.SYSTEM_CTL)
def plugin_loader(context, oper: str, name: str):
    """插件加载"""
    if oper not in ["load", "unload"]:
        return ActionResponse(action=Action.RESPONSE, result="插件操作失败", response="不支持的操作")

    cur_support = context.function_intent_manager.current_support_functions()
    if oper == "load":
        if name in cur_support:
            return ActionResponse(
                action=Action.RESPONSE,
                result="插件加载失败",
                response=f"{name}插件已加载,无需重复加载",
            )
        func = context.function_intent_manager.function_registry.register_function(name)
        if not func:
            return ActionResponse(action=Action.RESPONSE, result="插件加载失败", response="插件未找到")
        res = f"{name}插件加载成功"
    else:
        if name not in cur_support:
            return ActionResponse(
                action=Action.RESPONSE,
                result="插件卸载失败",
                response=f"{name}插件未加载",
            )
        bOK = context.function_intent_manager.function_registry.unregister_function(name)
        if not bOK:
            return ActionResponse(action=Action.RESPONSE, result="插件卸载失败", response="插件未找到")
        res = f"{name}插件卸载成功"
    context.function_intent_manager.upload_functions_desc()
    return ActionResponse(action=Action.RESPONSE, result="插件操作成功", response=res)
