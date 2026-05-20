import asyncio
import os
import random
import shutil
import time
from typing import TYPE_CHECKING, Optional

from core.models import Action, ActionResponse
from core.providers.tts.base import TtsAudioResponseData
from core.utils.util import remove_punctuation_and_length

if TYPE_CHECKING:
    from core.session.session_context import SessionContext

TAG = __name__


class WakeupProcessor:
    """唤醒词处理器

    负责语音助手的唤醒检测和响应管理，包括唤醒词识别、音频响应生成、缓存管理等功能。

    职责：
    - 检测用户输入中的唤醒词并触发助手激活状态
    - 管理唤醒词响应音频的生成、缓存和播放
    - 实现动态唤醒词响应生成，提供自然的交互体验
    - 管理响应音频文件的生命周期和缓存机制
    - 支持多种唤醒词配置和自定义响应内容

    组件关系：
    - 依赖SessionContext获取TTS服务、状态管理器和配置
    - 使用TTS服务生成唤醒词响应音频
    - 通过StateManager设置会话状态标志
    - 与文件系统交互管理音频缓存文件
    - 利用LLM生成动态的唤醒词响应内容
    """

    def __init__(self, context: "SessionContext"):
        """
        初始化唤醒词处理器

        :param context: 会话上下文，提供TTS服务、日志记录器等必要依赖
        """
        self.context = context
        self.logger = context.logger
        self.session_request_id = ""
        self._create_time = 0.0  # 当前响应音频的创建时间
        self._refresh_time = 3600  # 响应音频的刷新间隔时间（1小时）
        self._text = ""  # 当前唤醒词响应的文本内容

        self.logger.bind(tag=TAG).info("唤醒词处理器初始化完成")

    @property
    def create_time(self) -> float:
        """
        获取当前响应音频的创建时间
        :return: 创建时间戳（秒）
        """
        return self._create_time

    @property
    def refresh_time(self) -> int:
        """
        获取响应音频的刷新间隔时间
        :return: 刷新间隔（秒）
        """
        return self._refresh_time

    @property
    def text(self) -> str:
        """
        获取当前唤醒词响应的文本内容
        :return: 响应文本
        """
        return self._text

    @text.setter
    def text(self, value: str):
        """
        设置唤醒词响应的文本内容
        :param value: 新的响应文本内容
        """
        self._text = value

    async def process_wakeup_detection(self, text: str) -> Optional[ActionResponse]:
        """
        处理唤醒词检测的主要入口方法
        :param text: 用户输入的文本内容
        :return: 检测到唤醒词时返回ActionResponse，否则返回None
        """
        try:
            is_wakeup = await self.check_wakeup_words(text)
            if is_wakeup:
                self.logger.bind(tag=TAG).info(f"检测到唤醒词: {text}")
                return ActionResponse(action=Action.NONE, result="唤醒词检测", response="")
            return None
        except Exception as e:
            self.logger.bind(tag=TAG).error(f"唤醒词检测处理失败: {e}")
            return None

    async def check_wakeup_words(self, text: str) -> bool:
        """
        检查文本是否包含唤醒词并执行相应的唤醒响应
        :param text: 用户输入的文本内容
        :return: 检测到唤醒词返回True，否则返回False
        """
        intent_config = self.context.session_runtime_config.session_intent_config
        enable_wakeup_words_response = intent_config.enable_wakeup_words_response
        wakeup_words = intent_config.wakeup_words

        if not enable_wakeup_words_response:
            return False

        _, processed_text = remove_punctuation_and_length(text)
        if processed_text in wakeup_words:
            # 通过StateManager设置唤醒状态和任务完成标志
            if self.context.state_manager:
                self.context.state_manager.update_state(
                    llm_first_text_index=0,
                    llm_last_text_index=0,
                    llm_finish_task=True,
                )
            else:
                self.logger.bind(tag=TAG).warning("StateManager不可用，无法设置唤醒词状态")

            voice_file_path = intent_config.wakeup_words_notify_voice
            cached_file = self.get_wakeup_wordfile(voice_file_path)
            if cached_file is None:
                # 无缓存文件，触发异步生成新的响应音频
                asyncio.create_task(self.wakeup_words_response())
                return False

            audio_pcm = self.context.tts.pcm_handler.read_file_to_pcm(cached_file)
            _response_text = self.text if self.text else text

            # 分块发送音频数据，避免单个数据包过大
            chunk_size = 4096
            total_chunks = (len(audio_pcm) + chunk_size - 1) // chunk_size

            for i in range(total_chunks):
                start = i * chunk_size
                end = min((i + 1) * chunk_size, len(audio_pcm))
                pcm_chunk = audio_pcm[start:end]
                is_complete = i == total_chunks - 1

                self.context.tts_pipeline.audio_play_queue.put_nowait(
                    TtsAudioResponseData(pcm_bytes=pcm_chunk, text_index=0, pcm_is_complete=is_complete)
                )

            # 检查是否需要刷新响应内容
            if time.time() - self.create_time > self.refresh_time:
                asyncio.create_task(self.wakeup_words_response())

            return True

        return False

    def get_wakeup_wordfile(self, file_path: str) -> Optional[str]:
        """
        获取唤醒词音频文件路径
        :param file_path: 音频文件路径或文件名
        :return: 找到的文件路径，如果未找到返回None
        """
        assets_dir = "config/assets/"

        if file_path and os.path.exists(file_path):
            return file_path

        if file_path and not file_path.startswith(assets_dir):
            full_path = os.path.join(assets_dir, file_path)
            if os.path.exists(full_path):
                return full_path

        if file_path:
            file_name = os.path.basename(file_path)
            for file in os.listdir(assets_dir):
                if file.startswith("my_" + file_name):
                    full_file_path = os.path.join(assets_dir, file)
                    # 避免缓存文件过小（空文件或损坏文件）
                    if os.stat(full_file_path).st_size > (15 * 1024):
                        return full_file_path

            for file in os.listdir(assets_dir):
                if file.startswith(file_name):
                    return os.path.join(assets_dir, file)

        return None

    async def wakeup_words_response(self) -> None:
        """
        生成唤醒词响应音频文件
        随机选择一个唤醒词并生成对应的TTS音频文件，用于后续唤醒词检测时的语音响应
        """
        wait_max_time = 5
        while self.context.llm is None or not self.context.llm.chat_completion:
            await asyncio.sleep(1)
            wait_max_time -= 1
            if wait_max_time <= 0:
                self.logger.bind(tag=TAG).error("连接对象没有llm")
                return

        intent_config = self.context.session_runtime_config.session_intent_config
        wakeup_words = intent_config.wakeup_words
        if not wakeup_words:
            self.logger.bind(tag=TAG).error("没有配置唤醒词")
            return

        wakeup_word = random.choice(wakeup_words)
        dialogue = [
            {"role": "system", "content": self.context.config["prompt"]},
            {"role": "user", "content": wakeup_word},
        ]
        response_info = next(self.context.llm.chat_completion(dialogue))

        if not response_info:
            self.logger.bind(tag=TAG).error(f"唤醒词响应生成失败: {response_info.error}")
            return

        result = response_info.content
        tts_file = await asyncio.to_thread(self.context.tts.text_to_speech, result)

        if tts_file is not None and os.path.exists(tts_file):
            file_type = os.path.splitext(tts_file)[1]
            if file_type:
                file_type = file_type.lstrip(".")

            # 删除旧的缓存文件
            original_voice_file = intent_config.wakeup_words_notify_voice
            if original_voice_file:
                file_name = os.path.basename(original_voice_file)
                old_file = self.get_wakeup_wordfile("my_" + file_name)
                if old_file is not None:
                    os.remove(old_file)

            # 移动新生成的音频文件到assets目录
            assets_dir = "config/assets/"
            new_filename = "wakeup_words." + file_type
            shutil.move(
                tts_file,
                os.path.join(assets_dir, new_filename),
            )
            self._create_time = time.time()
            self.text = result
