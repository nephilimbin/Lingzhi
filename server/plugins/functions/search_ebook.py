"""
Z-Library 电子书搜索函数插件

在 Z-Library 电子书库中搜索书籍，返回书籍链接和相关信息。
支持无头模式自动登录和会话状态管理。
"""

from __future__ import annotations

import asyncio
import json
import os
import platform
import re
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from config.logger import setup_logging
from core.models import Action, ActionResponse, ToolType
from core.registries import register_function

try:
    from playwright.async_api import Browser, async_playwright
except ImportError:
    async_playwright = None  # type: ignore
    Browser = Any  # type: ignore

TAG = __name__
logger = setup_logging()

# ============== 静态配置参数 ==============
CONFIG_DIR = Path(__file__).parent / ".search_ebook"
STORAGE_STATE = CONFIG_DIR / "storage_state.json"

# 检测Chrome路径（Docker容器中不指定，让Playwright自动使用已安装的Chromium）
CHROME_PATH = None
if platform.system() == "Darwin" and os.path.exists("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"):
    CHROME_PATH = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
elif os.path.exists("/home/appuser/.cache/ms-playwright"):
    # Docker环境，使用Playwright安装的Chromium
    CHROME_PATH = None


def _get_config(conn, key: str, default=None):
    """从配置中获取 search_ebook 的配置项"""
    try:
        if hasattr(conn, "config"):
            ebook_config = conn.config.get("function_plugins", {}).get("search_ebook", {})
            return ebook_config.get(key, default)
    except Exception:
        pass
    return default


def _get_domains(conn) -> list[str]:
    """获取 Z-Library 域名列表"""
    domains = _get_config(conn, "domains")
    if isinstance(domains, list):
        return domains
    return []


def _get_credentials(conn) -> tuple[str, str]:
    """获取登录凭据 (email, password)"""
    email = _get_config(conn, "email", "")
    password = _get_config(conn, "password", "")
    return email, password


# 登录相关选择器
SELECTORS = {
    "login_trigger": 'a[data-action="login"], a[href*="/login"]',
    "login_form": "#loginForm",
    "email_input": '#loginForm input[name="email"]',
    "password_input": '#loginForm input[name="password"]',
    "submit_button": '#loginForm button[type="submit"]',
    "logged_out_indicator": ".navigation-user-card-element.not-logged",
    "logged_in_indicator": ".navigation-user-card-element:not(.not-logged)",
    "error_message": ".form-error, .validation-error",
}


async def _launch_browser_for_download(playwright, config_dir: Path, accept_downloads: bool = False) -> Browser | None:
    """
    启动浏览器（公共方法，用于搜索和下载）

    Args:
        playwright: Playwright 实例
        config_dir: 配置目录
        accept_downloads: 是否接受下载

    Returns:
        Browser 实例或 None
    """
    try:
        browser = await playwright.chromium.launch_persistent_context(
            executable_path=CHROME_PATH,
            user_data_dir=str(config_dir / "browser_profile"),
            headless=True,
            accept_downloads=accept_downloads,
            args=["--disable-blink-features=AutomationControlled"],
        )
        return browser
    except Exception as e:
        logger.bind(tag=TAG).error(f"启动浏览器失败: {e}")
        return None


# ========================================


SEARCH_EBOOK_FUNCTION_DESC = {
    "type": "function",
    "function": {
        "name": "search_ebook",
        "description": (
            "在电子书库中搜索书籍资源，返回书籍详情链接。"
            "适用场景：用户想搜索电子书、PDF、EPUB 等阅读资源。"
            "搜索结果包含：书名、作者、格式、文件大小、出版年份。"
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "要搜索的书籍关键词（书名、作者等）",
                },
                "limit": {
                    "type": "integer",
                    "description": "最多返回的结果条数，默认 10",
                },
            },
            "required": ["query"],
        },
    },
}


def _run_async(coro):
    """
    在线程池中运行异步协程

    解决 asyncio.run() 不能在运行中的事件循环调用的问题。
    当已有事件循环运行时，创建新线程和新事件循环执行协程。

    Args:
        coro: 异步协程对象

    Returns:
        协程的返回值

    Raises:
        Exception: 协程执行过程中的任何异常
    """
    try:
        loop = asyncio.get_running_loop()
    except RuntimeError:
        # 没有运行中的事件循环，直接使用 asyncio.run()
        return asyncio.run(coro)

    # 有运行中的事件循环，在新线程中创建新事件循环执行
    result = None
    exception = None

    def run_in_new_loop():
        nonlocal result, exception
        try:
            new_loop = asyncio.new_event_loop()
            asyncio.set_event_loop(new_loop)
            result = new_loop.run_until_complete(coro)
        except Exception as e:
            exception = e
        finally:
            new_loop.close()

    thread = threading.Thread(target=run_in_new_loop)
    thread.start()
    thread.join()

    if exception:
        raise exception
    return result


def _check_login() -> bool:
    """检查是否已登录（会话状态文件是否存在且有效）"""
    if not STORAGE_STATE.exists():
        return False
    try:
        content = STORAGE_STATE.read_text()
        if not content.strip():
            return False
        json.loads(content)
        return True
    except Exception:
        return False


async def _send_progress(conn, message: str) -> None:
    """向前端发送进度消息"""
    try:
        if conn and hasattr(conn, "loop") and conn.loop:
            asyncio.run_coroutine_threadsafe(
                conn.output_processor.send_llm_stream_response_message(message, False),
                conn.loop,
            )
            # 给前端一点时间处理消息
            await asyncio.sleep(0.05)
    except Exception:
        pass


