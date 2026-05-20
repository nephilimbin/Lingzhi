# 后端服务配置指南

本指南将帮助你完成 LingZhi 后端服务的基本配置，让服务能够正常运行。

## 前置准备

在开始配置前，请确保你已经：

1. ✅ 克隆了项目代码
2. ✅ 创建并激活了Python环境
3. ✅ 安装了 Python 依赖 (`pip install -r requirements.txt`)

## 快速开始（推荐配置）

对于快速体验，推荐使用以下配置组合（成本最低）：

| 模块 | 推荐服务 | 说明 | 成本 |
|------|----------|------|------|
| **VAD** | SileroVAD | 本地运行 | 免费 |
| **ASR** | QwenASR | 阿里云语音识别 | 有免费额度 |
| **LLM** | GlmLLM | 智谱AI | 有免费额度 |
| **TTS** | QwenTTS | 阿里云语音合成 | 有免费额度 |
| **VLM** | QwenVLM | 阿里云视觉理解 | 有免费额度 |

## 配置步骤

### 步骤 1: 复制配置文件

```bash
cd server/config
cp .server_config_example.yaml .server_config.yaml
```

### 步骤 2: 申请必要的 API 密钥

根据推荐配置，你需要申请以下服务的 API 密钥：

#### 2.1 智谱AI (GLM)

- **申请地址**: https://open.bigmodel.cn/
- **用途**: 大语言模型 (LLM) 和意图识别
- **免费额度**: 新用户有免费调用额度
- **步骤**:
  1. 注册并登录
  2. 进入 API Keys 页面
  3. 创建新的 API Key
  4. 保存 API Key（格式类似 `12345678.abcdefg`）

#### 2.2 阿里云 DashScope

- **申请地址**: https://dashscope.console.aliyun.com/
- **用途**: 语音识别 (ASR)、语音合成 (TTS)、视觉理解 (VLM)
- **免费额度**: 新用户有免费调用额度
- **步骤**:
  1. 登录阿里云账号
  2. 开通 DashScope 服务
  3. 创建 API-KEY
  4. 保存 API Key（格式类似 `sk-abcdefg1234567890`）

> 💡 **提示**: 如果你只想快速体验，智谱AI的免费额度足够使用，可以暂时不申请阿里云密钥。

### 步骤 3: 编辑配置文件

使用你喜欢的编辑器打开 `.server_config.yaml`：

```bash
vim .server_config.yaml
# 或使用其他编辑器
```

#### 3.1 配置基本服务器信息

```yaml
server:
  # [必填] 监听地址
  # - 0.0.0.0 = 允许局域网访问（推荐）
  # - 127.0.0.1 = 仅本机访问
  ip: 0.0.0.0

  # [必填] 监听端口
  port: 8000
```

#### 3.2 配置模型选择

```yaml
selected_module:
  # [必填] 语音活动检测 - 使用本地VAD
  VAD: SileroVAD

  # [必填] 语音识别 - 选择你配置的服务
  ASR: QwenASR  # 或 FunASR (本地)

  # [必填] 大语言模型
  LLM: GlmLLM

  # [必填] 语音合成
  TTS: QwenTTS  # 或 EdgeTTS (免费)

  # [必填] 记忆模块
  Memory: nomem  # 暂时使用无记忆模式

  # [必填] 意图识别
  Intent: GlmLLM

  # [必填] 视觉语言模型
  VLM: QwenVLM
```

#### 3.3 配置智谱AI (GLM)

```yaml
LLM:
  GlmLLM:
    type: zhipu
    api_key: 'YOUR_ZHIPU_API_KEY'  # [必填] 替换为你的API Key
    max_output_tokens: 8192
    model_name: glm-4-flash  # 推荐使用快速版本
    temperature: 0.7
    thinking_mode: disabled
    stream_mode: true
```

#### 3.4 配置阿里云 DashScope

如果你申请了阿里云密钥：

```yaml
# 语音识别配置
ASR:
  QwenASR:
    type: qwen
    nickname: '通义千问-语音识别'
    model_name: gummy-realtime-v1
    api_key: 'YOUR_DASHSCOPE_API_KEY'  # [必填] 替换为你的API Key

# 语音合成配置
TTS:
  QwenTTS:
    type: qwen
    voice: Cherry  # 可选: Cherry, Zhichu, Zhixiang 等
    model_name: qwen3-tts-flash-realtime
    api_key: 'YOUR_DASHSCOPE_API_KEY'  # [必填] 替换为你的API Key
    base_url: 'wss://dashscope.aliyuncs.com/api-ws/v1/realtime'
    language_type: Auto
    sample_rate: 24000

# 视觉语言模型配置
VLM:
  QwenVLM:
    type: qwen
    api_key: 'YOUR_DASHSCOPE_API_KEY'  # [必填] 替换为你的API Key
    model_name: qwen2.5-vl-7b-instruct
    base_url: ''
    thinking_mode: disabled
```

#### 3.5 配置本地语音识别（可选）

如果你想使用本地ASR，无需API密钥：

