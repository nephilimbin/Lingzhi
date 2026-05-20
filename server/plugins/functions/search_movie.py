"""
LUNA 本地部署的视频播放器
"""

import asyncio
import difflib
import os
from typing import Any, Dict, List
import urllib.parse

from config.logger import setup_logging
from core.models import Action, ActionResponse, ToolType
from core.registries import register_function
import requests

TAG = __name__
logger = setup_logging()


SEARCH_MOVIE_FUNCTION_DESC = {
    "type": "function",
    "function": {
        "name": "search_movie",
        "description": (
            "在`电影资源站`内搜索影片资源，并直接返回`电影资源站`播放页链接（可点击播放）。"
            "触发条件（优先使用本函数）: 用户提到 '电影站/站内/播放/在线观看/电影链接/播放页/在电影站中搜索/在站内搜索' 等；"
            "禁用条件（不要调用本函数）: 用户明确要求 '下载/网盘/磁力/网页搜索' 等 → 交给 AIsearch。"
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "要搜索的影片关键词（电影/电视剧名等）",
                },
                "top_k": {
                    "type": "integer",
                    "description": "最多返回的结果条数，默认 5",
                },
                "prefer": {
                    "type": "boolean",
                    "description": "播放页是否启用优选播放源，默认 true",
                },
            },
            "required": ["query"],
        },
    },
}


def _get_base_url(conn) -> str:
    """获取电影资源站基础地址，优先读取配置，其次读取环境变量，最后默认 http://localhost:3000

    注意: 开发场景下电影资源站的 Next.js 中间件常按主机名区分来源，使用 127.0.0.1 访问可能命中不同服务或导致 404。
    因此将默认值从 127.0.0.1 调整为 localhost。
    """
    try:
        if hasattr(conn, "config"):
            base = conn.config.get("function_plugins", {}).get("search_movie", {}).get("base_url")
            if base:
                return base.rstrip("/")
    except Exception:
        pass

    env_base = os.getenv("MOVIE_BASE_URL")
    if env_base:
        return env_base.rstrip("/")
    return "http://localhost:3002"


def _safe_get(d: Dict[str, Any], key: str, default=""):
    v = d.get(key)
    return v if v is not None else default


def _build_play_url(base_url: str, item: Dict[str, Any], prefer: bool = True) -> str:
    """构造电影资源站播放页链接，优先使用 source+id，其次使用 title+year。"""
    params = {
        "source": _safe_get(item, "source"),
        "id": _safe_get(item, "id"),
        "title": _safe_get(item, "title"),
        "year": _safe_get(item, "year"),
        "prefer": "true" if prefer else "false",
    }
    # 去除空参数
    params = {k: v for k, v in params.items() if v}
    return f"{base_url}/play?{urllib.parse.urlencode(params)}"


def _build_detail_api(base_url: str, item: Dict[str, Any]) -> str:
    params = {
        "source": _safe_get(item, "source"),
        "id": _safe_get(item, "id"),
    }
    params = {k: v for k, v in params.items() if v}
    return f"{base_url}/api/detail?{urllib.parse.urlencode(params)}"


def _get_public_base_url(conn, local_base_url: str) -> str:
    """根据配置推导公网可访问的Base URL。

    优先级：
    1) plugins.search_movie.public_base_url（若配置）
    2) 回退为 local_base_url
    """
    # 若提供了独立的 public_base_url
    try:
        if hasattr(conn, "config"):
            pub = conn.config.get("function_plugins", {}).get("search_movie", {}).get("public_base_url")
            if isinstance(pub, str) and pub:
                return pub.rstrip("/")
    except Exception:
        pass

    # 直接返回本地地址（当前场景无需推导公网地址）
    return local_base_url


def _get_password(conn) -> str:
    """从会话配置或环境变量中读取电影资源站密码（localstorage 模式）。"""
    # 优先从会话配置读取
    try:
        if hasattr(conn, "config"):
            pwd = conn.config.get("function_plugins", {}).get("search_movie", {}).get("password")
            if isinstance(pwd, str) and pwd:
                return pwd
    except Exception:
        pass

    # 其次读取环境变量
    return os.getenv("MOVIE_PASSWORD", "admin")


def _fetch_search(base_url: str, query: str, password: str = "") -> List[Dict[str, Any]]:
    """调用电影资源站搜索接口。

    - 自动处理 localstorage 模式下需要的鉴权：
      1) 先直接请求 /api/search
      2) 若返回 401 且提供了密码，则调用 /api/login 完成登录后重试
    - 说明：前端以 encodeURIComponent 进行编码，这里保持一致使用 urllib.parse.quote
    """
    url = f"{base_url}/api/search?q={urllib.parse.quote(query)}"
    logger.bind(tag=TAG).info(f"请求电影资源站搜索接口: {url}")

    def _request_with_session(sess: requests.Session):
        r = sess.get(url, timeout=10)
        return r

    try:
        session = requests.Session()
        resp = _request_with_session(session)

        # 未认证则尝试自动登录（仅当提供了密码时）
        if resp.status_code == 401 and password:
            login_url = f"{base_url}/api/login"
            logger.bind(tag=TAG).info("电影资源站搜索 401，尝试调用 /api/login 自动登录后重试")
            try:
                login_resp = session.post(login_url, json={"username": "admin", "password": password}, timeout=10)
                if login_resp.status_code == 200:
                    resp = _request_with_session(session)
            except Exception as _:
                # 登录失败时保持原始 resp
                pass

        resp.raise_for_status()
        data = resp.json()
        results = data.get("results", [])
        if not isinstance(results, list):
            return []
        return results
    except Exception as e:
        logger.bind(tag=TAG).error(f"电影资源站搜索失败: {e}")
        return []


