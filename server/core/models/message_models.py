import base64
from dataclasses import dataclass, field
from typing import Any, Dict, List, Literal, Optional, Union

import numpy as np

""" 前后端消息格式说明
{
	"type": "request.hello",
	"version": 1,
	"transport": "websocket",
	"session":{
		"session_id": str,
		"modalities": ["text", "audio", "video", "picture"],
		"audio_params": {
			"format": "opus",
			"sample_rate": 16000,
			"channels": 1,
			"frame_duration": 60
		},
		"audio_input_format": "opus",
		"audio_output_format": "opus",
		"audio_source": Bytes,
		"audio_playback_status": {
			"state": "start/stop/end",
			"mode": "manual/auto"
		},
		"chat_mode": "usual_mode/mute_mode",
		"video_source": Bytes,
		"text_source": str,
		"text_status": {
			"state": "sentence_start/sentence_end",
			"mode": "auto",
			"is_first_chunk": True/False
		},
		"session_request_id": str,
		"chat_mode": "usual_mode/mute_mode"
	}
}
"""


TAG = "MessageAPI"

# Type definitions for better type safety
MessageType = Literal[
    "request.hello",
    "request.abort",
    "request.listen",
    "request.read",
    "response.hello",
    "response.stt",
    "response.llm_stream_response",
    "response.tts",
    "response.tts.audio",
    "response.error",
]

TransportType = Literal["websocket", "mqtt", "http", "webrtc"]
ModalityType = Literal["text", "audio", "video", "picture"]
ChatModeType = Literal["usual_mode", "mute_mode"]
AudioFormatType = Literal["opus", "pcm", "wav", "mp3", "ndarray"]


# 事件信息值
class MessageEvent:
    """事件信息"""

    REQUEST = "request"
    RESPONSE = "response"
    REQUEST_HELLO = "request.hello"
    RESPONSE_HELLO = "response.hello"
    REQUEST_ABORT = "request.abort"
    REQUEST_LISTEN = "request.listen"
    REQUEST_READ = "request.read"
    RESPONSE_STT = "response.stt"
    RESPONSE_LLM_STREAM_RESPONSE = "response.llm_stream_response"
    RESPONSE_TTS = "response.tts"
    RESPONSE_TTS_AUDIO = "response.tts.audio"
    RESPONSE_ERROR = "response.error"


# 播放状态类
class PlaybackState:
    """音频播放状态常量"""

    START = "start"
    STOP = "stop"
    END = "end"
    SENTENCE_START = "sentence_start"
    SENTENCE_END = "sentence_end"


# 播放模式类
class PlaybackMode:
    """播放模式常量"""

    MANUAL = "manual"
    AUTO = "auto"


# 文本状态类
class TextState:
    """文本状态常量"""

    SENTENCE_START = "sentence_start"
    SENTENCE_END = "sentence_end"


# 聊天模式类
class ChatMode:
    """聊天模式常量"""

    USUAL_MODE = "usual_mode"
    MUTE_MODE = "mute_mode"


# 音频格式类
class AudioFormat:
    """音频格式常量"""

    OPUS = "opus"
    NDARRAY = "ndarray"
    PCM = "pcm"


# 传输类型类
class Transport:
    """传输类型常量"""

    WEBSOCKET = "websocket"
    WEBRTC = "webrtc"
    MQTT = "mqtt"
    HTTP = "http"


@dataclass
class AudioParams:
    """音频参数配置"""

    format: AudioFormatType = "opus"
    sample_rate: int = 16000
    channels: int = 1
    frame_duration: int = 60


@dataclass
class AudioPlaybackStatus:
    """音频播放状态"""

    state: str
    mode: str = PlaybackMode.AUTO

    # 静态属性
    STATE_START = PlaybackState.START
    STATE_STOP = PlaybackState.STOP
    STATE_END = PlaybackState.END

    MODE_AUTO = PlaybackMode.AUTO
    MODE_MANUAL = PlaybackMode.MANUAL


@dataclass
class TextStatus:
    """文本状态"""

    state: str
    mode: str = PlaybackMode.AUTO
    is_first_chunk: bool = False


