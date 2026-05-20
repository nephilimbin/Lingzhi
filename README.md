# 零知

[English](README_EN.md) | 简体中文

一款基于 Flutter 和 FastAPI 构建的移动端 AI 语音助手，支持实时语音通话、智能对话和多功能插件扩展，后续会增加Agent等相关处理复杂问题能力。

## 项目简介

零知是一个完整的 AI 语音助手，完全由Claude Code + GLM Code模型为主进行构建并完成编码开发。包含移动端应用和服务端两部分。
项目采用现代化的架构设计，支持 WebRTC 实时音视频通信、WebSocket 消息传输，以及 MCP (Model Context Protocol) 协议扩展。
该项目前端采用Doubao的UI设计风格，复刻了大部分的功能和交互体验。可以根据个人需求自行开发后端服务接口，对后端的业务逻辑进行调整和扩展。或者接入OpenClaw等其他AI服务。

个人初衷：作为一名非专业编程人员，仅仅想验证AI Coding在实际项目中的应用及可运行的一人公司模式。本项目主要也是用于个人学习及生活使用。想制作一个属于自己的Javis机器人。而且基于现有AI发展及产生的问题，对于家庭成员的使用中也暴露出一些问题，比如模型回答信息不准确或者错误，从而导致缺乏辨别力的老人过度依赖而产生不正确的认知。因此可以在家人日常使用中检查并早起发现一些问题。

## 核心特性

- **实时语音通话** - 基于 WebRTC 的低延迟语音通信
- **实时图像理解对话** - 支持实时图像理解对话
- **安全传输** - 基于 wss 或 https 的安全传输
- **智能对话** - 集成多种大语言模型 (OpenAI, Gemini, DeepSeek 等)
- **语音识别** - 支持 FunASR、腾讯云等多种 ASR 服务
- **语音合成** - 支持阿里云、豆包等多种 TTS 服务
- **流式输出** - 支持语音、文字的流式或非流式输出形式
- **FunctionCall** - 支持函数调用
- **MCP 协议** - 支持 Model Context Protocol 扩展 AI 能力
- **插件系统** - 可扩展的功能插件架构

## 快速开始

### 硬件部署推荐

- **服务器**：推荐使用云服务器（如阿里云、腾讯云等），配置至少 4 核 8GB 内存
  - 操作系统：Linux (Ubuntu 20.04+) / macOS 12+ / Windows 10+
  - Python：3.11+
- **移动端**：
  - iOS：iOS 14.0 及以上
  - Android：Android 5.0 (API 21) 及以上

### 开发环境要求

- Python 3.11+
- Flutter 3.29.2+
- Conda (推荐)
- FFmpeg
- Opus编解码器

### 后端服务部署

