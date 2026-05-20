"""
事件类型定义 - 集中管理所有事件类型
"""


class EventTypes:
    """事件类型定义 - 集中管理所有事件类型"""

    # 会话事件
    CLIENT_CONNECTED = "session.client_connected"
    CLIENT_DISCONNECTED = "session.client_disconnected"
    CLIENT_HANDSHAKE_REQUESTED = "session.client_handshake_requested"  # 客户端请求握手
    CLIENT_ABORT_REQUESTED = "session.client_abort_requested"  # 客户端请求中断（状态变更）
    CLIENT_MUTE_REQUESTED = "session.client_mute_requested"  # 客户端请求静音
    SESSION_TASKS_CANCEL_REQUESTED = "session.tasks_cancel_requested"  # 请求取消会话任务

    # 连接事件
    CONNECTION_STATE_CHANGED = "connection.state_changed"  # 连接状态变更
    CONNECTION_LOST = "connection.lost"  # 连接丢失
    CONNECTION_ESTABLISHED = "connection.established"  # 连接建立
    CONNECTION_ERROR = "connection.error"  # 连接错误
    WEBSOCKET_DISCONNECTED = "websocket.disconnected"  # WebSocket断开连接

    # 消息事件
    AUDIO_LISTEN_REQUESTED = "message.audio_listen_requested"
    AUDIO_BYTES_PARSE_REQUESTED = "message.audio_bytes_parse_requested"
    TEXT_READ_REQUESTED = "message.text_read_requested"

    # 状态变更事件
    CLIENT_STATE_CHANGED = "state.client_changed"
    ASR_STATE_CHANGED = "state.asr_changed"
    LLM_STATE_CHANGED = "state.llm_changed"
    TTS_STATE_CHANGED = "state.tts_changed"
    VAD_STATE_CHANGED = "state.vad_changed"

    # 音频事件
    AUDIO_LISTEN_DETECTED = "audio.listen_detected"
    AUDIO_LISTEN_STARTED = "audio.listen_started"
    AUDIO_LISTEN_ENDED = "audio.listen_ended"
    AUDIO_CHUNK_READY = "audio.chunk_ready"
    TTS_STARTED = "audio.tts_started"
    TTS_ENDED = "audio.tts_ended"

    # 配置事件
    CONFIG_UPDATED = "config.updated"
    PRIVATE_CONFIG_UPDATED = "config.private_updated"
    SERVICE_CONFIG_CHANGED = "config.service_changed"
    CONFIG_UPDATE_REQUESTED = "config.update_requested"

    # 任务事件
    TASK_CREATED = "task.created"
    TASK_COMPLETED = "task.completed"
    TASK_CANCELLED = "task.cancelled"
    TASK_FAILED = "task.failed"
