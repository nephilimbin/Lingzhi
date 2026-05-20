import asyncio
import traceback
from typing import TYPE_CHECKING, Generator

from core.models import Action
from core.providers.llm.base import LLMResponseInfo
from core.utils.markdown_formatter import MarkdownFormatter

if TYPE_CHECKING:
    import traceback

    from core.session.session_context import SessionContext


TAG = __name__


class ChatProcessor:
    """对话管理器 - 负责处理LLM对话和函数调用相关逻辑

    该处理器是AI助手系统的对话核心组件，专门处理用户与LLM的交互流程。
    支持流式和非流式两种LLM响应模式，并提供完整的对话状态管理。

    主要职责：
    1. 处理用户输入的意图识别和分发
    2. 管理LLM对话流程，包括流式和非流式响应
    3. 协调TTS（文本转语音）处理的分段和分发
    4. 维护对话历史和会话状态
    5. 处理任务取消和异常情况

    处理流程：
    用户输入 → 意图处理 → LLM调用 → 响应分段 → TTS分发 → 状态更新

    与其他组件的关系：
    - IntentProcessor: 处理用户意图识别和函数调用
    - SessionDialogue: 管理对话历史和上下文
    - OutputProcessor: 处理响应输出和流式传输
    - TtsPipeline: 管理TTS任务队列和处理
    - StateManager: 维护会话状态和任务管理
    - CancellationManager: 处理任务取消逻辑

    设计模式：
    - 策略模式：根据LLM支持情况选择流式或非流式处理
    - 观察者模式：监听任务取消事件
    - 状态模式：管理对话处理的不同状态
    """

    def __init__(self, context: "SessionContext"):
        """
        初始化对话处理器。
        :param context: 会话上下文对象
        """
        self.context = context
        self.logger = context.logger
        # 定义文本分段标点符号，用于TTS处理的分段逻辑
        self.segment_punctuation = ("。", "？", "！", "；", ".")
        # 初始化会话请求ID，用于追踪当前对话处理链路
        self.session_request_id = ""

    async def process_client_chat(self, text: str, source: str = "text", session_request_id: str = None):
        """
        处理用户输入并启动对话流程。
        :param text: 用户输入文本
        :param source: 输入来源标识 ("audio", "text", "timeout"等)
        :param session_request_id: 会话请求ID
        """

        # 记录用户输入处理开始的调试信息
        self.logger.bind(tag=TAG).debug(f"开始处理用户意图来源 {source}: '{text}'")
        # 设置会话请求ID用于追踪当前操作链路
        self.session_request_id = session_request_id

        try:
            # 执行意图识别和处理流程（包含用户消息记录和函数调用处理）
            intent_result = await self.context.intent_processor.handle_client_intent(text)

            # 解析处理结果，提取动作类型和错误信息
            if hasattr(intent_result, "action"):
                action = intent_result.action
                error_msg = intent_result.result if action == Action.ERROR else None
            else:
                action = intent_result
                error_msg = None

            # 根据不同的Action类型执行相应的处理逻辑
            match action:
                case Action.REQLLM:
                    # 需要LLM进行常规对话处理
                    await self._request_llm_response(None)
                case Action.RESPONSE:
                    # 直接响应，无需进一步处理
                    return
                case Action.NOTFOUND:
                    # 资源未找到，降级为LLM对话处理
                    await self._request_llm_response(None)
                case Action.NONE:
                    # 无需任何操作，直接返回
                    return
                case Action.ERROR:
                    # 发生错误，将错误信息传递给LLM处理
                    await self._request_llm_response(error_msg)

        except Exception:
            self.logger.bind(tag=TAG).error(
                f"处理用户意图时出错：'{text}': {traceback.format_exc()}",
            )
            raise

    async def _request_llm_response(self, query):
        """
        处理不同类型的对话。
        :param query: 查询内容，可能为None
        """

        try:
            # 获取当前异步任务并注册为可取消任务
            current_task = asyncio.current_task()
            if self.context.cancellation_manager and current_task:
                await self.context.cancellation_manager.register_task(
                    session_id=self.context.session_id,
                    task=current_task,
                    task_type=self.context.cancellation_manager.task_types.TEXT_READ_TASK,
                )

            # 检查任务是否已被外部取消
            if current_task and current_task.cancelled():
                self.logger.bind(tag=TAG).info("LLM处理任务已被取消")
                return False

            # 如果有查询内容且会话ID有效，记录用户消息到对话历史
            # TODO: 用户对话逻辑需要整合到统一的对话管理流程中
            if query and self.session_request_id is not None:
                self.context.session_dialogue.add_user_message(query, session_request_id=self.session_request_id)

            try:
                # 获取优化后的对话历史，包含记忆模式管理
                # TODO: 需要重新设计记忆模式的交互逻辑，提高上下文管理效率
                optimized_dialogue = self.context.session_dialogue.get_llm_dialogue()

                # 记录对话统计信息，用于调试和性能监控
                dialogue_stats = self.context.session_dialogue.get_dialogue_stats()
                self.logger.bind(tag=TAG).info(
                    f"对话统计 - 总消息数: {dialogue_stats['total_messages']}, 上下文限制: {dialogue_stats['dialogue_context_num']}, 实际发送给LLM: {len(optimized_dialogue)}条消息"
                )
                # 具体的对话历史
                # self.logger.bind(tag=TAG).info(f"对话历史: {optimized_dialogue}")

                # 检测LLM提供商是否支持流式响应模式
                is_stream_supported = self.context.llm.is_support_stream_mode()
                if is_stream_supported:
                    # 流式模式：实时响应，提升用户体验
                    llm_responses = self.context.llm.chat_completion(optimized_dialogue, stream_mode=True)
                    final_response_info, processed_chars, text_index = await self._process_stream_llm_response(
                        llm_responses, current_task
                    )
                else:
                    # 非流式模式：等待完整响应后一次性处理
                    llm_responses = self.context.llm.chat_completion(optimized_dialogue)
                    final_response_info, processed_chars, text_index = await self._process_non_stream_llm_response(
                        llm_responses, current_task
                    )

            except Exception as e:
                # LLM处理异常：记录错误详情并向用户发送友好的错误提示
                self.logger.bind(tag=TAG).error(f"LLM 处理出错: {e}, 追踪: {traceback.format_exc()}")
                error_message = "模型处理出错，请稍后重试。问题为：" + str(e)
                await self.context.output_processor.send_error_message(
                    error_message,
                    self.session_request_id,
                )
                # 更新LLM处理状态为未完成
                self.context.state_manager.update_state(llm_finish_task=False)
                return

            # 提取完整的LLM响应内容，用于后续处理和记录
            full_response_content = final_response_info.content if final_response_info else ""

            # 处理响应中的剩余文本，确保所有内容都被TTS系统处理
            if full_response_content and hasattr(self, "_process_remaining_text"):
                self._process_remaining_text(full_response_content, processed_chars, text_index)

                # 记录助手回复到对话历史，包含完整的响应信息和元数据
                self.context.session_dialogue.add_assistant_message(
                    content=full_response_content,
                    llm_response_info=final_response_info,
                    session_request_id=self.session_request_id,
                )
                # 记录完整响应内容，用于调试和日志追踪
                self.logger.bind(tag=TAG).info(f"LLM返回完整对话内容: {full_response_content}")

        except asyncio.CancelledError:
            # 任务被取消：记录取消事件，可能是用户中断或系统调度
            self.logger.bind(tag=TAG).info("LLM对话处理任务被事件驱动中断")
        except Exception as e:
            # 其他异常：记录详细错误信息用于问题诊断
            self.logger.bind(tag=TAG).error(f"对话处理错误: {e}, {traceback.format_exc()}")
        finally:
            # 最终清理：确保LLM任务状态被正确标记为已结束
            self.context.state_manager.update_state(llm_finish_task=True)

    async def _process_stream_llm_response(
        self, llm_responses: Generator[LLMResponseInfo, None, None], current_task: asyncio.Task
    ):
        """
        处理流式LLM响应 - 优化后使用单一LLMResponseInfo对象。
        :param llm_responses: 流式LLM响应生成器
        :param current_task: 当前任务对象，用于取消检查
        :return: (final_response_info, processed_chars, text_index)
        """
        text_index = 0
        final_response_content = ""
        is_first_response = True
        processed_chars = 0
        last_sent_length = 0  # 记录上次发送内容的长度，确保单调递增

        try:
            self.logger.bind(tag=TAG).info("开始处理流式LLM响应")

            for response_info in llm_responses:
                # 检查任务是否已被取消
                if current_task and current_task.cancelled():
                    self.logger.bind(tag=TAG).warning("LLM流式响应处理任务已被取消")
                    break

                # 累积内容到final_response_info.content
                final_response_content += response_info.content
                is_response_end = response_info.is_response_end

                # 发送累积内容
                current_length = len(final_response_content)
                if current_length > last_sent_length:
                    await self.context.output_processor.send_llm_stream_response_message(
                        final_response_content, is_first_response, self.session_request_id
                    )
                    last_sent_length = current_length

                    if is_first_response:
                        is_first_response = False

                # 统一TTS处理（传入累积的内容）
                text_index, processed_chars = self._handle_tts_processing(
                    final_response_content, processed_chars, text_index, is_response_end
                )

                # 最后文本结果赋值
                response_info.content = final_response_content

            return response_info, processed_chars, text_index
        except Exception as e:
            self.logger.bind(tag=TAG).error(f"流式处理异常: {traceback.format_exc()}")
            raise e

    async def _process_non_stream_llm_response(
        self, llm_responses: Generator[LLMResponseInfo, None, None], current_task: asyncio.Task
    ):
        """
        处理非流式LLM响应 - 优化后使用单一LLMResponseInfo对象。
        :param llm_responses: 非流式LLM响应生成器
        :param current_task: 当前任务对象，用于取消检查
        :return: (final_response_info, processed_chars, text_index)
        """
        text_index = 0
        processed_chars = 0
        is_first_response = True

        try:
            self.logger.bind(tag=TAG).info("开始处理非流式LLM响应")

            # 检查任务是否已被取消
            if current_task and current_task.cancelled():
                self.logger.bind(tag=TAG).warning("LLM非流式响应处理任务已被取消")
                return

            # 获取单一响应
            response_info = next(llm_responses)

            # 非流式模式下，content已经是完整的响应内容，直接使用
            response_message = response_info.content

            # 发送响应消息
            await self.context.output_processor.send_llm_stream_response_message(
                response_message, is_first_response, self.session_request_id
            )

            # 统一TTS处理
            text_index, processed_chars = self._handle_tts_processing([response_message], processed_chars, text_index)

            return response_info, processed_chars, text_index

        except Exception as e:
            self.logger.bind(tag=TAG).error(f"非流式处理异常: {traceback.format_exc()}")
            raise e

    def _process_remaining_text(self, response_message, processed_chars, text_index):
        """
        处理剩余文本。
        :param response_message: 响应消息内容
        :param processed_chars: 已处理的字符数
        :param text_index: 当前文本索引
        """
        try:
            full_text = "".join(response_message) if isinstance(response_message, list) else response_message
            remaining_text = full_text[processed_chars:]

            if not remaining_text.strip():
                self.logger.bind(tag=TAG).info("CHAT没有剩余文本需要TTS处理")
                self._dispatch_tts_for_segment("", text_index, True)
                return

            # markdown格式清理
            segment_text = MarkdownFormatter.clean_markdown(remaining_text)
            if segment_text and len(segment_text.strip()) >= 0:
                text_index += 1
                self.logger.bind(tag=TAG).info(f"CHAT处理最终剩余文本段 [{text_index}]: '{segment_text}'")
                self._dispatch_tts_for_segment(segment_text, text_index, True)
        except Exception as e:
            self.logger.bind(tag=TAG).error(f"处理剩余文本异常: {traceback.format_exc()}")
            raise e

    def _find_segment_position(self, text: str) -> int:
        """
        智能查找文本中分隔符的位置，避免数字列表误判。
        :param text: 待处理的文本
        :return: 分隔符位置，如果没有找到返回-1
        """
        # 定义文本分隔符集合，按优先级排序
        separators = ("\n", "。", "？", "！", "；", ".")

        for i, char in enumerate(text):
            if char in separators:
                # 特殊处理：避免将数字列表编号后的点号误认为句子结束
                if char == "." and i > 0:
                    prev_char = text[i - 1]
                    if prev_char.isdigit():
                        # 进一步检查：确保不是小数点（如"3.14"）
                        # 只有当点号前是单个数字且前面没有其他数字时，才判断为列表编号
                        if i == 1 or not text[i - 2].isdigit():
                            continue  # 跳过数字列表编号（如"1."、"2."等）
                return i
        return -1

    def _extract_text_segment(self, text, processed_chars: int = 0) -> tuple[str, str, int]:
        """
        提取文本段落并清理格式。
        :param text: 文本内容（可能是list或string）
        :param processed_chars: 已处理的字符位置
        :return: (segment_text_raw, segment_text_clean, new_processed_chars)
        """
        # 统一文本格式：将列表形式的文本合并为字符串
        full_text = "".join(text) if isinstance(text, list) else text
        # 获取待处理的文本部分（从已处理位置开始）
        current_text = full_text[processed_chars:]

        # 如果剩余文本为空或只有空白字符，直接返回
        if not current_text.strip():
            return "", "", processed_chars

        # 在当前文本中查找第一个合适的分隔符位置
        first_punct_pos = self._find_segment_position(current_text)

        if first_punct_pos != -1:
            # 提取完整的文本段落（包含分隔符，确保语义完整）
            segment_text_raw = current_text[: first_punct_pos + 1]
            # 清理Markdown标记，保留纯文本内容和标点符号
            segment_text_clean = MarkdownFormatter.clean_markdown(segment_text_raw)
            # 更新已处理字符位置
            new_processed_chars = processed_chars + len(segment_text_raw)
            return segment_text_raw, segment_text_clean, new_processed_chars

        # 没有找到合适的分隔符，返回空结果
        return "", "", processed_chars

    def _handle_tts_processing(self, response_buffer, processed_chars, text_index, is_response_end):
        """
        统一的TTS处理逻辑，供流式和非流式处理共用。
        :param response_buffer: 响应内容缓冲区
        :param processed_chars: 已处理字符数
        :param text_index: 当前文本索引
        :param is_response_end: 是否是最终的响应
        :return: (new_text_index, new_processed_chars)
        """
        _, segment_text, processed_chars = self._extract_text_segment(response_buffer, processed_chars)

        if segment_text:
            text_index += 1
            self._dispatch_tts_for_segment(segment_text, text_index, is_response_end)

        return text_index, processed_chars

    def _dispatch_tts_for_segment(self, segment_text: str, text_index: int, is_response_end: bool) -> None:
        """
        为文本段落分发TTS任务 - 统一TTS分发逻辑。
        :param segment_text: 文本段落内容
        :param text_index: 文本索引
        """
        try:
            # 记录文本段落索引到状态管理器，用于追踪TTS处理进度
            self.context.state_manager.record_llm_text_index(text_index)

            # 构造TTS任务参数并发送到音频处理管道
            segment_tts_text = segment_text, text_index, is_response_end

            # 将TTS任务加入处理队列（线程安全，同步操作）
            self.context.state_manager.audio_tts_queue.put(segment_tts_text)

        except Exception as e:
            # TTS任务分发异常：记录错误详情，避免影响主对话流程
            self.logger.bind(tag=TAG).error(f"错误分发TTS任务: {text_index}: {e}, 追踪: {traceback.format_exc()}")