def _similarity(a: str, b: str) -> float:
    """计算标题相似度，范围[0,1]。"""
    a_norm = (a or "").lower().replace(" ", "")
    b_norm = (b or "").lower().replace(" ", "")
    if not a_norm or not b_norm:
        return 0.0
    return difflib.SequenceMatcher(None, a_norm, b_norm).ratio()


def _score_item(query: str, title: str) -> float:
    """为结果打分：精确匹配>包含关系>相似度。"""
    q = (query or "").strip()
    t = title or ""

    if not q or not t:
        return 0.0

    if t == q:
        return 2.0
    if q.replace(" ", "") in t.replace(" ", "") or t.replace(" ", "") in q.replace(" ", ""):
        return 1.5

    # token 命中计分
    tokens = [tok for tok in q.split(" ") if tok]
    token_hits = sum(1 for tok in tokens if tok in t)
    token_score = token_hits / max(1, len(tokens)) * 0.5

    # 相似度
    sim = _similarity(q, t)
    return token_score + sim


@register_function("search_movie", SEARCH_MOVIE_FUNCTION_DESC, ToolType.SYSTEM_CTL)
def search_movie(conn, query: str = "", top_k: int = 5, prefer: bool = True):
    """
    在电影资源站中搜索影片资源。

    Args:
        conn: 会话上下文（用于读取配置）
        query: 搜索关键词
        top_k: 返回条数上限
        prefer: 播放页是否启用优选
    Returns:
        ActionResponse: 包含结果数据的工具调用返回，交给LLM进行呈现
    """
    base_url = _get_base_url(conn)
    public_base_url = _get_public_base_url(conn, base_url)

    # 防御：未提供关键词时直接提示
    if not query or not str(query).strip():
        tip = "需要提供影片关键词才能搜索，例如：'在电影资源站搜索 名侦探柯南'。"
        try:
            # 主动推送到前端
            if hasattr(conn, "loop") and conn.loop:
                asyncio.run_coroutine_threadsafe(
                    conn.output_processor.send_llm_stream_response_message(tip, True),
                    conn.loop,
                )
        except Exception:
            pass
        return ActionResponse(Action.RESPONSE, "缺少关键词", tip)

    password = _get_password(conn)
    results = _fetch_search(base_url, query, password=password)
    if not results:
        return ActionResponse(
            Action.REQLLM,
            f"未在电影资源站中搜索到与'{query}'匹配的结果。可尝试补充年份或更短关键词。",
            None,
        )

    # 截断
    results = results[: max(1, int(top_k))]

    # 按相似度重排（支持模糊搜索），并以20%为最低阈值
    MIN_SIMILARITY = 0.2
    results = sorted(
        results,
        key=lambda r: _score_item(query, _safe_get(r, "title")),
        reverse=True,
    )
    results = [r for r in results if _score_item(query, _safe_get(r, "title")) >= MIN_SIMILARITY]

    enriched: List[Dict[str, Any]] = []
    for r in results:
        item = {
            "title": _safe_get(r, "title"),
            "year": _safe_get(r, "year"),
            "source": _safe_get(r, "source"),
            "source_name": _safe_get(r, "source_name"),
            "id": _safe_get(r, "id"),
            "poster": _safe_get(r, "poster"),
            "type_name": _safe_get(r, "type_name"),
            "episodes": r.get("episodes", []) or [],
        }
        # 链接使用公网可访问地址
        item["detail_api"] = _build_detail_api(public_base_url, item)
        item["play_url"] = _build_play_url(public_base_url, item, prefer=prefer)
        enriched.append(item)

    # 截断到 top_k
    enriched = enriched[: max(1, int(top_k))]

    # 以更易读的格式直接返回，并隐藏真实播放链接内容，仅提供可点击的名字
    lines = []
    for it in enriched:
        title = it.get("title", "未知标题")
        year = it.get("year", "未知")
        play_url = it.get("play_url", "")
        lines.append(
            f"{title}\n\n年份：{year}\n类型：{it.get('type_name', '未知')}\n播放地址：[点击播放]({play_url})\n"
        )

    response_text = "\n\n".join(lines).strip()

    # 直接返回，不再交给LLM总结
    try:
        # 同步推送到前端，保证前端能及时渲染
        if hasattr(conn, "loop") and conn.loop:
            asyncio.run_coroutine_threadsafe(
                conn.output_processor.send_llm_stream_response_message(response_text, True),
                conn.loop,
            )
    except Exception:
        pass

    return ActionResponse(
        Action.RESPONSE,
        {"query": query, "base_url": public_base_url, "results": enriched},
        response_text,
    )
