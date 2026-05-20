```json
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
```

* type（必选）: 定义为消息的类别，用来控制用户事件
	* request.hello：用来与服务端建立连接的握手初始化。
	* request.abort：用来向服务端发送中止信号，用来停止正在执行的上一次request请求。
	* request.listen：用来通知服务端处理音频为主的请求指令。其中modalities必须含有参数"audio"
	* request.read：用来通知服务端处理文字为主的请求指令。其中modalities必须含有参数"text"
	* response.stt：服务端响应语音转文本的内容。
	* response.llm_stream_response：服务端响应大模型的流式文本回复。
	* response.tts：服务端响应的tts内容。
	* response.error：服务端响应的报错内容。
* version（可选）：用于大版本更替间的控制参数。
* transpor：默认为websocket，如执行物联操作，可选mqtt。
* session：管理会话的参数集合。
	* session_id（必须）：识别会话的唯一标识。
	* modalities：会话模式，作为会话中单次请求对话携带对话的内容。比如read模式下，必须含有text，同时可以上传audio、picture等作为辅助信息来完成read text的内容。
	* audio_params：为音频opus固定的解析和被解析参数。
	* audio_input_format: 默认为opus。为客户端发送音频的格式。
	* audio_output_format: 默认为opus，或mp3格式。为服务端发送音频的格式。
	* audio_source：发送和接收的音频源字节码
	* video_source：发送和接收的视频源字节码
	* text_source：发送和接收的文字字符串
	* session_request_id（必须）：用于标识单次会话中多次请求的版本控制标志。
	* chat_mode: 用于标识对话模式