class LoginResult:
    """登录结果"""

    def __init__(self, success: bool, message: str, need_admin: bool = False):
        self.success = success
        self.message = message
        self.need_admin = need_admin  # 是否需要管理员介入


async def _headless_login(
    conn=None,
    email: str = None,
    password: str = None,
) -> LoginResult:
    """
    无头模式登录电子书库

    Args:
        conn: 会话上下文（用于发送进度消息和读取配置）
        email: 登录邮箱（可选，未提供时从配置读取）
        password: 登录密码（可选，未提供时从配置读取）

    Returns:
        LoginResult: 登录结果
    """
    # 从配置中获取凭据
    if email is None or password is None:
        config_email, config_password = _get_credentials(conn)
        email = email or config_email
        password = password or config_password

    # 验证凭据是否配置
    if not email or not password:
        logger.bind(tag=TAG).error("电子书库账号密码未配置")
        return LoginResult(False, "电子书库账号未配置，请联系管理员在配置文件中设置", need_admin=True)

    # 获取域名列表
    domains = _get_domains(conn)

    if async_playwright is None:
        logger.bind(tag=TAG).error("Playwright 未安装")
        return LoginResult(False, "系统组件未安装，请联系管理员安装 Playwright", need_admin=True)

    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    CONFIG_DIR.chmod(0o700)

    async with async_playwright() as p:
        # 步骤1: 启动浏览器
        await _send_progress(conn, "正在启动浏览器...")
        try:
            browser = await p.chromium.launch_persistent_context(
                executable_path=CHROME_PATH,
                user_data_dir=str(CONFIG_DIR / "browser_profile"),
                headless=True,
                args=[
                    "--disable-blink-features=AutomationControlled",
                    "--no-sandbox",
                    "--disable-dev-shm-usage",
                ],
            )
        except Exception as e:
            logger.bind(tag=TAG).error(f"启动浏览器失败: {e}")
            return LoginResult(False, "启动浏览器失败，请联系管理员检查 Chrome 路径", need_admin=True)

        page = browser.pages[0] if browser.pages else await browser.new_page()
        page.set_default_timeout(10000)

        try:
            # 步骤2: 访问网站
            await _send_progress(conn, "正在连接电子书库...")
            page_loaded = False
            for domain in domains:
                try:
                    await page.goto(domain, wait_until="domcontentloaded", timeout=15000)
                    await asyncio.sleep(0.5)
                    page_loaded = True
                    break
                except Exception:
                    continue

            if not page_loaded:
                return LoginResult(False, "无法连接到电子书库，请稍后重试")

            # 步骤3: 检查登录状态
            await _send_progress(conn, "正在检查登录状态...")
            logged_in = await page.query_selector(SELECTORS["logged_in_indicator"])
            logged_out = await page.query_selector(SELECTORS["logged_out_indicator"])

            if logged_in and not logged_out:
                # 已登录，更新会话
                await browser.storage_state(path=str(STORAGE_STATE))
                STORAGE_STATE.chmod(0o600)
                return LoginResult(True, "已自动恢复登录状态")

            # 步骤4: 点击登录按钮
            await _send_progress(conn, "正在打开登录页面...")
            login_trigger = await page.query_selector(SELECTORS["login_trigger"])
            if login_trigger:
                await login_trigger.click()
                await asyncio.sleep(0.5)
            else:
                logger.bind(tag=TAG).warning("未找到登录按钮")
                return LoginResult(False, "页面元素异常，请联系管理员维护", need_admin=True)

            # 等待登录表单
            try:
                await page.wait_for_selector(SELECTORS["login_form"], timeout=5000)
            except Exception:
                return LoginResult(False, "登录表单加载失败，请联系管理员维护", need_admin=True)

            # 步骤5: 填写表单
            await _send_progress(conn, "正在验证账号信息...")

            email_input = await page.query_selector(SELECTORS["email_input"])
            if not email_input:
                return LoginResult(False, "登录表单异常，请联系管理员维护", need_admin=True)
            await email_input.fill(email)

            password_input = await page.query_selector(SELECTORS["password_input"])
            if not password_input:
                return LoginResult(False, "登录表单异常，请联系管理员维护", need_admin=True)
            await password_input.fill(password)

            # 步骤6: 提交登录
            await _send_progress(conn, "正在登录...")
            submit_button = await page.query_selector(SELECTORS["submit_button"])
            if not submit_button:
                return LoginResult(False, "登录按钮未找到，请联系管理员维护", need_admin=True)
            await submit_button.click()

            # 等待登录完成
            await asyncio.sleep(2)

            # 检查登录结果
            logged_in = await page.query_selector(SELECTORS["logged_in_indicator"])
            logged_out = await page.query_selector(SELECTORS["logged_out_indicator"])

            # 检查错误信息
            error_elem = await page.query_selector(SELECTORS["error_message"])
            error_text = ""
            if error_elem:
                error_text = await error_elem.inner_text()

            if logged_in or not logged_out:
                # 登录成功
                await browser.storage_state(path=str(STORAGE_STATE))
                STORAGE_STATE.chmod(0o600)
                return LoginResult(True, "登录成功")
            else:
                # 登录失败
                if error_text and "password" in error_text.lower():
                    return LoginResult(False, "密码错误，请联系管理员更新账号配置", need_admin=True)
                elif error_text and "email" in error_text.lower():
                    return LoginResult(False, "账号不存在或格式错误，请联系管理员", need_admin=True)
                elif error_text:
                    return LoginResult(False, f"登录失败: {error_text}")
                else:
                    return LoginResult(False, "登录失败，请稍后重试或联系管理员")

        except Exception as e:
            logger.bind(tag=TAG).error(f"登录过程异常: {e}")
            return LoginResult(False, "登录过程发生错误，请联系管理员")
        finally:
            await browser.close()


