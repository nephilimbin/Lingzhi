# ============================================
# 阶段1：构建依赖 - 使用BuildKit缓存加速
# ============================================
FROM python:3.11.9-slim AS builder

WORKDIR /build

# 使用阿里云镜像源加速 apt
RUN sed -i 's/deb.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list.d/debian.sources && \
    sed -i 's/security.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list.d/debian.sources

# 安装构建依赖和系统音频库
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential gcc g++ cmake pkg-config \
    portaudio19-dev libffi-dev libssl-dev \
    ffmpeg libavcodec-extra libavformat-dev libavutil-dev \
    libswscale-dev libswresample-dev libsndfile1 \
    && rm -rf /var/lib/apt/lists/*

# 升级pip
RUN pip install --no-cache-dir --upgrade pip setuptools wheel -i https://mirrors.aliyun.com/pypi/simple/

# ============================================
# 分层安装Python依赖 - 利用Docker层缓存
# ============================================

# 第1层：基础依赖（小型包，快速安装）
COPY requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir --prefix=/install \
    fastapi uvicorn pydantic pyyaml loguru requests aiohttp aiohttp_cors \
    httpx ormsgpack ruamel.yaml psutil netifaces PySocks \
    opuslib_next bs4 packaging \
    -i https://mirrors.aliyun.com/pypi/simple/

# 第2层：PyTorch相关（大型包，单独一层）
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir --prefix=/install \
    torch==2.2.2 torchaudio==2.2.2 \
    --index-url https://mirrors.aliyun.com/pypi/simple/ \
    --extra-index-url https://download.pytorch.org/whl/cpu

# 第3层：AI相关库
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir --prefix=/install \
    silero_vad opencv-python soundfile av pyaudio pydub \
    -i https://mirrors.aliyun.com/pypi/simple/

# 第4层：语音和模型库
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir --prefix=/install \
    funasr modelscope sherpa_onnx edge_tts \
    -i https://mirrors.aliyun.com/pypi/simple/

# 第5层：LLM和MCP相关
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir --prefix=/install \
    openai google-genai dashscope mem0ai cnlunar \
    mcp zai-sdk fastrtc \
    -i https://mirrors.aliyun.com/pypi/simple/

# 第6层：Playwright（不安装浏览器，因为下载太慢）
# 如果需要浏览器功能，请使用官方镜像：mcr.microsoft.com/artifact/mar/playwright/python:v1.58.0-arm64
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir --prefix=/install \
    playwright==1.58.0 \
    -i https://mirrors.aliyun.com/pypi/simple/

# ============================================
# 阶段2：运行时镜像
# ============================================
FROM python:3.11.9-slim

LABEL maintainer="mobile-nika"
LABEL description="AI助手后端服务 - FastAPI + WebSocket + WebRTC"

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONPATH=/app

# 使用阿里云镜像源加速 apt
RUN sed -i 's/deb.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list.d/debian.sources && \
    sed -i 's/security.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list.d/debian.sources

# 安装运行时依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    portaudio19-dev libportaudio2 libportaudiocpp0 \
    ffmpeg libavcodec-extra libavformat-dev libavutil-dev libswscale-dev \
    libsndfile1 libopus0 libvorbis0a \
    curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# 复制Python依赖
COPY --from=builder /install /usr/local

# 创建非root用户
RUN useradd -m -u 1000 -s /bin/bash appuser && \
    mkdir -p /app && chown -R appuser:appuser /app

WORKDIR /app

# 复制应用代码
COPY --chown=appuser:appuser . .

# 创建必要目录
RUN mkdir -p /app/models /app/music /app/data /app/log /app/certs && \
    chown -R appuser:appuser /app/models /app/music /app/data /app/log /app/certs

USER appuser

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8000/api/v1/health || exit 1

CMD ["python", "app.py"]
