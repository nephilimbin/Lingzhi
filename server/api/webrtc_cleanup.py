"""
WebRTC清理模块

提供WebRTC连接清理功能，确保正确关闭所有aioice相关资源，
避免STUN事务重试异常。
"""

import asyncio

from aiortc import RTCPeerConnection
from config.logger import setup_logging

TAG = __name__
logger = setup_logging()


class WebRTCCleanup:
    """
    WebRTC清理管理

    提供WebRTC资源清理功能，确保：
    1. RTCPeerConnection完全关闭
    2. 取消所有aioice相关任务
    3. 清理STUN事务重试机制
    """

    @staticmethod
    async def close_peer_connection_safely(pc: RTCPeerConnection, webrtc_id: str) -> None:
        """
        安全地关闭RTCPeerConnection，确保所有相关资源都被正确清理

        Args:
            pc: RTCPeerConnection实例
            webrtc_id: WebRTC连接ID
        """
        if not pc:
            return

        try:
            logger.bind(tag=TAG).info(f"开始关闭RTCPeerConnection: {webrtc_id}")

            # 1. 首先设置连接状态为closed
            if pc.connectionState != "closed":
                await pc.close()

            # 2. 等待一小段时间确保关闭操作完成
            await asyncio.sleep(0.1)

            # 3. 取消所有与aioice相关的任务
            await WebRTCCleanup._cancel_aioice_tasks(webrtc_id)

            logger.bind(tag=TAG).info(f"RTCPeerConnection已安全关闭: {webrtc_id}")

        except Exception as e:
            logger.bind(tag=TAG).error(f"关闭RTCPeerConnection时出错: {e}", exc_info=True)

    @staticmethod
    async def _cancel_aioice_tasks(webrtc_id: str) -> None:
        """
        取消所有与aioice相关的任务

        Args:
            webrtc_id: WebRTC连接ID
        """
        try:
            current_task = asyncio.current_task()
            all_tasks = [t for t in asyncio.all_tasks() if t is not current_task]

            cancelled_count = 0
            for task in all_tasks:
                coro = task.get_coro()
                if coro and (
                    "Transaction.__retry" in str(coro) or "aioice" in str(coro) or webrtc_id in str(task.get_name())
                ):
                    if not task.done() and not task.cancelled():
                        logger.bind(tag=TAG).debug(f"取消aioice任务: {task.get_name()}")
                        task.cancel()
                        cancelled_count += 1
                        try:
                            await task
                        except asyncio.CancelledError:
                            pass
                        except Exception as e:
                            logger.bind(tag=TAG).warning(f"取消任务时出错: {e}")

            if cancelled_count > 0:
                logger.bind(tag=TAG).info(f"已取消 {cancelled_count} 个aioice相关任务")

        except Exception as e:
            logger.bind(tag=TAG).error(f"取消aioice任务时出错: {e}", exc_info=True)

    @staticmethod
    def create_enhanced_cleanup_method(original_cleanup, pcs: dict) -> callable:
        """
        创建增强的清理方法，包装原始的clean_up方法

        Args:
            original_cleanup: 原始的clean_up方法
            pcs: PeerConnection字典

        Returns:
            增强的清理方法
        """

        def enhanced_cleanup(webrtc_id: str):
            try:
                # 1. 获取并关闭PeerConnection
                pc = pcs.get(webrtc_id)
                if pc:
                    # 安全地获取或创建事件循环
                    try:
                        loop = asyncio.get_event_loop()
                    except RuntimeError:
                        # 如果没有事件循环，尝试创建一个
                        loop = asyncio.new_event_loop()
                        asyncio.set_event_loop(loop)

                    # 创建异步任务来关闭PC
                    asyncio.create_task(WebRTCCleanup.close_peer_connection_safely(pc, webrtc_id))

                # 2. 调用原始的清理方法
                connection = original_cleanup(webrtc_id)

                # 3. 异步取消aioice相关任务（使用后台任务避免阻塞）
                try:
                    loop = asyncio.get_event_loop()
                except RuntimeError:
                    loop = asyncio.new_event_loop()
                    asyncio.set_event_loop(loop)

                # 如果循环正在运行，创建任务
                if loop.is_running():
                    asyncio.create_task(WebRTCCleanup._cancel_aioice_tasks(webrtc_id))
                else:
                    # 如果循环没有运行，运行任务
                    loop.run_until_complete(WebRTCCleanup._cancel_aioice_tasks(webrtc_id))

                return connection

            except Exception as e:
                logger.bind(tag=TAG).error(f"增强清理时出错: {e}", exc_info=True)
                # 即使出错也尝试调用原始清理方法
                return original_cleanup(webrtc_id)

        return enhanced_cleanup

    @staticmethod
    def patch_stream_clean_up(stream_instance):
        """
        动态修补Stream类的clean_up方法

        Args:
            stream_instance: Stream实例
        """
        if hasattr(stream_instance, "_clean_up_patched"):
            # 已经修补过，避免重复修补
            return

        # 保存原始方法
        original_cleanup = stream_instance.clean_up

        # 创建增强方法
        enhanced_cleanup = WebRTCCleanup.create_enhanced_cleanup_method(original_cleanup, stream_instance.pcs)

        # 替换方法
        stream_instance.clean_up = enhanced_cleanup
        stream_instance._clean_up_patched = True

        logger.bind(tag=TAG).info("Stream的clean_up方法已修补为增强版本")
