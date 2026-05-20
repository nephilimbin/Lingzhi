import io
import os
import sys
import time
from typing import List
import wave

from config.logger import setup_logging
from core.models.asr_models import ASRResponseInfo
from core.providers.asr.base import ASRProviderBase
from core.utils.util import set_unique_id
from funasr import AutoModel
from funasr.utils.postprocess_utils import rich_transcription_postprocess
import opuslib_next

TAG = __name__
logger = setup_logging()


# 捕获标准输出
class CaptureOutput:
    def __enter__(self):
        self._output = io.StringIO()
        self._original_stdout = sys.stdout
        sys.stdout = self._output

    def __exit__(self, exc_type, exc_value, traceback):
        sys.stdout = self._original_stdout
        self.output = self._output.getvalue()
        self._output.close()

        # 将捕获到的内容通过 logger 输出
        if self.output:
            logger.bind(tag=TAG).info(self.output.strip())


class ASRProvider(ASRProviderBase):
    def __init__(self, config: dict):
        super().__init__()  # 调用父类构造函数
        self.model_dir = config.get("model_dir")

        with CaptureOutput():
            self.model = AutoModel(
                model=self.model_dir,  # 使用动态计算的绝对路径
                vad_kwargs={"max_single_segment_time": 30000},
                disable_update=True,
                hub="hf",
                # device="cuda:0",  # 启用GPU加速
            )

    def save_audio_to_file(self, opus_data: List[bytes], session_id: str) -> str:
        """将Opus音频数据解码并保存为WAV文件"""
        file_name = set_unique_id(f"asr_{session_id}") + ".wav"
        # 优先使用session输出目录，如果没有设置则使用配置的目录
        output_dir = self.output_dir
        os.makedirs(output_dir, exist_ok=True)
        file_path = os.path.join(output_dir, file_name)

        decoder = opuslib_next.Decoder(16000, 1)  # 16kHz, 单声道
        pcm_data = []

        for opus_packet in opus_data:
            try:
                pcm_frame = decoder.decode(opus_packet, 960)  # 960 samples = 60ms
                pcm_data.append(pcm_frame)
            except opuslib_next.OpusError as e:
                logger.bind(tag=TAG).error(f"Opus解码错误: {e}", exc_info=True)

        with wave.open(file_path, "wb") as wf:
            wf.setnchannels(1)
            wf.setsampwidth(2)  # 2 bytes = 16-bit
            wf.setframerate(16000)
            wf.writeframes(b"".join(pcm_data))

        return file_path

    async def speech_to_text(self, opus_data: List[bytes], session_id: str) -> ASRResponseInfo:
        """语音转文本主处理逻辑"""
        file_path = None
        try:
            # 保存音频文件
            start_time = time.time()
            file_path = self.save_audio_to_file(opus_data, session_id)
            logger.bind(tag=TAG).debug(f"保存音频文件: {file_path}")

            # 语音识别
            result = self.model.generate(
                input=file_path,
                cache={},
                language="auto",
                use_itn=True,
                batch_size_s=60,
            )
            text = rich_transcription_postprocess(result[0]["text"])
            processing_time = time.time() - start_time
            logger.bind(tag=TAG).debug(f"语音识别耗时: {processing_time:.3f}s | 结果: {text}")

            return ASRResponseInfo(text=text, is_final=True, audio_file_path=file_path, provider_name="funasr_local")

        except Exception as e:
            logger.bind(tag=TAG).error(f"语音识别失败: {e}", exc_info=True)
            return ASRResponseInfo(text="", is_final=True, provider_name="funasr_local")
