"""
统一状态管理器 - 合并 SessionState 和 StateManager
提供完美的类型推断和零维护成本的状态管理解决方案
"""

from collections import deque
import queue
import threading
from typing import TYPE_CHECKING, Any, Dict, List, Optional

from config.logger import setup_logging
from core.models.message_models import ChatMode, ChatModeType

if TYPE_CHECKING:
    from core.session.session_context import SessionContext

TAG = __name__


class StateManager:
    """
    统一状态管理器

    直接管理状态数据和业务逻辑操作，提供：
    - 完美的类型推断（IDE 可准确推断所有属性类型）
    - 零维护成本（新增状态只需在 __init__ 中添加属性）
    - 高性能（直接属性访问，无代理开销）
    - 完整的状态操作方法（批量更新、清理等）

    所有状态属性直接在实例上定义，类型明确，IDE 友好。
    """

    def __init__(self, context: "SessionContext") -> None:
        """初始化状态管理器"""
        # 上下文相关
        self.context = context
        self.event_bus = context.event_bus
        self.logger = setup_logging()
        self.lock = threading.Lock()

        # === 基础信息 ===
        self.session_id: str = context.session_id

        # === 客户端运行时状态 ===
        self.client_listen_mode: Optional[str] = "auto"  # auto, manual
        self.current_session_request_id: Optional[str] = None  # 当前会话请求ID
        self.client_have_voice: bool = False  # 用于标记用户是否正在说话
        self.client_first_have_voice: bool = False  # 用于标记是否第一次有声音
        self.client_have_voice_last_time: float = 0.0  # 用于标记用户最后一次有声时间
        self.client_no_voice_last_time: float = 0.0  # 用于标记用户最后一次无声时间
        self.client_voice_stop: bool = False  # 用于标记用户是否停止说话
        self.client_voice_frame_count: int = 0  # 用于标记用户说话的帧数

        # === 聊天模式 ===
        self.chat_mode: Optional[ChatModeType] = ChatMode.USUAL_MODE

        # === ASR运行时状态 ===
        self.asr_vad_buffer: bytearray = bytearray()  # 用于储存ASR VAD缓冲区
        self.asr_audio_queue: deque = deque()  # 用于存储ASR音频数据
        self.asr_transcript_text: List[Dict[str, Any]] = []  # 用于存储ASR转录数据
        self.asr_processing_triggered: bool = False  # 用于标记ASR处理是否已被触发，防止重复调用

        # === 接收的输入音频流参数 ===
        self.input_audio_format: str = ""  # 用于标记输入音频格式
        self.input_audio_sample_rate: int = 16000
        self.input_audio_channels: int = 1
        self.input_audio_frame_duration: int = 60
        self.input_audio_has_started: bool = False  # 用于标记是否接收到音频数据，用于ASR判断是否解析数据
        self.input_audio_transport_type: Optional[str] = None

        # === LLM运行时状态 ===
        self.llm_finish_task: bool = False  # 用于标记LLM是否完成任务
        self.llm_first_text_index: int = -1  # 用于标记LLM第一个文本的索引
        self.llm_last_text_index: int = -1  # 用于标记LLM最后一个文本的索引

        # === 会话控制运行时状态 ===
        self.close_after_chat: bool = False  # 用于标记是否在对话结束后关闭会话

        # === tts状态 ===
        self.webrtc_tts_audio_output_queue: queue.Queue = queue.Queue()
        self.audio_tts_queue: queue.Queue = queue.Queue()  # 用于存储TTS输出数据
        self.audio_play_queue: queue.Queue = queue.Queue()  # 用于存储音频播放数据
        self.tts_tasks_stop: bool = False  # 用于标记TTS任务是否停止

        # === vlm状态===
        self.webrtc_vlm_video_queue: queue.Queue = queue.Queue()

    # ==================== 批量状态操作方法 ====================
    def update_current_session_request_id(self, id: str) -> None:
        """更新请求ID"""
        self.current_session_request_id = id
        self.context.intent_processor.session_request_id = id
        self.context.chat_processor.session_request_id = id
        self.context.tts_pipeline.session_request_id = id
        self.context.exit_processor.session_request_id = id
        self.context.output_processor.session_request_id = id
        self.context.wakeup_processor.session_request_id = id
        self.context.event_dispatcher.text_read_handler.session_request_id = id
        self.context.event_dispatcher.audio_bytes_parse_handler.session_request_id = id
        self.context.event_dispatcher.audio_listen_handler.session_request_id = id
        self.context.event_dispatcher.client_abort_handler.session_request_id = id
        self.context.event_dispatcher.client_handshake_handler.session_request_id = id
        self.context.event_dispatcher.client_mute_handler.session_request_id = id

    def update_state(self, **updates: Any) -> None:
        """
        批量更新状态
        :params: **updates: 要更新的状态键值对
        """
        # 可选：记录状态变更历史
        with self.lock:
            old_values = {}
            for key, value in updates.items():
                if hasattr(self, key) and not key.startswith("_"):
                    old_values[key] = getattr(self, key)
                    setattr(self, key, value)
                else:
                    self.logger.bind(tag=TAG).warning(f"尝试更新不存在的状态字段: {key}")
        # 调试时可以取消注释使用
        # if old_values:
        #     self.logger.bind(tag=TAG).debug(f"更新会话状态: 变更前: {old_values}, 变更后: {updates}")

    # ==================== ASR音频操作方法 ====================

    def append_asr_audio(self, audio_data: bytes) -> None:
        """向ASR音频列表添加数据"""
        self.asr_audio_queue.append(audio_data)

    def keep_latest_asr_audio(self, count: int) -> None:
        """保留最新的ASR音频数据"""
        if len(self.asr_audio_queue) > count:
            self.asr_audio_queue = deque(list(self.asr_audio_queue)[-count:])

    def reset_asr_task_states(self) -> None:
        """重置用户输入声音状态"""
        self.update_state(
            client_have_voice=False,
            client_voice_stop=False,
            client_have_voice_last_time=0,
            client_voice_frame_count=0,
            client_first_have_voice=False,
            asr_processing_triggered=False,
        )
        self.asr_vad_buffer.clear()
        self.asr_transcript_text.clear()
        self.asr_audio_queue.clear()

    def restart_auto_mode_asr_task_states(self) -> None:
        """
        重启自动ASR模式下的任务状态
        """
        self.update_state(
            client_have_voice=True,
            client_voice_stop=False,
            client_have_voice_last_time=0.0,
            asr_processing_triggered=False,
        )

    # ==================== LLM状态操作方法 ====================

    def record_llm_text_index(self, text_index: int = 0) -> None:
        """记录第一个和最后一个文本的索引"""
        if self.llm_first_text_index == -1:
            self.llm_first_text_index = text_index
        self.llm_last_text_index = text_index

    def reset_llm_task_states(self) -> None:
        """清除LLM状态"""
        self.update_state(llm_finish_task=False)
        self.update_state(llm_last_text_index=-1, llm_first_text_index=-1)

    # ==================== 会话状态管理方法 ====================

    def clear_session_state(self) -> None:
        """清理会话的所有状态"""
        try:
            # 清理ASR相关状态
            self.asr_audio_queue.clear()
            self.asr_transcript_text.clear()
            self.asr_vad_buffer.clear()

            # 重置客户端状态
            self.update_state(
                current_session_request_id=None,
                client_have_voice=False,
                client_have_voice_last_time=0.0,
                client_no_voice_last_time=0.0,
                client_voice_stop=False,
                client_voice_frame_count=0,
                client_first_have_voice=False,
            )

            # 重置LLM状态
            self.reset_llm_task_states()

            # 重置会话控制状态
            self.update_state(close_after_chat=False)

            self.logger.bind(tag=TAG).info(f"会话状态已清理: {self.session_id}")

        except Exception as e:
            self.logger.bind(tag=TAG).error(f"清理会话状态时出错: {self.session_id}, error={e}")

    # ==================== TTS摸跨状态管理方法 ====================

    def clear_webrtc_tts_output_queue(self) -> None:
        """重置tts的webrtc输出队列（同步方法，线程安全）"""
        while not self.webrtc_tts_audio_output_queue.empty():
            try:
                self.webrtc_tts_audio_output_queue.get_nowait()
            except queue.Empty:
                break
        self.logger.bind(tag=TAG).info("重置tts的webrtc输出队列")