class ZLibrarySearcher:
    """电子书搜索器"""

    def __init__(self, conn=None):
        self.config_dir = CONFIG_DIR
        self.storage_state = STORAGE_STATE
        self.conn = conn
        self.domains = _get_domains(conn) if conn else []

    def _check_login(self) -> bool:
        """检查是否已登录"""
        return self.storage_state.exists()

    async def search(self, query: str, limit: int = 10) -> list[dict[str, Any]]:
        """搜索书籍"""
        if not self._check_login():
            logger.bind(tag=TAG).warning("未找到登录状态")
            return []
        return await self._search_via_playwright(query, limit)

    async def _search_via_playwright(self, query: str, limit: int = 10) -> list[dict[str, Any]]:
        """通过 Playwright 搜索"""
        if async_playwright is None:
            logger.bind(tag=TAG).error("Playwright 未安装")
            return []

        start_time = time.time()
        logger.bind(tag=TAG).info(f"搜索: {query}")
        results = []
        last_error = None

        async with async_playwright() as p:
            browser = await self._launch_browser(p)
            if not browser:
                return []

            try:
                page = browser.pages[0] if browser.pages else await browser.new_page()
                page.set_default_timeout(10000)

                for domain in self.domains:
                    try:
                        await page.goto(domain, wait_until="domcontentloaded", timeout=15000)
                        await asyncio.sleep(0.5)  # 等待页面稳定

                        search_input = await page.query_selector(
                            'input[name="q"], input[type="search"], input[placeholder*="搜索"], input[placeholder*="Search"]'
                        )

                        if search_input:
                            await search_input.fill(query)
                            await asyncio.sleep(0.05)
                            await search_input.press("Enter")

                            # 等待页面导航完成
                            await asyncio.sleep(1.0)  # 给搜索结果页面加载时间

                            results = await self._parse_search_results(page, limit)

                            if results:
                                end_time = time.time()
                                logger.bind(tag=TAG).info(
                                    f"找到 {len(results)} 条结果，耗时: {end_time - start_time:.2f}秒"
                                )
                                break
                            else:
                                logger.bind(tag=TAG).info(f"域名 {domain} 未返回结果，尝试下一个")
                    except Exception as e:
                        last_error = str(e)
                        logger.bind(tag=TAG).warning(f"访问 {domain} 失败: {e}")
                        continue

            except Exception as e:
                logger.bind(tag=TAG).error(f"搜索出错: {e}")
            finally:
                await browser.close()

        if not results and last_error:
            logger.bind(tag=TAG).error(f"所有域名搜索失败，最后错误: {last_error}")

        return results

    async def _launch_browser(self, playwright) -> Browser | None:
        """启动浏览器（使用公共函数）"""
        return await _launch_browser_for_download(playwright, self.config_dir)

    async def _parse_search_results(self, page, limit: int = 10) -> list[dict[str, Any]]:
        """解析搜索结果"""
        results = []

        try:
            await asyncio.sleep(0.05)
            try:
                await page.wait_for_selector("z-bookcard", timeout=5000)
            except Exception:
                pass

            book_elements = await page.query_selector_all("z-bookcard")

            if not book_elements:
                links = await page.query_selector_all('a[href*="/book/"]')
                seen_links = set()
                for link in links[: limit * 2]:
                    href = await link.get_attribute("href")
                    if href and href not in seen_links:
                        seen_links.add(href)
                        book_elements.append(link)

            for i, element in enumerate(book_elements[:limit]):
                try:
                    book_info = await self._extract_book_info(element)
                    if book_info and book_info.get("title"):
                        results.append(book_info)
                except Exception:
                    continue

        except Exception as e:
            logger.bind(tag=TAG).error(f"解析结果失败: {e}")

        return results

    async def _extract_book_info(self, element) -> dict[str, Any] | None:
        """提取书籍信息"""
        book_info = {
            "title": "",
            "author": "",
            "link": "",
            "format": "",
            "size": "",
            "year": "",
        }

        try:
            tag_name = await element.evaluate("el => el.tagName.toLowerCase()")

            if tag_name == "z-bookcard".lower():
                book_info["link"] = await element.get_attribute("href") or ""
                book_info["year"] = await element.get_attribute("year") or ""
                book_info["format"] = (await element.get_attribute("extension") or "").upper()
                book_info["size"] = await element.get_attribute("filesize") or ""

                title_text = await element.evaluate(
                    """el => {
                        const titleSlot = el.querySelector('[slot="title"]');
                        return titleSlot ? titleSlot.textContent.trim() : '';
                    }"""
                )
                author_text = await element.evaluate(
                    """el => {
                        const authorSlot = el.querySelector('[slot="author"]');
                        return authorSlot ? authorSlot.textContent.trim() : '';
                    }"""
                )

                book_info["title"] = title_text
                book_info["author"] = author_text

                if book_info["link"] and book_info["link"].startswith("/"):
                    book_info["link"] = f"{self.domains[0]}{book_info['link']}"

            else:
                href = await element.get_attribute("href")
                if href:
                    book_info["link"] = f"{self.domains[0]}{href}" if href.startswith("/") else href
                    book_info["title"] = await element.inner_text()

            book_info["title"] = book_info["title"].strip()
            book_info["author"] = book_info["author"].strip()

            if book_info["title"]:
                return book_info

        except Exception:
            pass

        return None