@dataclass
class SessionInfo:
    """会话信息"""

    session_id: Optional[str] = None
    modalities: List[ModalityType] = field(default_factory=list)
    audio_params: Optional[AudioParams] = field(default_factory=AudioParams)
    audio_input_format: AudioFormatType = "opus"
    audio_output_format: AudioFormatType = "opus"
    audio_source: Optional[Union[str, bytes, np.ndarray]] = (
        None  # 支持多种音频数据格式：base64字符串、原始字节、numpy数组
    )
    audio_playback_status: Optional[AudioPlaybackStatus] = None
    video_source: Optional[bytes] = None
    text_source: Optional[str] = None
    text_status: Optional[TextStatus] = None
    session_request_id: Optional[str] = None
    chat_mode: Optional[ChatModeType] = None
    model_config: Optional[Dict[str, Any]] = None  # 模型配置，用于配置更新请求


@dataclass
class MessageInfo:
    """消息基础信息"""

    type: MessageType
    version: int = 1
    transport: TransportType = "websocket"
    session: Optional[SessionInfo] = None

    def to_dict(self) -> Dict[str, Any]:
        """转换为字典格式"""
        result = {"type": self.type, "version": self.version, "transport": self.transport}

        if self.session:
            session_dict = {}
            if self.session.session_id:
                session_dict["session_id"] = self.session.session_id
            if self.session.modalities:
                session_dict["modalities"] = self.session.modalities
            if self.session.audio_params:
                session_dict["audio_params"] = {
                    "format": self.session.audio_params.format,
                    "sample_rate": self.session.audio_params.sample_rate,
                    "channels": self.session.audio_params.channels,
                    "frame_duration": self.session.audio_params.frame_duration,
                }
            if self.session.audio_input_format:
                session_dict["audio_input_format"] = self.session.audio_input_format
            if self.session.audio_output_format:
                session_dict["audio_output_format"] = self.session.audio_output_format
            if self.session.audio_source:
                # audio_source 现在直接是base64字符串，无需再次编码
                session_dict["audio_source"] = self.session.audio_source
            if self.session.audio_playback_status:
                session_dict["audio_playback_status"] = {
                    "state": self.session.audio_playback_status.state,
                    "mode": self.session.audio_playback_status.mode,
                }
            if self.session.video_source:
                session_dict["video_source"] = self.session.video_source
            if self.session.text_source:
                session_dict["text_source"] = self.session.text_source
            if self.session.text_status:
                session_dict["text_status"] = {
                    "state": self.session.text_status.state,
                    "mode": self.session.text_status.mode,
                    "is_first_chunk": self.session.text_status.is_first_chunk,
                }
            if self.session.session_request_id:
                session_dict["session_request_id"] = self.session.session_request_id
            if self.session.chat_mode:
                session_dict["chat_mode"] = self.session.chat_mode
            if self.session.model_config:
                session_dict["model_config"] = self.session.model_config

            result["session"] = session_dict

        return result

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "MessageInfo":
        """从字典创建MessageInfo实例"""
        session = None
        if "session" in data:
            session_data = data["session"]

            # 解析audio_params
            audio_params = None
            if "audio_params" in session_data:
                ap_data = session_data["audio_params"]
                audio_params = AudioParams(
                    format=ap_data.get("format", "opus"),
                    sample_rate=ap_data.get("sample_rate", 16000),
                    channels=ap_data.get("channels", 1),
                    frame_duration=ap_data.get("frame_duration", 60),
                )

            # 解析audio_playback_status
            audio_playback_status = None
            if "audio_playback_status" in session_data:
                aps_data = session_data["audio_playback_status"]
                audio_playback_status = AudioPlaybackStatus(
                    state=aps_data.get("state", "start"), mode=aps_data.get("mode", "auto")
                )

            # 解析text_status
            text_status = None
            if "text_status" in session_data:
                ts_data = session_data["text_status"]
                text_status = TextStatus(
                    state=ts_data.get("state", "sentence_start"),
                    mode=ts_data.get("mode", "auto"),
                    is_first_chunk=ts_data.get("is_first_chunk", False),
                )

            session = SessionInfo(
                session_id=session_data.get("session_id"),
                modalities=session_data.get("modalities", []),
                audio_params=audio_params,
                audio_input_format=session_data.get("audio_input_format", "opus"),
                audio_output_format=session_data.get("audio_output_format", "opus"),
                audio_source=session_data.get("audio_source"),
                audio_playback_status=audio_playback_status,
                video_source=session_data.get("video_source"),
                text_source=session_data.get("text_source"),
                text_status=text_status,
                session_request_id=session_data.get("session_request_id"),
                chat_mode=session_data.get("chat_mode", ChatMode.USUAL_MODE),
                model_config=session_data.get("model_config"),
            )

        return cls(
            type=data.get("type", "request.hello"),
            version=data.get("version", 1),
            transport=data.get("transport", "websocket"),
            session=session,
        )

    @classmethod
    def create_audio_bytes_message_info(
        cls, audio_source: Union[bytes, np.ndarray], session_request_id: Optional[str] = None
    ) -> "MessageInfo":
        """从 audio_source 和 session_request_id 创建 MessageInfo 实例

        支持多种音频数据格式：
        - bytes: 原始字节音频数据
        - np.ndarray: numpy数组音频数据（WebRTC音频流）
        """

        session = SessionInfo(
            session_id=None,
            modalities=["audio"],
            audio_source=audio_source,
            session_request_id=session_request_id,
        )

        return cls(
            type="request.audio_bytes",
            version=cls.version,
            transport=cls.transport,
            session=session,
        )


