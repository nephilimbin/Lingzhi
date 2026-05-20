"""
适配器模块

提供各种协议和库的适配器，统一接口使用。
"""

from .websocket_adapter import WebSocketAdapter, create_websocket_adapter

__all__ = ["WebSocketAdapter", "create_websocket_adapter"]