def _get_search_result_file(conn) -> Path:
    """获取搜索结果文件路径（与对话历史在同一目录）"""
    try:
        # 优先使用 client_session_dir（与对话历史在同一目录）
        if hasattr(conn, "client_session_dir") and conn.client_session_dir:
            session_dir = Path(conn.client_session_dir)
            session_dir.mkdir(parents=True, exist_ok=True)
            return session_dir / "ebook_search_result.json"
        # 备选：使用 session_id
        elif hasattr(conn, "session_id") and conn.session_id:
            session_dir = Path(__file__).parent.parent.parent / "data" / "sessions" / conn.session_id
            session_dir.mkdir(parents=True, exist_ok=True)
            return session_dir / "ebook_search_result.json"
    except Exception:
        pass
    # 最后备选：使用配置目录
    return CONFIG_DIR / "ebook_search_result.json"


def _save_search_results(conn, results: list[dict[str, Any]]) -> None:
    """保存搜索结果到 JSON 文件

    Args:
        conn: 会话上下文
        results: 搜索结果列表
    """
    try:
        # 添加序号
        indexed_results = []
        for i, book in enumerate(results, 1):
            indexed_results.append(
                {
                    "index": i,
                    "title": book.get("title", ""),
                    "author": book.get("author", ""),
                    "link": book.get("link", ""),
                    "format": book.get("format", ""),
                    "size": book.get("size", ""),
                    "year": book.get("year", ""),
                }
            )

        # 保存到文件
        result_file = _get_search_result_file(conn)
        with open(result_file, "w", encoding="utf-8") as f:
            json.dump(indexed_results, f, ensure_ascii=False, indent=2)

        logger.bind(tag=TAG).info(f"搜索结果已保存: {result_file}")
    except Exception as e:
        logger.bind(tag=TAG).error(f"保存搜索结果失败: {e}")


def _load_search_results(conn) -> list[dict[str, Any]]:
    """从 JSON 文件加载搜索结果

    Args:
        conn: 会话上下文

    Returns:
        搜索结果列表，失败时返回空列表
    """
    try:
        result_file = _get_search_result_file(conn)
        if result_file.exists():
            with open(result_file, "r", encoding="utf-8") as f:
                return json.load(f)
    except Exception as e:
        logger.bind(tag=TAG).error(f"加载搜索结果失败: {e}")
    return []


def _format_books_summary(results: list[dict[str, Any]]) -> str:
    """格式化书籍列表摘要（用于对话历史）

    Args:
        results: 搜索结果列表

    Returns:
        书籍列表摘要字符串
    """
    lines = ["搜索到以下书籍："]
    for i, book in enumerate(results, 1):
        title = book.get("title", "未知标题")
        lines.append(f"{i}. {title}")
    return "\n".join(lines)


def _format_results(results: list[dict[str, Any]]) -> str:
    """格式化搜索结果"""
    if not results:
        return "未找到相关书籍"

    lines = []
    for i, book in enumerate(results, 1):
        title = book.get("title", "未知标题")
        author = book.get("author", "")
        link = book.get("link", "")
        fmt = book.get("format", "")
        size = book.get("size", "")
        year = book.get("year", "")

        meta = []
        if fmt:
            meta.append(fmt)
        if size:
            meta.append(size)
        if year:
            meta.append(year)

        line = f"{i}. **{title}**"
        if author:
            line += f"\n   作者: {author}"
        if meta:
            line += f"\n   信息: {' | '.join(meta)}"
        if link:
            line += f"\n   链接: [查看详情]({link})"

        lines.append(line)

    return "\n\n".join(lines)


@register_function("search_ebook", SEARCH_EBOOK_FUNCTION_DESC, ToolType.SYSTEM_CTL)
def search_ebook(conn, query: str = "", limit: int = 10):
    """
    在电子书库中搜索书籍

    Args:
        conn: 会话上下文
        query: 搜索关键词
        limit: 返回条数上限
    Returns:
        ActionResponse: 搜索结果
    """
    # 1. 检查关键词
    if not query or not str(query).strip():
        tip = "请提供书籍名称或作者进行搜索，例如：'搜索电子书 Python编程'"
        try:
            if hasattr(conn, "loop") and conn.loop:
                asyncio.run_coroutine_threadsafe(
                    conn.output_processor.send_llm_stream_response_message(tip, True),
                    conn.loop,
                )
        except Exception:
            pass
        return ActionResponse(Action.RESPONSE, "缺少关键词", tip)

    # 2. 检查登录状态，未登录则自动登录
    if not _check_login():
        # 执行自动登录（使用 _run_async 避免事件循环冲突）
        login_result = _run_async(_headless_login(conn))

        if not login_result.success:
            # 登录失败，返回错误信息
            tip = login_result.message
            if login_result.need_admin:
                tip += "\n\n（此问题需要管理员处理）"

            try:
                if hasattr(conn, "loop") and conn.loop:
                    asyncio.run_coroutine_threadsafe(
                        conn.output_processor.send_llm_stream_response_message(tip, True),
                        conn.loop,
                    )
            except Exception:
                pass
            return ActionResponse(Action.RESPONSE, "登录失败", tip)

    # 3. 执行搜索（使用 _run_async 避免事件循环冲突）
    searcher = ZLibrarySearcher(conn)
    try:
        results = _run_async(searcher.search(query, limit))
    except Exception as e:
        logger.bind(tag=TAG).error(f"搜索失败: {e}")
        tip = "搜索时发生错误，请稍后重试"
        try:
            if hasattr(conn, "loop") and conn.loop:
                asyncio.run_coroutine_threadsafe(
                    conn.output_processor.send_llm_stream_response_message(tip, True),
                    conn.loop,
                )
        except Exception:
            pass
        return ActionResponse(Action.RESPONSE, "搜索失败", tip)

    # 4. 格式化结果
    if not results:
        msg = f"未找到与「{query}」相关的书籍，请尝试其他关键词。"
        try:
            if hasattr(conn, "loop") and conn.loop:
                asyncio.run_coroutine_threadsafe(
                    conn.output_processor.send_llm_stream_response_message(msg, True),
                    conn.loop,
                )
        except Exception:
            pass
        return ActionResponse(Action.RESPONSE, "未找到结果", msg)

    # 5. 保存搜索结果到 JSON 文件
    _save_search_results(conn, results)

    # 6. 构建响应
    response_text = _format_results(results)

    # 5. 推送结果到前端
    try:
        if hasattr(conn, "loop") and conn.loop:
            asyncio.run_coroutine_threadsafe(
                conn.output_processor.send_llm_stream_response_message(response_text, True),
                conn.loop,
            )
    except Exception:
        pass

    return ActionResponse(
        Action.RESPONSE,
        {"query": query, "results": results},
        response_text,
    )


