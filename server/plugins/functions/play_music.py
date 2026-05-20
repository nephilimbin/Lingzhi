import asyncio
import difflib
import os
from pathlib import Path
import random
import re
import time
import traceback

from config.logger import setup_logging
from core.models import Action, ActionResponse, ToolType
from core.providers.tts.base import TtsAudioResponseData
from core.registries import register_function
from core.session.session_context import SessionContext

TAG = __name__
logger = setup_logging()

MUSIC_CACHE = {}

play_music_function_desc = {
    "type": "function",
    "function": {
        "name": "play_music",
        "description": "唱歌、听歌、播放音乐的方法。",
        "parameters": {
            "type": "object",
            "properties": {
                "song_name": {
                    "type": "string",
                    "description": "歌曲名称，如果用户没有指定具体歌名则为'random', 明确指定的时返回音乐的名字 示例: ```用户:播放两只老虎\n参数：两只老虎``` ```用户:播放音乐 \n参数：random ```",
                },
                "music_title": {
                    "type": "string",
                    "description": "音乐标题或歌名，优先使用此参数。如果指定则播放对应歌曲，如果为空则随机播放",
                },
            },
            "required": [],
        },
    },
}


@register_function("play_music", play_music_function_desc, ToolType.SYSTEM_CTL)
def play_music(context: "SessionContext", song_name: str = "random", music_title: str = None):
    try:
        # 优先使用 music_title 参数，如果没有则使用 song_name
        actual_song_name = music_title if music_title else song_name
        music_intent = f"播放音乐 {actual_song_name}" if actual_song_name != "random" else "随机播放音乐"

        # 检查事件循环状态
        if not context.loop.is_running():
            logger.bind(tag=TAG).error("事件循环未运行，无法提交任务")
            return ActionResponse(action=Action.RESPONSE, result="系统繁忙", response="请稍后再试")

        # 提交异步任务
        future = asyncio.run_coroutine_threadsafe(handle_music_command(context, music_intent), context.loop)

        # 非阻塞回调处理
        def handle_done(f):
            try:
                f.result()  # 可在此处理成功逻辑
                logger.bind(tag=TAG).info("播放完成")
            except Exception as e:
                logger.bind(tag=TAG).error(f"播放失败: {e}")

        future.add_done_callback(handle_done)

        return ActionResponse(
            action=Action.RESPONSE,
            result="指令已接收",
            response="正在为您播放音乐",
        )
    except Exception as e:
        logger.bind(tag=TAG).error(f"处理音乐意图错误: {e}")
        return ActionResponse(action=Action.RESPONSE, result=str(e), response="播放音乐时出错了")


def _extract_song_name(text):
    """从用户输入中提取歌名"""
    for keyword in ["播放音乐"]:
        if keyword in text:
            parts = text.split(keyword)
            if len(parts) > 1:
                return parts[1].strip()
    return None


def _find_best_match(potential_song, music_files):
    """查找最匹配的歌曲"""
    best_match = None
    highest_ratio = 0

    for music_file in music_files:
        song_name = os.path.splitext(music_file)[0]
        ratio = difflib.SequenceMatcher(None, potential_song, song_name).ratio()
        if ratio > highest_ratio and ratio > 0.4:
            highest_ratio = ratio
            best_match = music_file
    return best_match


def get_music_files(music_dir, music_ext):
    music_dir = Path(music_dir)
    music_files = []
    music_file_names = []
    for file in music_dir.rglob("*"):
        # 判断是否是文件
        if file.is_file():
            # 获取文件扩展名
            ext = file.suffix.lower()
            # 判断扩展名是否在列表中
            if ext in music_ext:
                # 添加相对路径
                music_files.append(str(file.relative_to(music_dir)))
                music_file_names.append(os.path.splitext(str(file.relative_to(music_dir)))[0])
    logger.bind(tag=TAG).info(f"找到的音乐文件: {music_files}")
    return music_files, music_file_names


def initialize_music_handler(context: "SessionContext"):
    global MUSIC_CACHE
    if MUSIC_CACHE == {}:
        if "play_music" in context.config["function_plugins"]:
            MUSIC_CACHE["music_config"] = context.config["function_plugins"]["play_music"]
            MUSIC_CACHE["music_dir"] = os.path.abspath(
                MUSIC_CACHE["music_config"].get("music_dir", "./music")  # 默认路径修改
            )
            MUSIC_CACHE["music_ext"] = MUSIC_CACHE["music_config"].get("music_ext", (".mp3", ".wav", ".p3"))
            MUSIC_CACHE["refresh_time"] = MUSIC_CACHE["music_config"].get("refresh_time", 60)
        else:
            MUSIC_CACHE["music_dir"] = os.path.abspath("./music")
            MUSIC_CACHE["music_ext"] = (".mp3", ".wav", ".p3")
            MUSIC_CACHE["refresh_time"] = 60
        # 获取音乐文件列表
        MUSIC_CACHE["music_files"], MUSIC_CACHE["music_file_names"] = get_music_files(
            MUSIC_CACHE["music_dir"], MUSIC_CACHE["music_ext"]
        )
        MUSIC_CACHE["scan_time"] = time.time()
    return MUSIC_CACHE


