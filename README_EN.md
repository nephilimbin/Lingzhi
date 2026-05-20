# LingZhi

A mobile AI voice assistant built with Flutter and FastAPI, featuring real-time voice calls, intelligent conversations, and extensible plugin system. Future updates will add Agent capabilities for handling complex problems.

## Project Overview

LingZhi is a complete AI voice assistant, primarily built and developed using Claude Code + GLM Code models. It consists of a mobile application and a backend service.

The project adopts modern architecture design, supporting WebRTC real-time audio/video communication, WebSocket message transmission, and MCP (Model Context Protocol) protocol extensions.

The frontend adopts Doubao's UI design style, replicating most of its functionality and interaction experience. You can customize backend service interfaces according to personal needs, adjust and extend backend business logic, or integrate other AI services like OpenAI.

**Personal Motivation**: As a non-professional programmer, I wanted to verify the application of AI Coding in actual projects and the viable one-person company model. This project is mainly for personal learning and daily use, aiming to create my own JARVIS robot. Additionally, based on current AI developments and emerging issues, some problems have been exposed during family use - such as inaccurate or incorrect model answers, leading elderly family members with limited discernment to over-rely on and form incorrect perceptions. Therefore, this can help check and detect issues early during family daily use.

## Core Features

- **Real-time Voice Calls** - Low-latency voice communication based on WebRTC
- **Real-time Image Understanding** - Supports real-time image understanding conversations
- **Secure Transmission** - Secure transmission via WSS or HTTPS
- **Intelligent Conversation** - Integrated multiple LLMs (OpenAI, Gemini, DeepSeek, etc.)
- **Voice Recognition** - Supports multiple ASR services like FunASR, Tencent Cloud
- **Voice Synthesis** - Supports multiple TTS services like Alibaba Cloud, Doubao
- **Streaming Output** - Supports streaming or non-streaming output for voice and text
- **Function Calling** - Supports function calling
- **MCP Protocol** - Model Context Protocol for extending AI capabilities
- **Plugin System** - Extensible functional plugin architecture

## Quick Start

### Hardware Deployment Recommendations

- **Server**: Recommended to use cloud servers (Alibaba Cloud, Tencent Cloud, etc.), with at least 4 cores and 8GB memory
  - OS: Linux (Ubuntu 20.04+) / macOS 12+ / Windows 10+
  - Python: 3.11+
- **Mobile**:
  - iOS: iOS 14.0 and above
  - Android: Android 5.0 (API 21) and above

### Development Environment Requirements

- Python 3.11+
- Flutter 3.29.2+
- Conda (recommended)
- FFmpeg
- Opus codec

### Backend Service Deployment

```bash
# 1. Clone the project
git clone https://github.com/nephilimbin/lingzhi.git
cd lingzhi

# 2. Create and activate Conda environment (you can use other environment managers)
conda create -n lingzhi python=3.11
conda activate lingzhi

# 3. Install dependencies and necessary tools
# 3.1 Install dependency libraries
cd server
pip install -r requirements.txt

# 3.2 Install dependency tools (choose the appropriate method for your system)
1. Install FFmpeg
2. Install Opus codec
   - **macOS**: `brew install opus`
   - **Linux**: `sudo apt-get install libopus-dev` or `sudo yum install opus-devel`
   - **Note**: macOS users should **NOT** globally set `DYLD_LIBRARY_PATH` in `~/.zshrc` or `~/.bash_profile`, as this will cause Playwright Chromium to crash
3. Install playwright browser: execute `playwright install`

# 4. Generate SSL certificate (required when SSL is enabled in config, see config file below)
bash scripts/generate_ssl_cert.sh

# 5. Configure service parameters
📖 **Detailed Configuration Guide**: [docs/SERVER_CONFIG_GUIDE.md](docs/SERVER_CONFIG_GUIDE.md)

## Basic Configuration Steps:
# 5.1 Copy configuration file
cp server/config/.server_config_example.yaml server/config/.server_config.yaml

# 5.2 Apply for necessary API keys (recommended configuration)
# - ZhipuAI (GLM): https://open.bigmodel.cn/ (for LLM, has free quota)
# - Alibaba Cloud DashScope: https://dashscope.console.aliyun.com/ (for ASR/TTS/VLM, has free quota)

# 5.3 Edit configuration file and fill in API keys
vim server/config/.server_config.yaml
# Required configurations:
# - LLM: Configure at least one LLM (e.g., GlmLLM)
# - ASR: Configure speech recognition service (e.g., QwenASR)
# - TTS: Configure text-to-speech service (e.g., QwenTTS)
# - VAD: Use SileroVAD (local, no configuration needed)

# 5.4 Edit MCP configuration (optional, if using MCP features)
vim server/config/.mcp_server_settings.json

# 6. Start the service
# Method 1: Use startup script (recommended)
./start.sh

# Method 2: Run directly (macOS users need to temporarily set DYLD_LIBRARY_PATH)
# macOS:
DYLD_LIBRARY_PATH=/opt/homebrew/lib python app.py

# Or use uv (recommended):
DYLD_LIBRARY_PATH=/opt/homebrew/lib uv run python app.py

# Linux/Windows:
python app.py
# or
uv run python app.py
```

### Mobile App Build (Mobile source code will be open-sourced later)

```bash
# 1. Enter app directory
cd app

# 2. Install dependencies
flutter pub get

# 3. Run debug version
flutter run

# 4. Install to device
flutter install

# 5. Build release version
flutter build ios --release      # iOS
flutter build apk --release      # Android
```

### Backend Service Endpoints