# ==================== 电子书下载功能 ====================


@dataclass
class DownloadResult:
    """电子书下载结果"""

    success: bool
    file_path: str | None = None
    format: str | None = None
    size: int = 0
    error: str | None = None


DOWNLOAD_EBOOK_FUNCTION_DESC = {
    "type": "function",
    "function": {
        "name": "download_ebook",
        "description": (
            "从电子书库下载书籍到本地。\n"
            "支持以下参数组合（优先级从高到低）：\n"
            "1. book_url: 直接提供书籍详情页URL\n"
            "2. index: 书籍在搜索结果中的序号（如1表示第一个，从1开始）\n"
            "3. book_name: 书籍名称（支持模糊匹配）\n\n"
            "适用场景：用户已经通过搜索功能获取到书籍，现在需要下载。"
            "支持PDF和EPUB格式，优先下载PDF格式。"
            "下载的文件会保存到服务器的指定目录。\n\n"
            "示例：\n"
            "- download_ebook(index=1) 下载第一个\n"
            "- download_ebook(book_name='Python编程') 下载指定书名\n"
            "- download_ebook(book_url='https://...') 直接下载"
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "book_url": {
                    "type": "string",
                    "description": "书籍详情页URL（直接提供时优先使用）",
                },
                "index": {
                    "type": "integer",
                    "description": "书籍在搜索结果中的序号（从1开始）",
                    "minimum": 1,
                },
                "book_name": {
                    "type": "string",
                    "description": "书籍名称（支持模糊匹配）",
                },
                "format": {
                    "type": "string",
                    "description": "首选格式（pdf或epub），默认为pdf",
                    "enum": ["pdf", "epub"],
                },
            },
        },
    },
}


def _resolve_book_url(conn, book_url: str = "", index: int = None, book_name: str = "") -> tuple[str, str]:
    """
    解析书籍 URL

    Args:
        conn: 会话上下文
        book_url: 直接提供的 URL
        index: 序号
        book_name: 书名

    Returns:
        (url, format) 或 (None, None)
    """
    # 优先级 1: 直接提供 URL
    if book_url:
        return book_url, ""

    # 加载搜索结果
    results = _load_search_results(conn)
    if not results:
        logger.bind(tag=TAG).warning("未找到搜索结果，请先执行搜索")
        return None, None

    # 优先级 2: 按序号查找
    if index is not None:
        for book in results:
            if book.get("index") == index:
                logger.bind(tag=TAG).info(f"找到第{index}个: {book.get('title')}")
                return book.get("link"), book.get("format", "")

    # 优先级 3: 按书名模糊匹配
    if book_name:
        for book in results:
            title = book.get("title", "")
            if book_name.lower() in title.lower():
                logger.bind(tag=TAG).info(f"找到匹配书籍: {title}")
                return book.get("link"), book.get("format", "")

    logger.bind(tag=TAG).warning(f"未找到匹配的书籍: index={index}, book_name={book_name}")
    return None, None