async def handle_music_command(context: "SessionContext", text):
    initialize_music_handler(context)
    global MUSIC_CACHE

    """处理音乐播放指令"""
    clean_text = re.sub(r"[^\w\s]", "", text).strip()
    logger.bind(tag=TAG).debug(f"检查是否是音乐命令: {clean_text}")

    # 尝试匹配具体歌名
    if os.path.exists(MUSIC_CACHE["music_dir"]):
        if time.time() - MUSIC_CACHE["scan_time"] > MUSIC_CACHE["refresh_time"]:
            # 刷新音乐文件列表
            MUSIC_CACHE["music_files"], MUSIC_CACHE["music_file_names"] = get_music_files(
                MUSIC_CACHE["music_dir"], MUSIC_CACHE["music_ext"]
            )
            MUSIC_CACHE["scan_time"] = time.time()

        potential_song = _extract_song_name(clean_text)
        if potential_song:
            best_match = _find_best_match(potential_song, MUSIC_CACHE["music_files"])
            if best_match:
                logger.bind(tag=TAG).info(f"找到最匹配的歌曲: {best_match}")
                await play_local_music(context, specific_file=best_match)
                return True
    # 检查是否是通用播放音乐命令
    await play_local_music(context)
    return True


async def play_local_music(context: "SessionContext", specific_file=None):
    global MUSIC_CACHE
    """播放本地音乐文件"""
    try:
        if not os.path.exists(MUSIC_CACHE["music_dir"]):
            logger.bind(tag=TAG).error("音乐目录不存在: " + MUSIC_CACHE["music_dir"])
            return

        # 确保路径正确性
        if specific_file:
            selected_music = specific_file
            music_path = os.path.join(MUSIC_CACHE["music_dir"], specific_file)
        else:
            if not MUSIC_CACHE["music_files"]:
                logger.bind(tag=TAG).error("未找到MP3音乐文件")
                return
            selected_music = random.choice(MUSIC_CACHE["music_files"])
            music_path = os.path.join(MUSIC_CACHE["music_dir"], selected_music)

        if not os.path.exists(music_path):
            logger.bind(tag=TAG).error(f"选定的音乐文件不存在: {music_path}")
            return
        text = f"正在播放{selected_music}"
        await context.output_processor.send_stt_message(text)

        # 通过StateManager更新状态
        context.state_manager.update_state(
            llm_first_text_index=0,
            llm_last_text_index=0,
            llm_finish_task=True,
        )

        # 启动tts_pipeline异步任务，确保音频发送循环在运行
        context.tts_pipeline.start_tts_pipeline_threads()
        logger.bind(tag=TAG).info("已启动tts_pipeline异步任务")

        if music_path.endswith(".p3"):
            # 对于.p3文件，需要先解码为PCM数据
            # 暂时跳过.p3文件处理，或者需要添加Opus到PCM的解码逻辑
            logger.bind(tag=TAG).warning("P3文件格式需要先解码为PCM，当前暂不支持")
            return
        else:
            logger.bind(tag=TAG).info(f"开始处理音乐文件: {music_path}")
            # 读取音频文件为原始PCM，保持原始采样率
            # 不在这里做采样率转换，让 tts_pipeline 统一处理
            try:
                from pydub import AudioSegment

                # 读取音频文件但保持原始采样率
                file_type = os.path.splitext(music_path)[1].lstrip(".")
                audio = AudioSegment.from_file(music_path, format=file_type or "mp3", parameters=["-nostdin"])

                # 转换为单声道和16位，但保持原始采样率
                audio = audio.set_channels(1).set_sample_width(2)
                original_sample_rate = audio.frame_rate

                logger.bind(tag=TAG).info(
                    f"音频文件信息 - 原始采样率: {original_sample_rate}Hz, 通道: {audio.channels}, 比特深度: {audio.sample_width * 8}"
                )

                # 转换为PCM数据
                audio_pcm = audio.raw_data
                logger.bind(tag=TAG).info(f"成功读取音频文件，PCM数据大小: {len(audio_pcm)} 字节")

            except Exception as e:
                logger.bind(tag=TAG).error(f"使用pydub读取失败，尝试备用方法: {e}")
                # 备用方法：使用 read_file_to_pcm（它会转换为16kHz）
                audio_pcm = context.tts.pcm_handler.read_file_to_pcm(music_path)
                original_sample_rate = 16000
                logger.bind(tag=TAG).warning("使用了备用读取方法，音频已被转换为16kHz")

            if not audio_pcm:
                logger.bind(tag=TAG).error("音频文件读取失败或为空")
                return

            # 检查音频大小，如果过大则警告
            audio_size_mb = len(audio_pcm) / (1024 * 1024)
            if audio_size_mb > 10:
                logger.bind(tag=TAG).warning(f"音频文件较大: {audio_size_mb:.2f}MB，可能会影响性能")
            else:
                logger.bind(tag=TAG).debug(f"音频文件大小: {audio_size_mb:.2f}MB")

            # 检查是否需要分块发送（1MB阈值）
            chunk_size_threshold = 1 * 1024 * 1024  # 1MB

            if len(audio_pcm) > chunk_size_threshold:
                # 大文件需要分块处理
                logger.bind(tag=TAG).info(
                    f"音频文件超过阈值 ({len(audio_pcm) / (1024 * 1024):.2f}MB > 1MB)，将分块发送"
                )
                await _send_audio_in_chunks(context, audio_pcm, original_sample_rate)
            else:
                # 小文件直接发送
                context.tts_pipeline.audio_play_queue.put_nowait(
                    TtsAudioResponseData(
                        pcm_bytes=audio_pcm,
                        text_index=0,
                        pcm_is_complete=True,
                        pcm_sample_rate=original_sample_rate,  # 使用原始采样率
                    )
                )

                logger.bind(tag=TAG).info(
                    f"音频数据已加入队列 - "
                    f"大小: {len(audio_pcm)} bytes, "
                    f"采样率: {original_sample_rate}Hz, "
                    f"预计播放时长: {len(audio_pcm) / (original_sample_rate * 2):.2f}秒"
                )

    except Exception:
        logger.bind(tag=TAG).error(f"播放音乐失败: {traceback.format_exc()}")