```bash
# 1. 克隆项目
git clone https://github.com/nephilimbin/lingzhi.git
cd lingzhi # 前往项目目录

# 2. 创建并激活 Conda 环境（可以使用其他环境管理器）
conda create -n lingzhi python=3.11
conda activate lingzhi

# 3. 安装依赖及必要工具
# 3.1 安装依赖库
cd server
pip install -r requirements.txt

# 3.2 安装依赖工具(根据系统选择对应的方式)
1. 安装FFmpeg
2. 安装Opus编解码器
   - **macOS**: `brew install opus`
   - **Linux**: `sudo apt-get install libopus-dev` 或 `sudo yum install opus-devel`
   - **注意**: macOS 用户**不要**在 `~/.zshrc` 或 `~/.bash_profile` 中全局设置 `DYLD_LIBRARY_PATH`，这会导致 Playwright Chromium 崩溃
3. 安装playwright浏览器，执行命令`playwright install`

# 4. 生成 SSL 证书 (在配置文件中开启SSL时需执行，配置文件见下)
bash scripts/generate_ssl_cert.sh

# 5. 配置服务参数
📖 **详细配置指南**: [docs/SERVER_CONFIG_GUIDE.md](docs/SERVER_CONFIG_GUIDE.md)

## 基本配置步骤:
# 5.1 复制配置文件
cp server/config/.server_config_example.yaml server/config/.server_config.yaml

# 5.2 申请必要的 API 密钥 (推荐配置)
# - 智谱AI (GLM): https://open.bigmodel.cn/ (用于LLM，有免费额度)
# - 阿里云DashScope: https://dashscope.console.aliyun.com/ (用于ASR/TTS/VLM，有免费额度)

# 5.3 编辑配置文件，填写 API 密钥
vim server/config/.server_config.yaml
# 必须配置项:
# - LLM: 至少配置一个大语言模型 (如 GlmLLM)
# - ASR: 配置语音识别服务 (如 QwenASR)
# - TTS: 配置语音合成服务 (如 QwenTTS)
# - VAD: 使用 SileroVAD (本地，无需配置)

# 5.4 编辑 MCP 配置 (可选，如需使用MCP功能)
vim server/config/.mcp_server_settings.json

# 6. 启动服务
# 方式1: 使用启动脚本（推荐）
./start.sh

# 方式2: 直接运行（macOS 用户需要临时设置 DYLD_LIBRARY_PATH）
# macOS:
DYLD_LIBRARY_PATH=/opt/homebrew/lib python app.py

# 或使用 uv（推荐）:
DYLD_LIBRARY_PATH=/opt/homebrew/lib uv run python app.py

# Linux/Windows:
python app.py
# 或
uv run python app.py

```

### 移动端应用构建(移动端源码稍后开放)

```bash
# 1. 进入应用目录
cd app

# 2. 安装依赖
flutter pub get

# 3. 运行调试版本
flutter run

# 4. 安装到设备
flutter install

# 5. 构建发布版本
flutter build ios --release      # iOS
flutter build apk --release      # Android
```

### 后端服务端点

| 端点 | 说明 |
|------|------|
| `http://localhost:8000` | 服务首页 |
| `ws://localhost:8000/chat/v1/` | WebSocket 连接 |
| `http://localhost:8000/api/v1/health` | 健康检查 |
| `http://localhost:8000/api/v1/config/` | 配置管理 |
| `http://localhost:8000/docs` | API 文档 |


## 项目结构

```
mobile-nika/
├── app/                              # Flutter 移动端应用
│   ├── lib/
│   │   ├── core/                     # 核心共享层
│   │   │   ├── api/                  # API 接口
│   │   │   ├── config/               # 应用配置
│   │   │   ├── models/               # 数据模型
│   │   │   ├── providers/            # 状态管理
│   │   │   ├── services/             # 业务服务
│   │   │   ├── utils/                # 工具类
│   │   │   └── widgets/              # 通用组件
│   │   ├── features/                 # 功能模块 (Clean Architecture)
│   │   │   ├── chat/                 # 聊天功能
│   │   │   ├── conversation/         # 对话管理
│   │   │   ├── settings/             # 设置页面
│   │   │   ├── discovery/            # 发现功能
│   │   │   └── telephony/            # 电话功能
│   │   └── main.dart
│   ├── android/                      # Android 平台代码
│   ├── ios/                          # iOS 平台代码
│   ├── assets/                       # 静态资源
│   └── pubspec.yaml                  # 依赖配置
│
├── server/                           # FastAPI 后端服务
│   ├── app.py                        # 应用入口
│   ├── api/                          # API 路由层
│   │   ├── websocket.py              # WebSocket 路由
│   │   ├── webrtc.py                 # WebRTC 路由
│   │   ├── config.py                 # 配置 API
│   │   └── health.py                 # 健康检查
│   ├── config/                       # 配置管理层
│   │   ├── server_config.py          # 服务器配置
│   │   └── assets/                   # 配置资源
│   ├── core/                         # 核心业务层
│   │   ├── adapters/                 # 适配器层
│   │   ├── connection/               # 连接管理
│   │   ├── container/                # 依赖注入容器
│   │   ├── context/                  # 上下文管理
│   │   ├── events/                   # 事件系统
│   │   ├── middleware/               # 中间件
│   │   ├── providers/                # 服务提供者（包含语音识别、语音合成、大语言模型、语音活动检测、视觉语言模型、记忆管理等）
│   │   ├── session/                  # 会话管理
│   │   ├── process/                  # 业务处理
│   │   ├── intent/                   # 意图识别
│   │   └── utils/                    # 工具模块
│   ├── plugins/                      # 插件系统
│   │   └── functions/                # 功能函数
│   ├── models/                       # 本地模型存储
│   ├── data/                         # 用户数据
│   ├── certs/                        # SSL 证书
│   ├── scripts/                      # 脚本工具
│   ├── test/                         # 测试脚本
│   └── requirements.txt              # Python 依赖
│
├── .claude/                          # Claude 开发配置
│   ├── agents/                       # 自定义 Agent
│   └── commands/                     # 自定义命令
│
├── web/                              # ICP备案主页
│   └── index.md                      # 主页面
│
├── pyproject.toml                    # Python格式化配置
└── CLAUDE.md                         # 项目开发指南
```