class ZLibraryDownloader:
    """电子书下载器"""

    def __init__(self, conn=None):
        self.config_dir = CONFIG_DIR
        self.storage_state = STORAGE_STATE
        self.conn = conn
        self.domains = _get_domains(conn) if conn else []
        # 获取下载目录配置
        self.download_dir = self._get_download_dir()

    def _get_download_dir(self) -> Path:
        """获取下载目录"""
        # 从配置获取下载目录，默认为 data/ebooks（相对于server目录）
        download_config = _get_config(self.conn, "download_dir", "data/ebooks")
        # 处理相对路径
        if not os.path.isabs(download_config):
            # 获取server目录（search_ebook.py所在目录的上级）
            server_dir = Path(__file__).parent.parent.parent
            download_dir = server_dir / download_config
        else:
            download_dir = Path(download_config)

        # 确保目录存在
        download_dir.mkdir(parents=True, exist_ok=True)
        return download_dir

    def _check_login(self) -> bool:
        """检查是否已登录"""
        return self.storage_state.exists()

    async def _launch_browser(self, playwright) -> Browser | None:
        """启动浏览器（使用公共函数，启用下载）"""
        return await _launch_browser_for_download(playwright, self.config_dir, accept_downloads=True)

    async def _detect_interface_type(self, page) -> str:
        """
        检测界面类型

        Args:
            page: Playwright 页面对象

        Returns:
            'new' 或 'old'
        """
        # 新版界面特征：三点菜单按钮
        new_indicators = [
            'button[aria-label="更多选项"]',
            'button[title="更多"]',
            ".more-options",
            '[class*="dots"]',
        ]
        for selector in new_indicators:
            if await page.query_selector(selector):
                return "new"
        return "old"

    async def _wait_for_conversion(self, page, target_format: str, timeout: int = 60, download_completed: asyncio.Event = None) -> bool:
        """
        等待格式转换完成（旧版界面）

        Args:
            page: Playwright 页面对象
            target_format: 目标格式 (pdf 或 epub)
            timeout: 超时时间（秒）
            download_completed: 下载完成事件（如果提供，下载完成后立即返回）

        Returns:
            转换是否成功
        """
        logger.bind(tag=TAG).info(f"等待 {target_format.upper()} 转换完成...")
        await _send_progress(self.conn, f"正在转换格式为 {target_format.upper()}...")

        for i in range(timeout):
            await asyncio.sleep(1)

            # 如果提供了下载完成事件，检查是否已下载
            if download_completed and download_completed.is_set():
                logger.bind(tag=TAG).info(f"{target_format.upper()} 文件已下载，转换完成")
                return True

            try:
                # 检查转换完成的消息
                message = await page.query_selector('.message:has-text("转换为")')
                if message:
                    message_text = await message.inner_text()
                    if target_format.lower() in message_text.lower() and "完成" in message_text:
                        logger.bind(tag=TAG).info(f"{target_format.upper()} 转换完成")
                        return True
            except Exception:
                pass

            # 每10秒报告一次进度
            if i > 0 and i % 10 == 0:
                logger.bind(tag=TAG).info(f"等待中... {i}秒")

        return False

    async def _download_new_interface(self, page, preferred_format: str) -> tuple:
        """
        新版界面下载（三点菜单）

        Returns:
            (download_link, downloaded_format)
        """
        logger.bind(tag=TAG).info("检测到新版界面（三点菜单）")
        await _send_progress(self.conn, "检测到新版界面，正在查找下载选项...")

        # 查找三点菜单按钮
        dots_selectors = [
            'button[aria-label="更多选项"]',
            'button[title="更多"]',
            ".more-options",
            '[class*="dots"]',
            '[class*="more"]',
        ]

        dots_button = None
        for selector in dots_selectors:
            try:
                dots_button = await page.query_selector(selector)
                if dots_button:
                    break
            except Exception:
                continue

        if not dots_button:
            logger.bind(tag=TAG).warning("未找到三点菜单按钮")
            return None, None

        # 点击打开菜单
        try:
            await dots_button.click()
            await asyncio.sleep(2)
        except Exception as e:
            logger.bind(tag=TAG).error(f"点击菜单失败: {e}")
            return None, None

        # 根据首选格式查找选项
        format_priority = [preferred_format.lower(), "epub" if preferred_format.lower() == "pdf" else "pdf"]

        for fmt in format_priority:
            logger.bind(tag=TAG).info(f"查找 {fmt.upper()} 选项...")
            options = await page.query_selector_all(f'a:has-text("{fmt.upper()}"), button:has-text("{fmt.upper()}")')
            if options:
                logger.bind(tag=TAG).info(f"找到 {fmt.upper()} 选项")
                return options[0], fmt

        return None, None

    async def _download_old_interface(self, page, preferred_format: str, download_completed: asyncio.Event = None) -> tuple:
        """
        旧版界面下载（转换按钮）

        Returns:
            (download_link, downloaded_format)
        """
        logger.bind(tag=TAG).info("检测到旧版界面")
        await _send_progress(self.conn, "检测到旧版界面，正在查找转换选项...")

        # 格式优先级
        format_priority = [preferred_format.lower(), "epub" if preferred_format.lower() == "pdf" else "pdf"]

        for fmt in format_priority:
            convert_selector = f'a[data-convert_to="{fmt}"]'
            convert_button = await page.query_selector(convert_selector)

            if convert_button:
                logger.bind(tag=TAG).info(f"检测到 {fmt.upper()} 转换按钮")
                await _send_progress(self.conn, f"正在转换为 {fmt.upper()} 格式...")

                # 点击转换按钮
                try:
                    await convert_button.evaluate("el => el.click()")
                    logger.bind(tag=TAG).info(f"已点击 {fmt.upper()} 转换按钮")
                except Exception as e:
                    logger.bind(tag=TAG).error(f"点击转换按钮失败: {e}")
                    continue

                # 等待转换完成（传递下载事件以便提前结束等待）
                conversion_success = await self._wait_for_conversion(page, fmt, download_completed=download_completed)
                if not conversion_success:
                    logger.bind(tag=TAG).warning(f"{fmt.upper()} 转换超时")
                    continue

                # 查找下载链接
                download_link = await page.query_selector(f'a[href*="/dl/"][href*="convertedTo={fmt}"]')
                if download_link:
                    return download_link, fmt

                # 备选：查找任何 /dl/ 链接
                all_links = await page.query_selector_all('a[href*="/dl/"]')
                if all_links:
                    return all_links[0], fmt

        return None, None

    async def download(self, book_url: str, preferred_format: str = "pdf") -> DownloadResult:
        """
        下载电子书

        Args:
            book_url: 书籍详情页URL
            preferred_format: 首选格式 (pdf 或 epub)

        Returns:
            DownloadResult: 下载结果
        """
        if not self._check_login():
            logger.bind(tag=TAG).warning("未找到登录状态")
            return DownloadResult(False, error="未登录，请先执行搜索功能")

        if async_playwright is None:
            logger.bind(tag=TAG).error("Playwright 未安装")
            return DownloadResult(False, error="系统组件未安装")

        # 获取超时配置
        timeout_seconds = _get_config(self.conn, "timeout_seconds", 300)

        start_time = time.time()
        logger.bind(tag=TAG).info(f"开始下载: {book_url}")

        download_path = None
        downloaded_format = None
        download_completed = asyncio.Event()  # 下载完成事件

        async with async_playwright() as p:
            browser = await self._launch_browser(p)
            if not browser:
                return DownloadResult(False, error="启动浏览器失败")

            try:
                page = browser.pages[0] if browser.pages else await browser.new_page()
                page.set_default_timeout(60000)

                # 设置下载处理
                async def handle_download(download):
                    nonlocal download_path, downloaded_format
                    try:
                        suggested_filename = download.suggested_filename
                        # 清理文件名
                        suggested_filename = re.sub(r'[<>:"/\\|?*]', "_", suggested_filename)
                        logger.bind(tag=TAG).info(f"下载文件名: {suggested_filename}")

                        # 从文件名推断格式
                        file_ext = Path(suggested_filename).suffix.lower().replace(".", "")
                        if file_ext in ["pdf", "epub"]:
                            downloaded_format = file_ext

                        file_path = self.download_dir / suggested_filename
                        await download.save_as(file_path)
                        download_path = file_path
                        logger.bind(tag=TAG).info(f"文件已保存: {file_path}")
                        download_completed.set()  # 标记下载完成
                    except Exception as e:
                        logger.bind(tag=TAG).error(f"保存文件失败: {e}")

                page.on("download", handle_download)

                # 访问书籍页面
                await _send_progress(self.conn, "正在访问书籍页面...")
                try:
                    await page.goto(book_url, wait_until="domcontentloaded", timeout=60000)
                    await asyncio.sleep(3)
                except Exception as e:
                    logger.bind(tag=TAG).error(f"访问页面失败: {e}")
                    return DownloadResult(False, error=f"访问页面失败: {e}")

                # 检测界面类型并执行下载
                dots_button = await page.query_selector(
                    'button[aria-label="更多选项"], button[title="更多"], .more-options'
                )

                download_link = None

                if dots_button:
                    # 新版界面
                    download_link, downloaded_format = await self._download_new_interface(page, preferred_format)
                else:
                    # 旧版界面（传递下载事件以便提前结束等待）
                    download_link, downloaded_format = await self._download_old_interface(page, preferred_format, download_completed)

                # 如果两种方法都没找到，尝试直接查找下载链接
                if not download_link:
                    logger.bind(tag=TAG).info("未检测到特定界面，查找直接下载链接...")
                    await _send_progress(self.conn, "正在查找下载链接...")

                    selectors = [
                        'a[href*="/dl/"]',
                        'a:has-text("下载")',
                        'a:has-text("Download")',
                        'button:has-text("下载")',
                    ]

                    for selector in selectors:
                        try:
                            links = await page.query_selector_all(selector)
                            if links:
                                for link in links:
                                    href = await link.get_attribute("href")
                                    if href and "/dl/" in href:
                                        download_link = link
                                        # 从 URL 判断格式
                                        if "pdf" in href.lower():
                                            downloaded_format = "pdf"
                                        elif "epub" in href.lower():
                                            downloaded_format = "epub"
                                        logger.bind(tag=TAG).info(f"找到下载链接: {href}")
                                        break
                                if download_link:
                                    break
                        except Exception:
                            continue

                if not download_link:
                    logger.bind(tag=TAG).error("未找到下载链接")
                    return DownloadResult(False, error="未找到下载链接，请检查书籍是否可用")

                # 点击下载
                await _send_progress(self.conn, "正在下载...")
                try:
                    await download_link.evaluate("el => el.click()")
                    logger.bind(tag=TAG).info("点击下载链接成功")
                except Exception as e:
                    logger.bind(tag=TAG).error(f"点击下载链接失败: {e}")
                    return DownloadResult(False, error=f"点击下载链接失败: {e}")

                # 等待下载完成
                logger.bind(tag=TAG).info("等待下载完成...")
                # 使用配置的超时时间，默认最多等待60秒
                download_timeout = min(timeout_seconds, 60)
                try:
                    # 等待下载完成事件
                    await asyncio.wait_for(download_completed.wait(), timeout=download_timeout)
                    logger.bind(tag=TAG).info("下载事件触发")
                except asyncio.TimeoutError:
                    logger.bind(tag=TAG).warning("等待下载超时，检查文件...")

                # 检查下载结果
                if download_path and download_path.exists():
                    file_size = download_path.stat().st_size
                    end_time = time.time()
                    logger.bind(tag=TAG).info(
                        f"下载成功: {download_path.name}, "
                        f"格式: {downloaded_format}, "
                        f"大小: {file_size / 1024:.1f} KB, "
                        f"耗时: {end_time - start_time:.2f}秒"
                    )
                    return DownloadResult(True, file_path=str(download_path), format=downloaded_format, size=file_size)

                # 备选：检查下载目录（根据格式）
                if downloaded_format:
                    pattern = f"*.{downloaded_format}"
                    downloaded_files = list(self.download_dir.glob(pattern))

                    if downloaded_files:
                        # 找最新的文件
                        latest_file = max(downloaded_files, key=lambda p: p.stat().st_mtime)
                        file_age = time.time() - latest_file.stat().st_mtime

                        # 检查文件是否是最近下载的
                        if file_age < 120:
                            file_size = latest_file.stat().st_size
                            end_time = time.time()
                            logger.bind(tag=TAG).info(
                                f"下载成功: {latest_file.name}, "
                                f"格式: {downloaded_format}, "
                                f"大小: {file_size / 1024:.1f} KB, "
                                f"耗时: {end_time - start_time:.2f}秒"
                            )
                            return DownloadResult(
                                True, file_path=str(latest_file), format=downloaded_format, size=file_size
                            )

                logger.bind(tag=TAG).error("未找到下载的文件")
                return DownloadResult(False, error="下载失败，未找到文件")

            except Exception as e:
                logger.bind(tag=TAG).error(f"下载过程出错: {e}")
                return DownloadResult(False, error=f"下载过程出错: {e}")
            finally:
                await browser.close()


