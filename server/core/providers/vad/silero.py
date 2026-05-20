import os
import traceback
from typing import TYPE_CHECKING

from config.logger import setup_logging
from core.providers.vad.base import VADProviderBase
import numpy as np
import opuslib_next
import torch

# 使用TYPE_CHECKING来避免循环导入
if TYPE_CHECKING:
    from core.session.session_context import SessionContext

TAG = __name__
logger = setup_logging()


class VADProvider(VADProviderBase):
    def __init__(self, config):
        """
        初始化Silero VAD服务提供者

        :param config: VAD配置字典，必须包含model_dir参数
        :raises FileNotFoundError: 当模型目录不存在或模型文件缺失时抛出
        """
        model_dir = config.get("model_dir")

        if not model_dir:
            raise ValueError("VAD配置中缺少model_dir参数")

        # 预先验证模型路径
        if not os.path.exists(model_dir):
            raise FileNotFoundError(
                f"VAD模型目录不存在: {model_dir}\n"
                f"当前工作目录: {os.getcwd()}\n"
                f"请检查配置文件中的 model_dir 路径是否正确"
            )

        hubconf_path = os.path.join(model_dir, "hubconf.py")
        if not os.path.exists(hubconf_path):
            raise FileNotFoundError(
                f"VAD模型文件缺失: {hubconf_path}\n"
                f"模型目录: {model_dir}\n"
                f"请确保模型文件完整下载，参考README中的模型下载说明"
            )

        # 模型路径验证通过后，加载模型
        try:
            self.model, self.utils = torch.hub.load(
                repo_or_dir=model_dir,
                source="local",
                model="silero_vad",
                force_reload=False,
            )
            (get_speech_timestamps, _, _, _, _) = self.utils
            logger.bind(tag=TAG).info(f"Silero VAD模型加载成功: {model_dir}")
        except Exception as e:
            error_msg = f"加载Silero VAD模型失败: {str(e)}\n模型路径: {model_dir}"
            logger.bind(tag=TAG).error(error_msg)
            raise RuntimeError(error_msg) from e

        self.decoder = opuslib_next.Decoder(16000, 1)
        self.vad_threshold = float(config.get("threshold", 0.5))

    def close(self):
        """显式清理opuslib_next.Decoder资源"""
        if hasattr(self, "decoder") and self.decoder is not None:
            try:
                # 重置解码器状态
                if hasattr(self.decoder, "reset_state"):
                    self.decoder.reset_state()
                # 清空引用
                self.decoder = None
                logger.bind(tag=TAG).debug("VAD Decoder资源已清理")
            except Exception as e:
                logger.bind(tag=TAG).debug(f"清理VAD Decoder资源时出错: {e}")
                # 即使出现异常也要清空引用
                self.decoder = None

    def __del__(self):
        """析构函数 - 备用清理机制"""
        try:
            if hasattr(self, "decoder") and self.decoder is not None:
                # 在析构函数中只清空引用，避免复杂操作
                self.decoder = None
        except Exception:
            # 在析构函数中避免任何可能的异常
            pass

    def is_vad(self, context: "SessionContext", pcm_frames: bytes) -> bool:
        """
        检测音频数据中的语音活动
        返回:
        - True: 检测到语音活动
        - False: 没有检测到语音活动
        """
        try:
            # 直接通过StateManager访问状态属性
            context.state_manager.asr_vad_buffer.extend(pcm_frames)

            # 从session配置中获取静默阈值（用于注释中的逻辑，当前未使用）
            # silence_threshold_ms = context.session_runtime_config.session_vad_config.silence_threshold_ms

            # 处理缓冲区中的完整帧（每次处理512采样点）
            vad_have_voice = False
            while len(context.state_manager.asr_vad_buffer) >= 512 * 2:
                # 提取前512个采样点（1024字节）
                chunk = context.state_manager.asr_vad_buffer[: 512 * 2]
                context.state_manager.asr_vad_buffer = context.state_manager.asr_vad_buffer[512 * 2 :]

                # 转换为模型需要的张量格式
                audio_int16 = np.frombuffer(chunk, dtype=np.int16)
                audio_float32 = audio_int16.astype(np.float32) / 32768.0
                audio_tensor = torch.from_numpy(audio_float32)

                # 检测语音活动
                with torch.no_grad():
                    speech_prob = self.model(audio_tensor, 16000).item()
                is_voice = speech_prob >= self.vad_threshold

                # 只有连续4帧检测到语音才认为有语音
                if is_voice:
                    context.state_manager.client_voice_frame_count += 1
                else:
                    context.state_manager.client_voice_frame_count = 0
                vad_have_voice = context.state_manager.client_voice_frame_count >= 4

            return vad_have_voice
        except opuslib_next.OpusError as e:
            logger.bind(tag=TAG).info(f"解码错误: {e}")
            return False
        except Exception:
            logger.bind(tag=TAG).error(f"人声识别失败: {traceback.format_exc()}")
            return False
