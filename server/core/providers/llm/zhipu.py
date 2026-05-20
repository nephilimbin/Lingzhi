import traceback
from typing import List

from config.logger import setup_logging
from core.providers.llm.base import LLMProviderBase, LLMResponseInfo
import zai
from zai import ZhipuAiClient

TAG = __name__
logger = setup_logging()


class LLMProvider(LLMProviderBase):
    def __init__(self, config):
        super().__init__(config)
        self.client = ZhipuAiClient(api_key=self.api_key)
        if hasattr(self, "model_name") and self.model_name is None:
            self.model_name = "glm-4.5-flash"
        if hasattr(self, "temperature") and self.temperature is None:
            self.temperature = 0.2  # 控制输出的随机性, 不与top_k共同使用
        if hasattr(self, "max_output_tokens") and self.max_output_tokens is None:
            self.max_output_tokens = 4096  # 最大输出tokens
        if hasattr(self, "thinking_mode") and self.thinking_mode is None:
            self.thinking_mode = "disabled"  # 启用思考过程
        if hasattr(self, "stream_mode") and self.stream_mode is None:
            self.stream_mode = False

    def response(self, dialogue: List, stream_mode=False, **kwargs):
        # 验证对话格式
        dialogue = self.validate_dialogue_format(dialogue)
        # 验证是否支持流式输出
        if not self.is_support_stream_mode():
            logger.bind(tag=TAG).info("不支持流式输出")
            stream_mode = False
        try:
            response = self.client.chat.completions.create(
                model=self.model_name,
                messages=[dialogue for dialogue in dialogue],
                thinking={"type": f"{self.thinking_mode}"},
                stream=stream_mode,  # 启用流式输出
                max_tokens=self.max_output_tokens,
                temperature=self.temperature,
                **kwargs,
            )

            # 根据是否启用流式输出，返回不同的响应
            if not stream_mode:
                # 非流式获取回复:Completion(model='glm-4.5-flash', created=1762925464, choices=[CompletionChoice(index=0, finish_reason='stop', message=CompletionMessage(content='故宫、长城、天坛、颐和园、798艺术区。', role='assistant', reasoning_content=None, tool_calls=None))], request_id='20251112133103e65716e079c049c2', id='20251112133103e65716e079c049c2', usage=CompletionUsage(prompt_tokens=29, prompt_tokens_details=PromptTokensDetails(cached_tokens=28), completion_tokens=17, completion_tokens_details=None, total_tokens=46))

                yield LLMResponseInfo(
                    model_name=self.model_name,
                    content=response.choices[0].message.content,
                    total_token_count=response.usage.total_tokens,
                    prompt_token_count=response.usage.prompt_tokens,
                    candidates_token_count=response.usage.completion_tokens,
                    is_response_end=True,
                    is_stream_mode=False,
                )
            else:
                # 流式获取回复: ChatCompletionChunk(id='20251123100155b7ada9d0a4a2454e', choices=[Choice(delta=ChoiceDelta(content='。', role='assistant', reasoning_content=None, tool_calls=None, audio=None), finish_reason=None, index=0)], created=1763863315, model='glm-4.5', usage=None, extra_json=None)
                # 流式结束回复：ChatCompletionChunk(id='20251123100155b7ada9d0a4a2454e', choices=[Choice(delta=ChoiceDelta(content='', role='assistant', reasoning_content=None, tool_calls=None, audio=None), finish_reason='stop', index=0)], created=1763863315, model='glm-4.5', usage=CompletionUsage(prompt_tokens=1502, prompt_tokens_details=PromptTokensDetails(cached_tokens=1390), completion_tokens=21, completion_tokens_details=None, total_tokens=1523), extra_json=None)
                for chunk in response:
                    if not chunk.choices:
                        continue
                    if hasattr(chunk.choices[0].delta, "content"):
                        yield LLMResponseInfo(
                            model_name=chunk.model,
                            content=chunk.choices[0].delta.content,
                            is_response_end=False,
                            is_stream_mode=True,
                        )
                    if hasattr(chunk.choices[0], "finish_reason") and chunk.choices[0].finish_reason == "stop":
                        # logger.bind(tag=TAG).debug("流式回复结束")
                        yield LLMResponseInfo(
                            model_name=chunk.model,
                            content=chunk.choices[0].delta.content,
                            total_token_count=chunk.usage.total_tokens,
                            prompt_token_count=chunk.usage.prompt_tokens,
                            candidates_token_count=chunk.usage.completion_tokens,
                            is_response_end=True,
                            is_stream_mode=True,
                        )

        except zai.core.APIStatusError as err:
            logger.bind(tag=TAG).error(f"API 状态错误: {err}, 追踪: {traceback.format_exc()}")
        except zai.core.APITimeoutError as err:
            logger.bind(tag=TAG).error(f"请求超时: {err}, 追踪: {traceback.format_exc()}")
        except Exception as err:
            logger.bind(tag=TAG).error(f"其他错误: {err}, 追踪: {traceback.format_exc()}")
            raise

    def is_support_stream_mode(self) -> bool:
        return self.stream_mode

    def validate_dialogue_format(self, dialogues: List) -> List:
        # 过滤掉每个遍历的字典中role不是system、user、assistant和tool的项
        return [dialogue for dialogue in dialogues if dialogue.get("role") in ["system", "user", "assistant", "tool"]]

    def get_models_list(self) -> list:
        # 价格地址:https://bigmodel.cn/pricing
        models = [
            {
                "model_name": "glm-4.6",
                "thinking_mode": "enabled",
                "max_output_tokens": 200000,
                "max_context_tokens": 200000,
                "max_input_million_tokens_price": 3,
                "max_output_million_tokens_price": 14,
                "max_cache_million_tokens_price": 0.6,
            },
            {
                "model_name": "glm-4.5",
                "thinking_mode": "enabled",
                "max_output_tokens": 128000,
                "max_context_tokens": 128000,
                "max_input_million_tokens_price": 3,
                "max_output_million_tokens_price": 14,
                "max_cache_million_tokens_price": 0.6,
            },
            {
                "model_name": "glm-4.5-x",
                "thinking_mode": "enabled",
                "max_output_tokens": 128000,
                "max_context_tokens": 128000,
                "max_input_million_tokens_price": 12,
                "max_output_million_tokens_price": 32,
                "max_cache_million_tokens_price": 2.4,
            },
            {
                "model_name": "glm-4.5-air",
                "thinking_mode": "enabled",
                "max_output_tokens": 128000,
                "max_context_tokens": 128000,
                "max_input_million_tokens_price": 0.8,
                "max_output_million_tokens_price": 6,
                "max_cache_million_tokens_price": 0.16,
            },
            {
                "model_name": "glm-4.5-airx",
                "thinking_mode": "enabled",
                "max_output_tokens": 128000,
                "max_context_tokens": 128000,
                "max_input_million_tokens_price": 4,
                "max_output_million_tokens_price": 16,
                "max_cache_million_tokens_price": 0.8,
            },
            {
                "model_name": "glm-4.5-flash",
                "thinking_mode": "enabled",
                "max_output_tokens": 128000,
                "max_context_tokens": 128000,
                "max_input_million_tokens_price": 0,
                "max_output_million_tokens_price": 0,
                "max_cache_million_tokens_price": 0,
            },
            {
                "model_name": "glm-4-plus",
                "thinking_mode": "disabled",
                "max_output_tokens": 128000,
                "max_context_tokens": 128000,
                "max_input_million_tokens_price": 5,
                "max_output_million_tokens_price": 5,
                "max_cache_million_tokens_price": 0,
            },
            {
                "model_name": "glm-4-air",
                "thinking_mode": "disabled",
                "max_output_tokens": 128000,
                "max_context_tokens": 128000,
                "max_input_million_tokens_price": 0.5,
                "max_output_million_tokens_price": 0.5,
                "max_cache_million_tokens_price": 0,
            },
            {
                "model_name": "glm-4-airx",
                "thinking_mode": "disabled",
                "max_output_tokens": 8000,
                "max_context_tokens": 8000,
                "max_input_million_tokens_price": 10,
                "max_output_million_tokens_price": 10,
                "max_cache_million_tokens_price": 0,
            },
            {
                "model_name": "glm-4-flashx-250414",
                "thinking_mode": "disabled",
                "max_output_tokens": 128000,
                "max_context_tokens": 128000,
                "max_input_million_tokens_price": 0.1,
                "max_output_million_tokens_price": 0.1,
                "max_cache_million_tokens_price": 0,
            },
            {
                "model_name": "glm-4-long",
                "thinking_mode": "disabled",
                "max_output_tokens": 1000000,
                "max_context_tokens": 1000000,
                "max_input_million_tokens_price": 1,
                "max_output_million_tokens_price": 1,
                "max_cache_million_tokens_price": 0,
            },
            {
                "model_name": "glm-4-assistant",
                "thinking_mode": "disabled",
                "max_output_tokens": 128000,
                "max_context_tokens": 128000,
                "max_input_million_tokens_price": 5,
                "max_output_million_tokens_price": 5,
                "max_cache_million_tokens_price": 0,
            },
        ]
        return models