| Endpoint | Description |
|----------|-------------|
| `http://localhost:8000` | Service homepage |
| `ws://localhost:8000/chat/v1/` | WebSocket connection |
| `http://localhost:8000/api/v1/health` | Health check |
| `http://localhost:8000/api/v1/config/` | Configuration management |
| `http://localhost:8000/docs` | API documentation |

## Project Structure

```
mobile-nika/
├── app/                              # Flutter mobile application
│   ├── lib/
│   │   ├── core/                     # Core shared layer
│   │   │   ├── api/                  # API interfaces
│   │   │   ├── config/               # App configuration
│   │   │   ├── models/               # Data models
│   │   │   ├── providers/            # State management
│   │   │   ├── services/             # Business services
│   │   │   ├── utils/                # Utility classes
│   │   │   └── widgets/              # Common components
│   │   ├── features/                 # Feature modules (Clean Architecture)
│   │   │   ├── chat/                 # Chat functionality
│   │   │   ├── conversation/         # Conversation management
│   │   │   ├── settings/             # Settings page
│   │   │   ├── discovery/            # Discovery features
│   │   │   └── telephony/            # Telephony features
│   │   └── main.dart
│   ├── android/                      # Android platform code
│   ├── ios/                          # iOS platform code
│   ├── assets/                       # Static resources
│   └── pubspec.yaml                  # Dependency configuration
│
├── server/                           # FastAPI backend service
│   ├── app.py                        # Application entry point
│   ├── api/                          # API routing layer
│   │   ├── websocket.py              # WebSocket routes
│   │   ├── webrtc.py                 # WebRTC routes
│   │   ├── config.py                 # Configuration API
│   │   └── health.py                 # Health check
│   ├── config/                       # Configuration management
│   │   ├── server_config.py          # Server configuration
│   │   └── assets/                   # Configuration resources
│   ├── core/                         # Core business layer
│   │   ├── adapters/                 # Adapter layer
│   │   ├── connection/               # Connection management
│   │   ├── container/                # Dependency injection container
│   │   ├── context/                  # Context management
│   │   ├── events/                   # Event system
│   │   ├── middleware/               # Middleware
│   │   ├── providers/                # Service providers (ASR, TTS, LLM, VAD, VLM, memory management, etc.)
│   │   ├── session/                  # Session management
│   │   ├── process/                  # Business processing
│   │   ├── intent/                   # Intent recognition
│   │   └── utils/                    # Utility modules
│   ├── plugins/                      # Plugin system
│   │   └── functions/                # Function plugins
│   ├── models/                       # Local model storage
│   ├── data/                         # User data
│   ├── certs/                        # SSL certificates
│   ├── scripts/                      # Utility scripts
│   ├── test/                         # Test scripts
│   └── requirements.txt              # Python dependencies
│
├── .claude/                          # Claude development configuration
│   ├── agents/                       # Custom agents
│   └── commands/                     # Custom commands
│
├── web/                              # ICP filing homepage
│   └── index.md                      # Homepage
│
├── pyproject.toml                    # Python formatting configuration
└── CLAUDE.md                         # Project development guide
```

## Important Notes

1. **macOS Environment Variable Setup**:
   - Do NOT globally set `DYLD_LIBRARY_PATH=/opt/homebrew/lib` in `~/.zshrc` or `~/.bash_profile`
   - This will cause Playwright Chromium to crash on Apple Silicon (SIGBUS)
   - Please use the provided `start.sh` script to start the service, or set environment variables temporarily in the command line
2. Some Android devices cannot use WebRTC video calls
3. Currently no Agent capability, only simple function tools or MCP module calls
4. Some plugin features cannot be used directly, such as video search and e-book search. You can use AI coding to help supplement or deploy your own services
5. The memory module is being reconsidered for product functionality, leaning more towards multimodal retrieval assistance for life or work memory. Long-term memory functionality needs validation

## Future Development Directions

1. **Frontend**: Mainly as a unified entry point for multiple devices, achieving multi-device collaboration through local service deployment and third-party services. Multi-platform service support.
2. **Backend**: Mainly as a provider for personalized custom services, optimizing and standardizing interfaces to provide a more convenient development experience. Enable AI to quickly help users deploy new features according to reference documentation or module examples. Mainly suitable for scenarios with high privacy and security requirements or home use.
3. **Agent Features**: Will add Skill and Agent functional modules, along with related plugins or modules.

## Contributing

1. Fork this repository
2. Create a feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

This project is licensed under the **Business Source License 1.1 (BSL-1.1)**.

- **Personal/Non-commercial Use**: Free for permanent use, learning, and research
- **Commercial Use**: Contact the author for authorization (lingzhi0211@163.com)
- **Change Date**: Automatically converts to MIT license on January 1, 2030

See [LICENSE](LICENSE) file for details

## Acknowledgments

- [xiaozhi-esp32-server](https://github.com/xinnan-tech/xiaozhi-esp32-server) - XiaoZhi ESP32 Server
- [fastrtc](https://github.com/gradio-app/fastrtc) - Real-time communication library for Python
- And all related open-source projects and community contributors

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=nephilimbin/lingzhi&type=date&legend=top-left)](https://www.star-history.com/#nephilimbin/lingzhi&type=date&legend=top-left)

---

**Note**:
1. This project is for learning and research purposes only. Please do not use for commercial purposes.
2. All third-party API service providers referenced by this application are unrelated to this project. Please use with caution. It is recommended that users prefer service providers with relevant business licenses and carefully read their service agreements and privacy policies. This software does not host any account keys, participate in fund transfers, or assume risks of top-up fund losses.
3. This project's functionality is not yet complete and has not passed network security assessments. Please do not use in production environments. If you deploy and learn this project in a public network environment, please take necessary precautions.
