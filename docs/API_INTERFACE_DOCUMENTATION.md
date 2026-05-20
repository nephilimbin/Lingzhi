# Mobile Nika AI助手 - API接口规范文档

## 概述

本文档详细描述了Mobile Nika AI助手项目中前后端通信的完整接口规范，包括WebSocket实时通信接口和HTTP REST API接口。

### 服务信息

| 服务类型 | 端点地址 | 说明 |
|---------|---------|------|
| HTTP API | `http://0.0.0.0:8000/api/v1/` | REST API服务 |
| WebSocket文本通道 | `ws://0.0.0.0:8000/chat/v1/` | 文本消息和信令通道 |
| WebSocket音频通道 | `ws://0.0.0.0:8000/chat/v1/audio/` | TTS音频流专用通道 |
| WebSocket WebRTC通道 | `ws://0.0.0.0:8000/chat/v1/webrtc/` | WebRTC信令通道 |
| WebSocket测试通道 | `ws://0.0.0.0:8000/chat/v1/test/` | 连接测试通道 |

### 技术架构

- **后端框架**: FastAPI + WebSocket + FastRTC
- **架构模式**: 依赖注入架构 + 事件驱动
- **核心功能**: 语音识别(ASR)、文本聊天(LLM)、语音合成(TTS)、会话管理、视频理解(VLM)

---

## 1. WebSocket接口

### 1.1 连接认证

所有WebSocket连接必须在HTTP头部携带以下认证信息：

| Header | 类型 | 必填 | 说明 |
|--------|------|------|------|
| `device-id` | string | 是 | 设备唯一标识符 |
| `Authorization` | string | 否 | Bearer Token认证 |

**示例请求头：**
```
device-id: device_abc123
Authorization: Bearer your_token_here
```

### 1.2 文本通道 `/chat/v1/`

主要的WebSocket通信通道，用于文本消息、信令交换和会话管理。

#### 1.2.1 客户端请求消息

##### request.hello - 连接握手

建立WebSocket连接后发送的第一个消息，用于会话初始化。

```json
{
  "type": "request.hello",
  "version": 1,
  "transport": "websocket",
  "session": {
    "session_id": "existing_session_id_or_null",
    "modalities": ["text", "audio"],
    "audio_params": {
      "format": "opus",
      "sample_rate": 16000,
      "channels": 1,
      "frame_duration": 60
    },
    "audio_input_format": "opus",
    "audio_output_format": "opus",
    "chat_mode": "usual_mode"
  }
}
```

| 字段 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `session_id` | string | 否 | null | 已有会话ID，用于恢复会话 |
| `modalities` | string[] | 否 | ["text", "audio"] | 支持的模态类型 |
| `audio_params.format` | string | 否 | "opus" | 音频编码格式 |
| `audio_params.sample_rate` | int | 否 | 16000 | 采样率(Hz) |
| `audio_params.channels` | int | 否 | 1 | 声道数 |
| `audio_params.frame_duration` | int | 否 | 60 | 帧持续时间(ms) |
| `chat_mode` | string | 否 | "usual_mode" | 聊天模式: "usual_mode" / "mute_mode" |

##### request.read - 文本消息

发送文本消息进行处理。

