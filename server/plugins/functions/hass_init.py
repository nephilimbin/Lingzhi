from typing import TYPE_CHECKING

from config.logger import setup_logging
from core.utils.util import check_model_key

if TYPE_CHECKING:
    from core.session.session_context import SessionContext

TAG = __name__
logger = setup_logging()

HASS_CACHE = {}


def append_devices_to_prompt(context: "SessionContext"):
    if context.session_runtime_config.session_function_config.use_function_call_mode:
        funcs = context.config["Intent"]["function_call"].get("functions", [])
        if "hass_get_state" in funcs or "hass_set_state" in funcs:
            prompt = "下面是我家智能设备，可以通过homeassistant控制\n"
            devices = context.config["function_plugins"]["home_assistant"].get("devices", [])
            if len(devices) == 0:
                return
            for device in devices:
                prompt += device + "\n"
            context.prompt += prompt
            # 更新提示词
            context.session_dialogue.set_system_prompt(context.prompt)


def initialize_hass_handler(context: "SessionContext"):
    global HASS_CACHE
    if HASS_CACHE == {}:
        if context.session_runtime_config.session_function_config.use_function_call_mode:
            funcs = context.config["Intent"]["function_call"].get("functions", [])
            if "hass_get_state" in funcs or "hass_set_state" in funcs:
                HASS_CACHE["base_url"] = context.config["function_plugins"]["home_assistant"].get("base_url")
                HASS_CACHE["api_key"] = context.config["function_plugins"]["home_assistant"].get("api_key")

                check_model_key("home_assistant", HASS_CACHE["api_key"])
    return HASS_CACHE
