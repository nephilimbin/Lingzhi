#!/bin/bash
# Mobile Nika Server 启动脚本
#
# 说明: 此脚本临时设置 DYLD_LIBRARY_PATH 环境变量以支持 libopus
#       - 只影响本脚本启动的服务进程
#       - 不影响其他终端会话
#       - 不会导致 Playwright Chromium 崩溃
#
# 如果需要同时运行 playwright，请在不同的终端窗口中执行，互不影响。

cd "$(dirname "$0")"
DYLD_LIBRARY_PATH=/opt/homebrew/lib uv run python app.py