```yaml
selected_module:
  ASR: FunASR

ASR:
  FunASR:
    type: funasr_local
    nickname: 'FunASR-SenseVoiceSmall(本地)'
    model_name: SenseVoiceSmall
    model_dir: models/SenseVoiceSmall
```

> ⚠️ **注意**: 使用本地ASR需要先下载模型文件，详见 [模型下载指南](#模型下载)

### 步骤 4: 验证配置

确保你已经配置了以下必填项：

- [ ] `server.ip` 和 `server.port` 已设置
- [ ] `selected_module` 所有模块已选择
- [ ] 至少配置了一个 LLM 服务（API Key已填写）
- [ ] 至少配置了一个 ASR 服务
- [ ] 至少配置了一个 TTS 服务
- [ ] VAD 已配置为 SileroVAD（本地）

### 步骤 5: 下载必要的模型文件

如果使用了本地服务（SileroVAD、FunASR），需要下载模型：

```bash
# 下载 Silero VAD 模型
cd server
python -c "from core.providers.vad.silero_vad import SileroVAD; SileroVAD().download_model()"

# 下载 FunASR 模型（如果使用本地ASR）
# 模型会自动下载到 models/SenseVoiceSmall 目录
```

### 步骤 6: 启动服务

```bash
# 返回 server 目录
cd ../..

# 启动服务
./start.sh

# 或手动启动
# macOS:
DYLD_LIBRARY_PATH=/opt/homebrew/lib python app.py

# Linux/Windows:
python app.py
```

## 高级配置（可选）

### SSL/TLS 加密配置

如果你需要在公网环境部署，建议启用SSL：

```yaml
server:
  ssl:
    enabled: true  # 启用SSL
    cert_path: 'certs/lingzhi_server.crt'
    key_path: 'certs/lingzhi_server.key'
```

生成自签名证书：

```bash
bash scripts/generate_ssl_cert.sh
```

### 认证配置

限制只有特定设备可以连接：

```yaml
server:
  auth:
    enabled: true
    tokens:
      - token: 'YOUR_TOKEN_HERE'  # 自定义认证令牌
        name: 'xx:xx:xx:xx:xx:xx'  # 设备MAC地址
```

### WebRTC 配置

如果需要公网视频通话，需要配置TURN服务器：

```yaml
server:
  webrtc:
    ice_servers:
      - urls:
          - 'stun:stun.cloudflare.com:3478'
          - 'turn:turn.cloudflare.com:3478?transport=udp'
        username: 'YOUR_TURN_USERNAME'
        credential: 'YOUR_TURN_CREDENTIAL'
```

免费TURN服务申请：https://.cloudflare.com/

## 其他模型服务配置

除了推荐配置，你还可以使用其他服务：

### OpenAI

```yaml
LLM:
  OpenAILLM:
    type: openai
    api_key: 'YOUR_OPENAI_API_KEY'
    model_name: gpt-4
```

### DeepSeek

```yaml
LLM:
  DeepSeekLLM:
    type: deepseek
    api_key: 'YOUR_DEEPSEEK_API_KEY'
    model_name: deepseek-chat
```

### Gemini

```yaml
LLM:
  GeminiLLM:
    type: gemini
    api_key: 'YOUR_GEMINI_API_KEY'
    model_name: gemini-pro
```

## 常见问题

### Q1: 启动时提示 "API Key is required"

**A**: 请检查你是否正确填写了对应服务的 API Key，确保没有多余的空格或引号。

### Q2: 语音识别没有响应

**A**:
1. 检查 ASR 配置的 API Key 是否正确
2. 如果使用本地ASR，确保模型文件已下载
3. 查看日志输出，确认具体错误信息

### Q3: 语音合成没有声音

**A**:
1. 检查 TTS 配置的 API Key 是否正确
2. 确认网络连接正常（云端TTS需要联网）
3. 检查音频设备是否正常工作

### Q4: 如何只使用免费服务？

**A**: 使用以下配置组合：
- VAD: SileroVAD (本地，免费)
- ASR: FunASR (本地，免费)
- LLM: GlmLLM (有免费额度)
- TTS: EdgeTTS (免费，需联网)

### Q5: 配置文件格式错误

**A**: YAML 对缩进非常敏感，请确保：
- 使用空格缩进（不要用Tab）
- 缩进层级保持一致
- 冒号后面有一个空格
- 字符串用引号包裹

## 配置文件参考

完整的配置示例请参考 `.server_config_example.yaml` 文件。

## 下一步

配置完成后：

1. ✅ 启动后端服务
2. [配置移动端应用](./MOBILE_CONFIG_GUIDE.md) (待补充)
3. 开始使用 LingZhi AI 助手

## 需要帮助？

如果遇到问题：

1. 查看日志文件 `server/log/server.log`
2. 检查配置文件语法
3. 参考项目 Issues: https://github.com/nephilimbin/lingzhi/issues
4. 提交新的 Issue 描述你的问题

---

**最后更新**: 2026-05-20
