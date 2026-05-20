# -*- encoding: utf-8 -*-
import asyncio
import json
import os
import re  # <-- Add re
import ssl
import traceback

# import logging # Use standard logging <-- Remove standard logging
from typing import Any, Dict, List, Optional
from urllib.parse import urlparse  # <-- Add urlparse

from config.logger import setup_logging  # <-- Restore project logger import
from core.models.asr_models import ASRResponseInfo  # Add ASRResponseInfo import
import websockets

from .base import ASRProviderBase  # <-- Restore base class import

TAG = "FunasrDockerASRProvider"
logger = setup_logging()  # <-- Use project logger


# class ASRProvider(): # Keep base class commented out
class ASRProvider(ASRProviderBase):
    """
    ASRProvider implementation using FunASR Docker via WebSocket.
    Connects to a running FunASR WebSocket server to perform speech-to-text.
    Processes Opus audio data.
    """

    def __init__(self, config: Dict[str, Any]):
        """
        Initializes the FunASR Docker ASR provider.

        Args:
            config (Dict[str, Any]): Configuration dictionary containing:
                - base_url (str): Full WebSocket URL (e.g., "wss://127.0.0.1:10095").
                - output_dir (str, optional): Directory path (currently unused).
                - hotword (str, optional): Hotword file path or string. Defaults to "".
                # Other potential configs can be added later if needed
        """
        super().__init__(config)  # 调用父类构造函数
        base_url = config.get("base_url")
        if not base_url:
            raise ValueError("Missing 'base_url' in ASRProvider config for FunASR_Docker")

        parsed_url = urlparse(base_url)
        self.ssl_enabled = parsed_url.scheme == "wss"
        self.host = parsed_url.hostname
        self.port = parsed_url.port

        if not self.host or not self.port:
            raise ValueError(f"Could not parse host/port from base_url: {base_url}")

        # Keep other parameters as defaults for now
        self.mode = config.get("mode", "2pass")  # Example: allow override later if needed
        self.chunk_size = config.get("chunk_size", [5, 10, 5])
        self.chunk_interval = config.get("chunk_interval", 10)
        self.encoder_chunk_look_back = config.get("encoder_chunk_look_back", 4)
        self.decoder_chunk_look_back = config.get("decoder_chunk_look_back", 0)
        self.hotword = config.get("hotword", "")  # Allow hotword config
        self.use_itn = config.get("use_itn", True)
        self.uri = base_url  # Use the full base_url as the URI
        self.ssl_context = self._build_ssl_context()
        self.hotword_msg = self._prepare_hotword_msg()
        self.fallback_to_ws = config.get("fallback_to_ws", False)  # 回退选项
        self.type = config.get("type", "funasr_docker")
        self.model_name = config.get("model_name", "funasr_docker-unknow")

        # 重试配置
        self.max_retries = config.get("max_retries", 3)  # 最大重试次数
        self.retry_delay = config.get("retry_delay", 2.0)  # 初始重试延迟（秒）
        self.retry_backoff = config.get("retry_backoff", 2.0)  # 退避因子

    def _build_uri(self) -> str:
        """Builds the WebSocket URI."""
        # Now redundant as we take base_url directly
        # protocol = "wss" if self.ssl_enabled else "ws"
        # return f"{protocol}://{self.host}:{self.port}"
        return self.uri

    def _build_ssl_context(self) -> Optional[ssl.SSLContext]:
        """Builds the SSL context if SSL is enabled."""
        if self.ssl_enabled:
            ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
            # FunASR Docker often uses self-signed certs, allow them for ease of use.
            # For production, proper cert validation is recommended.
            ssl_context.check_hostname = False
            ssl_context.verify_mode = ssl.CERT_NONE
            return ssl_context
        return None

    def _prepare_hotword_msg(self) -> str:
        """Prepares the hotword message string."""
        hotword_msg = ""
        if self.hotword and self.hotword.strip() != "":
            if os.path.exists(self.hotword):
                try:
                    fst_dict = {}
                    with open(self.hotword, "r", encoding="utf-8") as f_scp:
                        hot_lines = f_scp.readlines()
                        for line in hot_lines:
                            words = line.strip().split(" ")
                            if len(words) < 2:
                                logger.bind(tag=TAG).warning(f"Skipping invalid hotword line: {line.strip()}")
                                continue
                            try:
                                fst_dict[" ".join(words[:-1])] = int(words[-1])
                            except ValueError:
                                logger.bind(tag=TAG).warning(
                                    f"Skipping invalid hotword line (format error): {line.strip()}"
                                )
                        hotword_msg = json.dumps(fst_dict)
                except Exception as e:
                    logger.bind(tag=TAG).error(f"Error reading hotword file {self.hotword}: {e}", exc_info=True)
                    hotword_msg = ""  # Fallback to empty if error
            else:
                # Treat as direct hotword string if not a file path
                # Example: "阿里巴巴 20" - needs proper JSON formatting by user if complex
                hotword_msg = self.hotword
        return hotword_msg

    def _is_retryable_error(self, error: Exception) -> bool:
        """判断错误是否可以通过重试解决"""
        retryable_errors = (
            websockets.exceptions.InvalidHandshake,
            websockets.exceptions.InvalidStatusCode,
            ConnectionRefusedError,
            ConnectionResetError,
            asyncio.TimeoutError,
        )
        return isinstance(error, retryable_errors)

    async def speech_to_text(self, pcm_data: List[bytes]) -> ASRResponseInfo:
        """
        Performs speech-to-text on the given Opus audio data using FunASR Docker.
        带重试机制的语音识别

        Args:
            pcm_data (List[bytes]): 接收pcm格式音频列表

        Returns:
            ASRResponseInfo: ASR响应信息包含识别的文本和相关信息
        """
        # --- 音频预处理阶段（不涉及网络连接，无需重试）---
        import struct

        # 由于输入已经是PCM格式，直接使用
        try:
            # 确保所有pcm_frame都不是None并且转换为bytes
            valid_pcm_data = []
            for frame in pcm_data:
                if frame is not None:
                    if isinstance(frame, bytes):
                        valid_pcm_data.append(frame)
                    else:
                        # 如果不是bytes类型，尝试转换
                        valid_pcm_data.append(bytes(frame))

            audio_data = b"".join(valid_pcm_data)

        except Exception:
            logger.bind(tag=TAG).error(f"Failed to decode Opus data: {traceback.format_exc()}")
            return ASRResponseInfo(text="", is_final=True, provider_name="FunASR-Docker")

        # 检查音频数据是否为空
        if len(audio_data) == 0:
            logger.bind(tag=TAG).error("解码后的PCM数据为空，无法进行ASR处理")
            return ASRResponseInfo(text="", is_final=True, provider_name="FunASR-Docker")

        # 尝试移除开头的静音部分
        if len(audio_data) >= 1000:
            try:
                # 找到第一个非零样本的位置
                samples_to_check = min(len(audio_data) // 2, 4000)  # 检查前4000个样本（250ms@16kHz）
                samples = struct.unpack("<" + "h" * samples_to_check, audio_data[: samples_to_check * 2])

                first_non_zero_idx = 0
                significant_samples = 0
                # 寻找连续的有意义音频
                for i, sample in enumerate(samples):
                    if abs(sample) > 100:  # 降低阈值，寻找更明显的音频信号
                        if significant_samples == 0:
                            first_non_zero_idx = i
                        significant_samples += 1
                        if significant_samples >= 5:  # 找到连续5个有意义的样本
                            break
                    else:
                        significant_samples = 0

                if first_non_zero_idx > 0 and significant_samples >= 5:
                    # 跳过开头的静音部分，但保留一些缓冲
                    skip_samples = max(0, first_non_zero_idx - 320)  # 保留20ms的缓冲（320样本@16kHz）
                    skip_bytes = skip_samples * 2
                    if skip_bytes > 0 and skip_bytes < len(audio_data) // 3:  # 最多跳过1/3的数据
                        audio_data = audio_data[skip_bytes:]

            except Exception as trim_error:
                logger.bind(tag=TAG).debug(f"Could not trim leading silence: {trim_error}")

        # 检查音频数据长度是否合理
        min_audio_length = 1600  # 至少100ms的16kHz单声道音频
        if len(audio_data) < min_audio_length:
            logger.bind(tag=TAG).warning(
                f"音频数据过短: {len(audio_data)} bytes ({len(audio_data) / 32:.1f}ms), 可能影响识别效果"
            )

        if not audio_data:
            logger.bind(tag=TAG).warning("Opus decoding resulted in empty PCM data.")
            return ASRResponseInfo(text="", is_final=True, provider_name="FunASR-Docker")

        # --- 重试循环阶段 ---
        last_error = None

        for attempt in range(self.max_retries + 1):
            try:
                return await self._transcribe_audio(audio_data)
            except Exception as e:
                last_error = e
                if not self._is_retryable_error(e):
                    # 不可重试的错误，直接抛出
                    raise
                if attempt < self.max_retries:
                    delay = self.retry_delay * (self.retry_backoff ** attempt)
                    logger.bind(tag=TAG).warning(
                        f"ASR连接失败 (尝试 {attempt + 1}/{self.max_retries + 1})，"
                        f"{delay:.1f}秒后重试: {type(e).__name__}: {e}"
                    )
                    await asyncio.sleep(delay)
                else:
                    logger.bind(tag=TAG).error(
                        f"ASR连接失败，已达最大重试次数 ({self.max_retries + 1}): {type(e).__name__}: {e}"
                    )

        # 所有重试都失败，返回空结果
        return ASRResponseInfo(text="", is_final=True, provider_name="FunASR-Docker")

    async def _transcribe_audio(self, audio_data: bytes) -> ASRResponseInfo:
        """
        实际的音频转写逻辑（WebSocket 通信）

        Args:
            audio_data (bytes): 预处理后的PCM音频数据

        Returns:
            ASRResponseInfo: ASR响应信息包含识别的文本和相关信息

        Raises:
            Exception: 连接或通信失败时抛出异常，由上层 speech_to_text 处理重试
        """
        result_text: Optional[str] = None
        final_result_received = asyncio.Event()
        accumulated_text = ""

        # 添加连接超时和更详细的参数
        connect_timeout = 10  # 10秒连接超时

        async with websockets.connect(
            self.uri,
            subprotocols=["binary"],
            ping_interval=None,
            ping_timeout=None,  # 禁用ping超时
            close_timeout=10,
            ssl=self.ssl_context,
            max_size=2**23,  # 8MB max message size
            open_timeout=connect_timeout,
        ) as websocket:
            logger.bind(tag=TAG).info("WebSocket connection established.")

            # 1. Send configuration message
            config_message = json.dumps(
                {
                    "mode": "offline",  # 使用offline模式，更稳定
                    "chunk_size": [0, 10, 5],  # 标准配置
                    "encoder_chunk_look_back": 4,
                    "decoder_chunk_look_back": 1,
                    "chunk_interval": 10,
                    "wav_name": "funasr_docker.wav",
                    "is_speaking": True,
                    "hotwords": self.hotword_msg if self.hotword_msg else "",
                    "itn": False,  # 先禁用ITN，减少复杂性
                }
            )
            try:
                await websocket.send(config_message)
            except Exception as config_error:
                logger.bind(tag=TAG).error(
                    f"Error sending config message: {type(config_error).__name__}: {config_error}",
                    exc_info=True,
                )
                raise

            # 2. Start receiving messages in a separate task
            async def receive_messages():
                nonlocal result_text, accumulated_text, final_result_received
                try:
                    while True:
                        message = await websocket.recv()
                        try:
                            meg = json.loads(message)
                            text = meg.get("text", "")
                            mode = meg.get("mode", "")
                            is_final = meg.get("is_final", False)

                            if mode == "online":
                                accumulated_text += text
                            elif mode == "offline":
                                accumulated_text = text
                                final_result_received.set()
                            elif mode == "2pass-online":
                                accumulated_text += text
                            elif mode == "2pass-offline":
                                accumulated_text = text
                                final_result_received.set()
                            else:
                                accumulated_text += text

                            if is_final or mode in ["offline", "2pass-offline"]:
                                final_result_received.set()
                                break

                        except json.JSONDecodeError:
                            logger.bind(tag=TAG).warning(f"Received non-JSON message: {message}")
                        except Exception as e:
                            logger.bind(tag=TAG).error(f"Error processing message: {e}", exc_info=True)
                            final_result_received.set()
                            break
                except websockets.exceptions.ConnectionClosedOK:
                    logger.bind(tag=TAG).info("WebSocket connection closed normally by server.")
                    final_result_received.set()
                except websockets.exceptions.ConnectionClosedError as e:
                    logger.bind(tag=TAG).error(f"WebSocket connection closed with error: {e}", exc_info=True)
                    final_result_received.set()
                except Exception as e:
                    logger.bind(tag=TAG).error(f"Error in receive loop: {e}", exc_info=True)
                    final_result_received.set()

            receive_task = asyncio.create_task(receive_messages())

            # 3. Send audio data in chunks
            stride_ms = 60 * self.chunk_size[1] / self.chunk_interval
            stride = int(stride_ms * 16 * 2)  # 16kHz, 16-bit (2 bytes)

            total_bytes = len(audio_data)
            bytes_sent = 0

            try:
                while bytes_sent < total_bytes:
                    chunk = audio_data[bytes_sent : bytes_sent + stride]
                    if not chunk:
                        break
                    await websocket.send(chunk)
                    bytes_sent += len(chunk)
            except Exception as send_error:
                logger.bind(tag=TAG).error(
                    f"Error sending audio data: {type(send_error).__name__}: {send_error}",
                    exc_info=True,
                )
                raise

            # 4. Send end-of-speech signal
            eos_message = json.dumps({"is_speaking": False})
            try:
                await websocket.send(eos_message)
            except Exception as eos_error:
                logger.bind(tag=TAG).error(
                    f"Error sending end-of-speech signal: {type(eos_error).__name__}: {eos_error}",
                    exc_info=True,
                )
                raise

            # 5. Wait for the final result from the receiving task
            try:
                await asyncio.wait_for(final_result_received.wait(), timeout=30.0)
                result_text = accumulated_text
                # 格式化处理<|zh|><|NEUTRAL|><|Speech|> 删除<>及其里面的内容
                if result_text is not None:
                    result_text = re.sub(r"<\|.*?\|>", "", result_text).strip()
            except asyncio.TimeoutError:
                logger.bind(tag=TAG).error("Timeout waiting for final result")
                # 格式化处理<|zh|><|NEUTRAL|><|Speech|> 删除<>及其里面的内容
                if result_text is not None:
                    result_text = re.sub(r"<\|.*?\|>", "", result_text).strip()
                result_text = accumulated_text
                logger.bind(tag=TAG).info(f"Final result received: {result_text}")

            # 6. Ensure receiver task is cleaned up
            receive_task.cancel()
            try:
                await receive_task
            except asyncio.CancelledError:
                logger.bind(tag=TAG).debug("Receive task cancelled successfully.")

        # Return the final result with ASRResponseInfo
        return ASRResponseInfo(text=result_text or "", is_final=True, provider_name="FunASR-Docker")

    def is_support_stream_mode(self) -> bool:
        return False

    def close(self):
        # 无需手动关闭
        pass
