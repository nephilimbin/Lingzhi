"""
调用栈跟踪装饰器 - 用于调试和监控函数调用来源
"""

import inspect
import functools
from typing import Callable, Any, Optional
from config.logger import setup_logging


def with_call_stack(stack_depth: int = 3, include_caller_stack: bool = True, log_calls: bool = False, logger_tag: Optional[str] = None):
    """
    调用栈跟踪装饰器

    Args:
        stack_depth: 获取调用栈的深度，默认3层
        include_caller_stack: 是否将caller_stack作为参数传递给被装饰函数（可选参数）
        log_calls: 是否自动记录函数调用日志
        logger_tag: 日志标签，如果不指定则使用函数所在模块名
    """

    def decorator(func: Callable) -> Callable:
        @functools.wraps(func)
        async def async_wrapper(*args, **kwargs):
            # 获取调用栈信息
            caller_info = []
            stack_frames = inspect.stack()[1 : stack_depth + 1]  # 跳过当前装饰器frame

            for frame_info in stack_frames:
                caller_info.append(f"{frame_info.filename.split('/')[-1]}:{frame_info.function}:{frame_info.lineno}")

            caller_stack = " <- ".join(caller_info)

            # 将调用栈存储到函数的局部属性中，函数内部可以通过 func._caller_stack 访问
            func._caller_stack = caller_stack

            # 如果需要记录调用日志
            if log_calls:
                logger = setup_logging()
                tag = logger_tag or func.__module__
                logger.bind(tag=tag).debug(f"调用 {func.__name__}, 调用栈: {caller_stack}")

            # 如果需要将调用栈传递给函数（仅当函数签名中有caller_stack参数时）
            if include_caller_stack:
                sig = inspect.signature(func)
                if "caller_stack" in sig.parameters:
                    kwargs["caller_stack"] = caller_stack

            # 调用原函数
            try:
                if inspect.iscoroutinefunction(func):
                    return await func(*args, **kwargs)
                else:
                    return func(*args, **kwargs)
            finally:
                # 清理临时属性
                if hasattr(func, "_caller_stack"):
                    delattr(func, "_caller_stack")

        @functools.wraps(func)
        def sync_wrapper(*args, **kwargs):
            # 获取调用栈信息
            caller_info = []
            stack_frames = inspect.stack()[1 : stack_depth + 1]  # 跳过当前装饰器frame

            for frame_info in stack_frames:
                caller_info.append(f"{frame_info.filename.split('/')[-1]}:{frame_info.function}:{frame_info.lineno}")

            caller_stack = " <- ".join(caller_info)

            # 将调用栈存储到函数的局部属性中
            func._caller_stack = caller_stack

            # 如果需要记录调用日志
            if log_calls:
                logger = setup_logging()
                tag = logger_tag or func.__module__
                logger.bind(tag=tag).debug(f"调用 {func.__name__}, 调用栈: {caller_stack}")

            # 如果需要将调用栈传递给函数（仅当函数签名中有caller_stack参数时）
            if include_caller_stack:
                sig = inspect.signature(func)
                if "caller_stack" in sig.parameters:
                    kwargs["caller_stack"] = caller_stack

            # 调用原函数
            try:
                return func(*args, **kwargs)
            finally:
                # 清理临时属性
                if hasattr(func, "_caller_stack"):
                    delattr(func, "_caller_stack")

        # 根据函数类型返回对应的包装器
        if inspect.iscoroutinefunction(func):
            return async_wrapper
        else:
            return sync_wrapper

    return decorator


def get_caller_stack(depth: int = 3) -> str:
    """
    直接获取调用栈字符串的工具函数

    Args:
        depth: 获取调用栈的深度，默认3层

    Returns:
        调用栈字符串
    """
    caller_info = []
    stack_frames = inspect.stack()[1 : depth + 1]  # 跳过当前函数frame

    for frame_info in stack_frames:
        caller_info.append(f"{frame_info.filename.split('/')[-1]}:{frame_info.function}:{frame_info.lineno}")

    return " <- ".join(caller_info)


# 一些预定义的装饰器配置


def log_calls(stack_depth: int = 2, logger_tag: Optional[str] = None):
    """
    最简单的装饰器：只记录调用日志，不需要修改函数签名
    推荐用于大部分场景
    """
    return with_call_stack(
        stack_depth=stack_depth,
        include_caller_stack=False,  # 不传递参数
        log_calls=True,
        logger_tag=logger_tag,
    )


def debug_calls(stack_depth: int = 3):
    """调试模式装饰器，会自动记录调用日志和传递调用栈（如果函数有caller_stack参数）"""
    return with_call_stack(stack_depth=stack_depth, include_caller_stack=True, log_calls=True)