@register_function("download_ebook", DOWNLOAD_EBOOK_FUNCTION_DESC, ToolType.SYSTEM_CTL)
def download_ebook(conn, book_url: str = "", index: int = None, book_name: str = "", format: str = "pdf"):
    """
    下载电子书到本地

    Args:
        conn: 会话上下文
        book_url: 书籍详情页URL（可选，直接提供时优先使用）
        index: 书籍在搜索结果中的序号（可选，从1开始）
        book_name: 书籍名称（可选，支持模糊匹配）
        format: 首选格式 (pdf 或 epub)，默认为 pdf

    Returns:
        ActionResponse: 下载结果
    """
    # 1. 解析书籍 URL（支持序号、书名、直接 URL）
    resolved_url, _ = _resolve_book_url(conn, book_url, index, book_name)

    if not resolved_url:
        tip = "未找到指定的书籍。请先搜索书籍，然后说「下载第N个」或「下载《书名》」。"
        try:
            if hasattr(conn, "loop") and conn.loop:
                asyncio.run_coroutine_threadsafe(
                    conn.output_processor.send_llm_stream_response_message(tip, True),
                    conn.loop,
                )
        except Exception:
            pass
        return ActionResponse(Action.RESPONSE, "未找到书籍", tip)

    # 2. 验证解析后的 URL 格式
    if not resolved_url.startswith(("http://", "https://")):
        tip = "无效的书籍链接格式。请先搜索书籍后再下载。"
        try:
            if hasattr(conn, "loop") and conn.loop:
                asyncio.run_coroutine_threadsafe(
                    conn.output_processor.send_llm_stream_response_message(tip, True),
                    conn.loop,
                )
        except Exception:
            pass
        return ActionResponse(Action.RESPONSE, "无效的链接", tip)

    # 3. 检查登录状态
    if not _check_login():
        tip = "未登录电子书库。请先执行搜索功能，系统会自动登录后再下载。"
        try:
            if hasattr(conn, "loop") and conn.loop:
                asyncio.run_coroutine_threadsafe(
                    conn.output_processor.send_llm_stream_response_message(tip, True),
                    conn.loop,
                )
        except Exception:
            pass
        return ActionResponse(Action.RESPONSE, "未登录", tip)

    # 4. 格式化参数
    format = format.lower() if format else "pdf"
    if format not in ["pdf", "epub"]:
        format = "pdf"

    # 5. 执行下载（使用解析后的 URL）
    downloader = ZLibraryDownloader(conn)
    try:
        result = _run_async(downloader.download(resolved_url, format))
    except Exception as e:
        logger.bind(tag=TAG).error(f"下载失败: {e}")
        tip = "下载时发生错误，请稍后重试"
        try:
            if hasattr(conn, "loop") and conn.loop:
                asyncio.run_coroutine_threadsafe(
                    conn.output_processor.send_llm_stream_response_message(tip, True),
                    conn.loop,
                )
        except Exception:
            pass
        return ActionResponse(Action.RESPONSE, "下载失败", tip)

    # 6. 处理结果
    if not result.success:
        error_tip = result.error or "下载失败，请稍后重试"
        try:
            if hasattr(conn, "loop") and conn.loop:
                asyncio.run_coroutine_threadsafe(
                    conn.output_processor.send_llm_stream_response_message(error_tip, True),
                    conn.loop,
                )
        except Exception:
            pass
        return ActionResponse(Action.RESPONSE, "下载失败", error_tip)

    # 7. 成功响应
    file_size_kb = result.size / 1024 if result.size else 0
    success_msg = (
        f"✅ 下载成功！\n\n"
        f"📄 文件名：{Path(result.file_path).name}\n"
        f"📁 路径：{result.file_path}\n"
        f"📊 格式：{result.format.upper() if result.format else '未知'}\n"
        f"💾 大小：{file_size_kb:.1f} KB"
    )

    # 发送最终结果消息（与 search_ebook 保持一致）
    try:
        if hasattr(conn, "loop") and conn.loop:
            asyncio.run_coroutine_threadsafe(
                conn.output_processor.send_llm_stream_response_message(success_msg, True),
                conn.loop,
            )
    except Exception:
        pass

    return ActionResponse(
        Action.RESPONSE,
        {
            "success": True,
            "file_path": result.file_path,
            "format": result.format,
            "size": result.size,
        },
        success_msg,
    )