## 使用注意事项

1. **macOS 环境变量设置**:
   - 不要在 `~/.zshrc` 或 `~/.bash_profile` 中全局设置 `DYLD_LIBRARY_PATH=/opt/homebrew/lib`
   - 这会导致 Playwright Chromium 在 Apple Silicon 上崩溃 (SIGBUS)
   - 请使用提供的 `start.sh` 脚本启动服务，或在命令行临时设置环境变量
2. 安卓部分机型无法使用webrtc的视频通话问题
3. 暂时没有Agent的能力，只是简单的函数工具或mcp模块调用。
4. 插件中的部分功能无法直接使用。比如视频搜索及电子书搜索等，可以使用ai coding去帮忙补充或者单独部署您的服务。
5. 记忆模块再重新思考产品功能，更倾向于做多模态的检索辅助生活或者工作记忆，长期记忆功能有待验证。


## 未来的一些发展方向及想法

1. 前端主要作为多种设备的统一入口，通过本地服务部署及其他三方服务，实现多设备协同工作。多平台服务支持。
2. 后端主要作为适用于个人自定义服务的提供者，优化规范接口，提供更便捷的开发体验。让ai可以按照参考文档或者模块示例来快速帮助用户部署新的功能。主要适用于隐私及安全要求较高的场景或者家庭使用。
3. 也会增加Skill及Agent的功能模块，并且添加一些相关的插件或模块。


## 贡献指南

1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 提交 Pull Request

## 许可证

本项目采用 **Business Source License 1.1 (BSL-1.1)** 许可证。

- **个人/非商业用途**：永久免费使用、学习和研究
- **商业用途**：需联系作者获取授权 (lingzhi0211@163.com)
- **变更日期**：2030年1月1日后自动转为 MIT 许可证

详见 [LICENSE](LICENSE) 文件

## 致谢

- [xiaozhi-esp32-server](https://github.com/xinnan-tech/xiaozhi-esp32-server) - 小智ESP32服务器
- [fastrtc](https://github.com/gradio-app/fastrtc) - Python 的实时通信库。
- 以及所有开源的相关项目和社区贡献者。


## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=nephilimbin/lingzhi&type=date&legend=top-left)](https://www.star-history.com/#nephilimbin/lingzhi&type=date&legend=top-left)

---

**注意**: 
1. 本项目仅供学习和研究使用，请勿用于商业用途。
2. 本应用所引用的所有任何第三方API服务商均与本项目无关，请谨慎使用。建议使用者优先选择持有相关业务牌照的服务商，并仔细阅读其服务协议及隐私政策。本软件不托管任何账户密钥、不参与资金流转、不承担充值资金损失风险。
3. 本项目功能未完善，且未通过网络安全测评等，请勿在生产环境中使用。 如果您在公网环境中部署学习本项目，请务必做好必要的防护。