async def _send_audio_in_chunks(context: "SessionContext", audio_pcm: bytes, sample_rate: int):
    """
    将音频数据分块发送，避免OpusEncoder处理过大的数据块

    Args:
        context: SessionContext实例
        audio_pcm: PCM音频数据
        sample_rate: 音频采样率
    """
    try:
        # 计算分块大小：约8秒的音频数据（约256KB at 32kHz）
        # 每秒音频数据大小 = sample_rate * 2 bytes (16-bit)
        chunk_duration_seconds = 8
        bytes_per_second = sample_rate * 2  # 16-bit音频
        chunk_size = chunk_duration_seconds * bytes_per_second

        # 限制最大块大小为512KB，防止过大
        max_chunk_size = 512 * 1024
        chunk_size = min(chunk_size, max_chunk_size)

        total_size = len(audio_pcm)
        chunk_count = (total_size + chunk_size - 1) // chunk_size  # 向上取整

        logger.bind(tag=TAG).info(
            f"准备分块发送音频 - "
            f"总大小: {total_size / (1024 * 1024):.2f}MB, "
            f"块大小: {chunk_size / 1024:.0f}KB, "
            f"分块数: {chunk_count}, "
            f"采样率: {sample_rate}Hz"
        )

        # 分块发送
        for i in range(chunk_count):
            start_pos = i * chunk_size
            end_pos = min(start_pos + chunk_size, total_size)
            chunk_data = audio_pcm[start_pos:end_pos]

            # 判断是否为最后一块
            is_last_chunk = i == chunk_count - 1

            # 创建TtsAudioResponseData对象
            audio_chunk = TtsAudioResponseData(
                pcm_bytes=chunk_data,
                text_index=i,  # 使用索引作为text_index
                pcm_is_complete=is_last_chunk,  # 只有最后一块标记为complete
                pcm_sample_rate=sample_rate,  # 保持原始采样率
            )

            # 发送分块到队列
            context.tts_pipeline.audio_play_queue.put_nowait(audio_chunk)

            logger.bind(tag=TAG).debug(
                f"发送音频分块 {i + 1}/{chunk_count} - 大小: {len(chunk_data) / 1024:.0f}KB, 最后一块: {is_last_chunk}"
            )

            # 在分块之间添加小延迟，防止过载
            if not is_last_chunk:
                await asyncio.sleep(0.1)  # 100ms延迟

        logger.bind(tag=TAG).info(f"音频分块发送完成，共 {chunk_count} 块")

    except Exception:
        logger.bind(tag=TAG).error(f"分块发送音频失败: {traceback.format_exc()}")