```json
{
  "type": "request.read",
  "version": 1,
  "transport": "websocket",
  "session": {
    "session_id": "session_123",
    "modalities": ["text"],
    "text_source": "你好，请帮我查询今天天气",
    "session_request_id": "req_101112"
  }
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `text_source` | string | 是 | 文本内容 |
| `session_request_id` | string | 否 | 请求唯一标识，用于关联响应 |

##### request.listen - 语音监听控制

控制音频流的开始/停止。

```json
{
  "type": "request.listen",
  "version": 1,
  "transport": "websocket",
  "session": {
    "session_id": "session_123",
    "modalities": ["audio"],
    "audio_playback_status": {
      "state": "start",
      "mode": "auto"
    },
    "session_request_id": "req_789"
  }
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `audio_playback_status.state` | string | 是 | 状态: "start" / "stop" / "end" |
| `audio_playback_status.mode` | string | 否 | 模式: "auto" / "manual" |

##### request.abort - 中断请求

中断当前正在进行的处理。

```json
{
  "type": "request.abort",
  "version": 1,
  "transport": "websocket",
  "session": {
    "session_id": "session_123",
    "session_request_id": "req_to_abort_456"
  }
}
```

##### request.mute - 静音控制

切换静音模式。

```json
{
  "type": "request.mute",
  "version": 1,
  "transport": "websocket",
  "session": {
    "session_id": "session_123",
    "session_request_id": "req_mute_1314",
    "chat_mode": "mute_mode"
  }
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `chat_mode` | string | 是 | 聊天模式: "usual_mode" / "mute_mode" |

##### request.config - 配置更新

更新模型配置。

```json
{
  "type": "request.config",
  "version": 1,
  "transport": "websocket",
  "session": {
    "session_id": "session_123",
    "session_request_id": "req_config_001",
    "model_config": {
      "ASR": "qwen",
      "LLM": "gpt-4o",
      "TTS": "doubao"
    }
  }
}
```

##### 二进制音频数据

前端可以通过WebSocket二进制帧直接发送Opus音频数据。

**传输方式：** WebSocket二进制帧
**音频格式：** Opus编码，16kHz采样率，单声道

#### 1.2.2 服务端响应消息

##### response.hello - 握手响应

```json
{
  "type": "response.hello",
  "version": 1,
  "transport": "websocket",
  "session": {
    "session_id": "server_generated_session_123",
    "modalities": ["text"],
    "audio_params": {
      "format": "opus",
      "sample_rate": 16000,
      "channels": 1,
      "frame_duration": 60
    },
    "session_request_id": "req_hello_1718",
    "chat_mode": "usual_mode"
  }
}
```

##### response.stt - 语音识别结果

返回ASR识别的文本结果。

```json
{
  "type": "response.stt",
  "version": 1,
  "transport": "websocket",
  "session": {
    "session_id": "session_123",
    "modalities": ["text"],
    "text_source": "今天天气怎么样",
    "session_request_id": "req_audio_1516"
  }
}
```

##### response.llm_stream_response - LLM流式响应

返回大语言模型的流式文本响应。

```json
{
  "type": "response.llm_stream_response",
  "version": 1,
  "transport": "websocket",
  "session": {
    "session_id": "session_123",
    "modalities": ["text"],
    "text_source": "今天天气",
    "text_status": {
      "state": "sentence_start",
      "mode": "auto",
      "is_first_chunk": true
    },
    "session_request_id": "req_audio_1516"
  }
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `text_status.state` | string | 文本状态: "sentence_start" / "sentence_end" |
| `text_status.mode` | string | 模式: "auto" / "manual" |
| `text_status.is_first_chunk` | bool | 是否为第一个文本块 |

##### response.tts - TTS状态响应

TTS处理状态通知。

```json
{
  "type": "response.tts",
  "version": 1,
  "transport": "websocket",
  "session": {
    "session_id": "session_123",
    "modalities": ["audio", "text"],
    "audio_playback_status": {
      "state": "start",
      "mode": "auto"
    },
    "text_source": "今天天气很好，适合出门",
    "session_request_id": "req_audio_1516"
  }
}
```

##### response.tts.audio - TTS音频数据

传输TTS生成的音频数据（base64编码）。

```json
{
  "type": "response.tts.audio",
  "version": 1,
  "transport": "websocket",
  "session": {
    "session_id": "session_123",
    "modalities": ["audio"],
    "audio_source": "base64编码的Opus音频数据",
    "audio_input_format": "opus",
    "audio_output_format": "opus",
    "session_request_id": "req_audio_1516"
  }
}
```

##### response.error - 错误响应

```json
{
  "type": "response.error",
  "version": 1,
  "transport": "websocket",
  "session": {
    "session_id": "session_123",
    "modalities": ["text"],
    "text_source": "ASR服务暂时不可用，请稍后重试",
    "session_request_id": "req_error_1920"
  }
}
```

### 1.3 音频通道 `/chat/v1/audio/`

专门用于TTS Opus音频流的WebSocket通道，与文本通道共享同一个SessionContext。

**连接要求：**
- 必须提供与文本通道一致的`x-session-id`请求头
- 需要通过`device-id`和`Authorization`认证

### 1.4 WebRTC信令通道 `/chat/v1/webrtc/`

用于WebRTC连接的信令交换，支持音视频实时通信。

**连接要求：**
- 可选提供`x-session-id`请求头（如不提供将自动生成）
- 需要通过`device-id`认证

**连接确认消息：**
```json
{
  "role": "system",
  "content": "WebRTC WebSocket连接已建立，会话ID: session_xxx",
  "type": "connection_established",
  "session_id": "session_xxx",
  "is_new_session": true,
  "timestamp": 1703123456.789
}
```

### 1.5 测试通道 `/chat/v1/test/`

用于测试WebSocket连接的基本功能，不涉及复杂业务逻辑。

**连接标记：** 在请求头中添加 `X-Test-Connection: true`

**测试响应：**
```json
{
  "type": "response.hello",
  "data": {
    "status": "test_success",
    "message": "测试连接成功",
    "server_version": "1.0.0"
  },
  "timestamp": "2024-01-01T00:00:00.000Z"
}
```

---

## 2. HTTP REST API接口

### 2.1 健康检查 `/api/v1/health`

#### GET /api/v1/health - 基础健康检查

**响应示例：**
```json
{
  "status": "healthy",
  "message": "FastAPI统一服务运行正常",
  "timestamp": "2024-01-01T00:00:00.000Z",
  "uptime": "运行中",
  "version": "1.0.0",
  "active_connections": 5,
  "services_status": {
    "status": "initialized"
  }
}
```

#### GET /api/v1/health/detailed - 详细健康检查

**响应示例：**
```json
{
  "status": "healthy",
  "message": "FastAPI统一服务详细状态正常",
  "timestamp": "2024-01-01T00:00:00.000Z",
  "uptime": "运行中",
  "version": "1.0.0",
  "active_connections": 5,
  "services_status": {},
  "system_info": {
    "platform": "macOS-14.0",
    "python_version": "3.11.9",
    "cpu_count": 8,
    "memory_total": "16GB",
    "memory_available": "8GB",
    "disk_usage": "45%"
  },
  "performance_metrics": {
    "cpu_percent": 25.5,
    "memory_percent": 50.2,
    "active_connections": 5,
    "connection_ids": ["session_123", "session_456"]
  }
}
```

#### GET /api/v1/health/ready - 就绪检查

检查服务是否准备好接受请求。

**响应示例：**
```json
{
  "ready": true,
  "message": "服务已准备就绪",
  "timestamp": "2024-01-01T00:00:00.000Z",
  "services_status": {
    "status": "initialized"
  }
}
```

#### GET /api/v1/health/live - 存活检查

简单的存活检查，用于容器编排系统。

**响应示例：**
```json
{
  "alive": true,
  "message": "服务正在运行",
  "timestamp": "2024-01-01T00:00:00.000Z"
}
```

#### GET /api/v1/health/metrics - 获取服务指标

**响应示例：**
```json
{
  "timestamp": "2024-01-01T00:00:00.000Z",
  "connections": {
    "active": 5,
    "total_created": 10
  },
  "system": {
    "cpu_percent": 25.5,
    "memory": {
      "total": 17179869184,
      "available": 8589934592,
      "percent": 50.0,
      "used": 8589934592
    },
    "disk": {
      "total": 494384795648,
      "used": 222473203712,
      "free": 271911591936,
      "percent": 45.0
    }
  },
  "services": {
    "status": "initialized"
  }
}
```

### 2.2 配置管理 `/api/v1/config`

#### GET /api/v1/config/health - 配置API健康检查

**响应示例：**
```json
{
  "status": "ok",
  "message": "配置管理API正在运行"
}
```

#### GET /api/v1/config/server-info - 获取服务器信息

返回服务器的SSL状态和推荐连接协议。

**响应示例：**
```json
{
  "success": true,
  "ssl_enabled": false,
  "recommended_protocol": "ws",
  "recommended_port": 8000,
  "message": "服务器未启用SSL加密，建议使用 ws:// 协议",
  "timestamp": "2024-01-01T00:00:00.000Z"
}
```

#### GET /api/v1/config/modules - 获取可用模块列表

**响应示例：**
```json
{
  "success": true,
  "message": "可用模块列表获取成功",
  "modules": {
    "VAD": [
      {
        "name": "silero",
        "type": "silero",
        "model_name": "silero_vad",
        "description": "silero 模块",
        "enabled": true
      }
    ],
    "ASR": [
      {
        "name": "qwen",
        "type": "qwen",
        "model_name": "paraformer-realtime-v2",
        "description": "qwen 模块",
        "enabled": true
      }
    ],
    "LLM": [
      {
        "name": "gpt-4o",
        "type": "openai",
        "model_name": "gpt-4o",
        "description": "gpt-4o 模块",
        "enabled": true
      }
    ],
    "TTS": [
      {
        "name": "doubao",
        "type": "doubao",
        "model_name": "doubao_tts",
        "description": "doubao 模块",
        "enabled": true
      }
    ],
    "VLM": [],
    "Memory": [],
    "Intent": []
  },
  "default_selected_module": {
    "VAD": "silero",
    "ASR": "qwen",
    "LLM": "gpt-4o",
    "TTS": "doubao"
  },
  "timestamp": "2024-01-01T00:00:00.000Z"
}
```

#### GET /api/v1/config/info - 获取配置服务信息

**响应示例：**
```json
{
  "service_name": "配置管理API",
  "version": "1.0.0",
  "description": "WebSocket连接测试和WebRTC配置管理服务",
  "features": ["WebSocket连接测试", "WebRTC配置管理", "模块查询"],
  "supported_endpoints": [
    "POST /api/v1/config/test-connection",
    "GET /api/v1/config/modules",
    "GET /api/v1/config/health",
    "GET /api/v1/config/info",
    "GET /api/v1/config/webrtc"
  ],
  "config_info": {
    "server_config_loaded": true,
    "available_modules": ["VAD", "ASR", "LLM", "TTS", "VLM", "Memory", "Intent"]
  },
  "timestamp": "2024-01-01T00:00:00.000Z"
}
```

#### POST /api/v1/config/test-connection - 测试WebSocket连接

**请求体：**
```json
{
  "server_url": "ws://192.168.1.2:8000/chat/v1",
  "mac_address": "device_abc123",
  "token": "optional_token"
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `server_url` | string | 是 | WebSocket服务器地址 |
| `mac_address` | string | 是 | 设备MAC地址/设备ID |
| `token` | string | 否 | 认证Token |

**成功响应：**
```json
{
  "success": true,
  "message": "连接成功",
  "details": {
    "handshake_time": 150,
    "connection_time": 100,
    "server_version": "1.0.0"
  },
  "timestamp": "2024-01-01T00:00:00.000Z"
}
```

**失败响应：**
```json
{
  "success": false,
  "message": "服务器未启用SSL加密，请使用 ws:// 协议连接",
  "error_type": "protocol_mismatch",
  "timestamp": "2024-01-01T00:00:00.000Z"
}
```

**错误类型 (error_type)：**

| 错误类型 | 说明 |
|---------|------|
| `invalid_format` | URL格式错误（不是ws://或wss://开头） |
| `invalid_host` | 主机地址无效 |
| `missing_path` | 缺少路径 |
| `connection_timeout` | 连接超时 |
| `connection_refused` | 连接被拒绝 |
| `handshake_failed` | 握手失败 |
| `auth_failed` | 认证失败 |
| `protocol_mismatch` | 协议不匹配（ws://与wss://） |

#### GET /api/v1/config/webrtc - 获取WebRTC配置

获取全局WebRTC RTC配置，供前端使用。

**响应示例：**
```json
{
  "success": true,
  "message": "全局 WebRTC 配置获取成功",
  "config": {
    "iceServers": [
      {
        "urls": ["stun:stun.l.google.com:19302"]
      }
    ],
    "iceCandidatePoolSize": 4,
    "iceTransportPolicy": "all",
    "bundlePolicy": "max-bundle",
    "rtcpMuxPolicy": "require"
  },
  "timestamp": "2024-01-01T00:00:00.000Z"
}
```

### 2.3 连接管理 `/api/v1/chat`

#### GET /api/v1/chat/connections - 获取WebSocket连接统计

**响应示例：**
```json
{
  "status": "success",
  "active_connections": 5,
  "connection_ids": ["session_123", "session_456", "session_789"],
  "total_connections": 10,
  "timestamp": 1703123456.789
}
```

---

## 3. 数据模型定义

### 3.1 消息类型枚举

#### 客户端请求类型
| 类型 | 说明 |
|------|------|
| `request.hello` | 连接握手 |
| `request.read` | 文本消息 |
| `request.listen` | 语音监听控制 |
| `request.abort` | 中断请求 |
| `request.mute` | 静音控制 |
| `request.config` | 配置更新 |

#### 服务端响应类型
| 类型 | 说明 |
|------|------|
| `response.hello` | 握手响应 |
| `response.stt` | 语音识别结果 |
| `response.llm_stream_response` | LLM流式响应 |
| `response.tts` | TTS状态响应 |
| `response.tts.audio` | TTS音频数据 |
| `response.error` | 错误响应 |

### 3.2 传输类型枚举

| 类型 | 说明 |
|------|------|
| `websocket` | WebSocket传输 |
| `webrtc` | WebRTC传输 |
| `mqtt` | MQTT传输 |
| `http` | HTTP传输 |

### 3.3 模态类型枚举

| 类型 | 说明 |
|------|------|
| `text` | 文本 |
| `audio` | 音频 |
| `video` | 视频 |
| `picture` | 图片 |

### 3.4 音频格式枚举

| 类型 | 说明 |
|------|------|
| `opus` | Opus编码 |
| `pcm` | PCM原始音频 |
| `wav` | WAV格式 |
| `mp3` | MP3格式 |
| `ndarray` | NumPy数组（WebRTC内部使用） |

### 3.5 播放状态枚举

| 状态 | 说明 |
|------|------|
| `start` | 开始 |
| `stop` | 停止 |
| `end` | 结束 |
| `sentence_start` | 句子开始 |
| `sentence_end` | 句子结束 |

### 3.6 播放模式枚举

| 模式 | 说明 |
|------|------|
| `auto` | 自动模式（VAD检测） |
| `manual` | 手动模式（按住说话） |

### 3.7 聊天模式枚举

| 模式 | 说明 |
|------|------|
| `usual_mode` | 正常模式 |
| `mute_mode` | 静音模式 |

---

## 4. 交互流程

### 4.1 连接建立流程

```
1. 客户端 → 服务端: WebSocket连接请求 (带device-id头)
2. 服务端 → 客户端: 认证通过，连接建立
3. 客户端 → 服务端: request.hello (会话握手)
4. 服务端 → 客户端: response.hello (确认连接，返回session_id)
```

### 4.2 语音聊天完整流程

```
1. 客户端 → 服务端: request.listen (state: "start", mode: "auto")
2. 客户端 → 服务端: 二进制音频数据流 (连续发送)
3. 客户端 → 服务端: request.listen (state: "stop")
4. 服务端 → 客户端: response.stt (识别结果)
5. 服务端 → 客户端: response.llm_stream_response (多个chunk)
6. 服务端 → 客户端: response.tts (state: "start", 包含文本)
7. 服务端 → 客户端: response.tts.audio (音频数据)
8. 服务端 → 客户端: response.tts (state: "end")
```

### 4.3 文本聊天流程

```
1. 客户端 → 服务端: request.read (文本内容)
2. 服务端 → 客户端: response.llm_stream_response (流式响应)
3. 服务端 → 客户端: response.tts (state: "start")
4. 服务端 → 客户端: response.tts.audio (音频数据)
5. 服务端 → 客户端: response.tts (state: "end")
```

### 4.4 按住说话模式 (Manual Mode)

```
1. 客户端 → 服务端: request.listen (state: "start", mode: "manual")
2. 客户端 → 服务端: 二进制音频数据流 (用户按住期间)
3. 客户端 → 服务端: request.listen (state: "stop", mode: "manual")
4. 服务端 → 客户端: response.stt (识别结果)
5. 服务端 → 客户端: response.llm_stream_response (多个chunk)
6. 服务端 → 客户端: response.tts (state: "start", 包含文本)
7. 服务端 → 客户端: response.tts.audio (音频数据)
8. 服务端 → 客户端: response.tts (state: "end")
```

### 4.5 中断处理流程

```
任意时刻:
1. 客户端 → 服务端: request.abort (中断当前处理)
2. 服务端 → 客户端: 停止所有相关响应
```

### 4.6 WebRTC语音通话流程

```
1. 客户端 → 服务端: HTTP GET /api/v1/config/webrtc (获取RTC配置)
2. 客户端 → 服务端: WebSocket连接 /chat/v1/webrtc/ (建立信令通道)
3. 客户端 ↔ 服务端: WebRTC SDP/ICE交换
4. 客户端 ↔ 服务端: WebRTC音视频流传输
```

---

## 5. 音频数据处理

### 5.1 音频传输机制

**前端发送音频：**
- **格式**: 原始二进制Opus数据流
- **方式**: WebSocket二进制帧直接传输
- **参数**: 通过audio_params指定

**后端返回音频：**
- **格式**: base64编码的Opus数据
- **方式**: JSON包装在response.tts.audio中
- **解码**: 客户端需要base64解码后播放

### 5.2 音频参数标准

```json
{
  "format": "opus",
  "sample_rate": 16000,
  "channels": 1,
  "frame_duration": 60
}
```

| 参数 | 值 | 说明 |
|------|-----|------|
| format | opus | 音频编码格式 |
| sample_rate | 16000 | 16kHz采样率 |
| channels | 1 | 单声道 |
| frame_duration | 60 | 60ms帧长 |

---

## 6. 错误处理

### 6.1 错误码定义

| 错误码 | 说明 |
|--------|------|
| `AUTH_FAILED` | 认证失败 |
| `AUTH_TOKEN_INVALID` | Token无效 |
| `AUTH_DEVICE_NOT_ALLOWED` | 设备不允许 |
| `AUTH_TOKEN_EXPIRED` | Token过期 |
| `SESSION_INVALID` | 会话无效 |
| `SESSION_NOT_FOUND` | 会话不存在 |
| `SESSION_EXPIRED` | 会话过期 |
| `SESSION_ACCESS_DENIED` | 会话访问拒绝 |
| `SERVICE_ERROR` | 服务错误 |
| `SERVICE_UNAVAILABLE` | 服务不可用 |
| `SERVICE_TIMEOUT` | 服务超时 |
| `CONNECTION_ERROR` | 连接错误 |
| `CONNECTION_TIMEOUT` | 连接超时 |
| `CONNECTION_LIMIT_EXCEEDED` | 连接数超限 |
| `INVALID_REQUEST` | 无效请求 |
| `MISSING_PARAMETER` | 缺少参数 |
| `INVALID_PARAMETER` | 参数无效 |
| `INTERNAL_ERROR` | 内部错误 |
| `CONFIGURATION_ERROR` | 配置错误 |
| `RESOURCE_NOT_FOUND` | 资源不存在 |

### 6.2 WebSocket错误响应格式

```json
{
  "type": "error",
  "error_code": "SERVICE_ERROR",
  "message": "服务暂时不可用",
  "timestamp": "2024-01-01T00:00:00.000Z",
  "details": {
    "service": "ASR"
  }
}
```

### 6.3 HTTP错误响应格式

```json
{
  "success": false,
  "error_code": "INTERNAL_ERROR",
  "message": "内部服务器错误",
  "timestamp": "2024-01-01T00:00:00.000Z",
  "details": {
    "error": "详细错误信息"
  }
}
```

---

## 7. 注意事项

### 7.1 消息顺序保证

- WebSocket消息可能不按发送顺序到达
- 使用`session_request_id`进行消息关联和顺序保证
- 流式响应需要按chunk顺序处理

### 7.2 会话状态同步

- 客户端应在每次请求时使用最新的session_id
- 服务器会在响应中返回当前的session_id
- session_request_id在每次请求时应该是唯一的

### 7.3 性能考虑

- 音频数据采用二进制传输减少带宽占用
- JSON消息压缩减少传输延迟
- 流式响应提供更好的用户体验

### 7.4 安全考虑

- 验证所有传入的WebSocket消息
- 实现适当的身份验证和授权
- 在生产环境中使用安全的WebSocket连接 (WSS)

---

## 8. 开发调试

### 8.1 WebSocket连接测试

```javascript
const ws = new WebSocket('ws://localhost:8000/chat/v1/', [], {
  headers: { 'device-id': 'test-device' }
});

ws.onopen = () => {
  // 发送Hello消息
  ws.send(JSON.stringify({
    type: "request.hello",
    version: 1,
    transport: "websocket",
    session: {
      modalities: ["text", "audio"],
      chat_mode: "usual_mode"
    }
  }));
};
```