class ResponseInfoInstant:
    """响应信息实例管理类 - 后端专用"""

    @staticmethod
    def create_stt_response(session_id: str, text_source: str, session_request_id: Optional[str] = None) -> MessageInfo:
        """创建STT响应"""
        session = SessionInfo(
            session_id=session_id,
            modalities=["text"],
            text_source=text_source,
            session_request_id=session_request_id,
        )

        return MessageInfo(type="response.stt", session=session)

    @staticmethod
    def create_llm_stream_response(
        session_id: str,
        text_source: str,
        is_first_chunk: bool = False,
        session_request_id: Optional[str] = None,
        text_state: TextState = "sentence_start",
    ) -> MessageInfo:
        """创建LLM流式响应"""
        text_status = TextStatus(state=text_state, is_first_chunk=is_first_chunk)

        session = SessionInfo(
            session_id=session_id,
            modalities=["text"],
            text_source=text_source,
            text_status=text_status,
            session_request_id=session_request_id,
        )

        return MessageInfo(type="response.llm_stream_response", session=session)

    @staticmethod
    def create_tts_response(
        session_id: str,
        audio_source: Optional[bytes] = None,
        audio_playback_status: Optional[AudioPlaybackStatus] = None,
        text_source: Optional[str] = None,
        session_request_id: Optional[str] = None,
    ) -> MessageInfo:
        """创建TTS响应"""
        modalities = ["audio"]
        if text_source:
            modalities.append("text")

        session = SessionInfo(
            session_id=session_id,
            modalities=modalities,
            audio_source=audio_source,
            audio_playback_status=audio_playback_status,
            text_source=text_source,
            session_request_id=session_request_id,
        )

        return MessageInfo(type="response.tts", session=session)

    @staticmethod
    def create_tts_audio_opus_response(
        session_id: str,
        audio_source: bytes,
        session_request_id: Optional[str],
        audio_input_format: Optional[str] = "opus",
        audio_output_format: Optional[str] = "opus",
    ) -> MessageInfo:
        """创建TTS音频字节响应"""
        session = SessionInfo(
            session_id=session_id,
            modalities=["audio"],
            audio_source=base64.b64encode(audio_source).decode(),
            audio_input_format=audio_input_format,
            audio_output_format=audio_output_format,
            session_request_id=session_request_id,
        )

        return MessageInfo(type="response.tts.audio", session=session)

    @staticmethod
    def create_error_response(
        session_id: str, error_text: str, session_request_id: Optional[str] = None
    ) -> MessageInfo:
        """创建错误响应"""
        session = SessionInfo(
            session_id=session_id,
            modalities=["text"],
            text_source=error_text,
            session_request_id=session_request_id,
        )

        return MessageInfo(type="response.error", session=session)

    @staticmethod
    def create_hello_response(
        session_id: str,
        session_request_id: Optional[str] = None,
        chat_mode: Optional[ChatModeType] = ChatMode.USUAL_MODE,
    ) -> MessageInfo:
        """创建Hello响应"""
        # 创建符合API规范的session信息
        modalities = ["text"]
        session = SessionInfo(
            session_id=session_id,
            modalities=modalities,
            audio_params=AudioParams(
                format="opus",
                sample_rate=16000,
                channels=1,
                frame_duration=60,
            ),
            session_request_id=session_request_id,
            chat_mode=chat_mode,
        )

        return MessageInfo(type="response.hello", session=session)


class RequestParser:
    """请求解析器 - 后端专用"""

    @staticmethod
    def parse_request(data: Dict[str, Any]) -> MessageInfo:
        """解析请求消息"""
        return MessageInfo.from_dict(data)
