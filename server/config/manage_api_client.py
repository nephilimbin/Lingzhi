from abc import ABC
import os
import time
from typing import Any, Dict, Optional

import httpx

TAG = __name__


class DeviceNotFoundException(Exception):
    """设备未找到异常"""

    pass


class DeviceBindException(Exception):
    """设备绑定异常"""

    def __init__(self, bind_code: str):
        self.bind_code = bind_code
        super().__init__(f"设备绑定异常，绑定码: {bind_code}")


class HttpClient:
    """HTTP客户端管理类，负责网络连接和重试逻辑"""

    def __init__(
        self, base_url: str, timeout: int = 30, max_retries: int = 6, retry_delay: int = 10
    ):
        self.base_url = base_url
        self.timeout = timeout
        self.max_retries = max_retries
        self.retry_delay = retry_delay

        self._client = httpx.Client(
            base_url=base_url,
            headers={
                "User-Agent": f"PythonClient/2.0 (PID:{os.getpid()})",
                "Accept": "application/json",
            },
            timeout=timeout,
        )

    def _should_retry(self, exception: Exception) -> bool:
        """判断异常是否应该重试"""
        if isinstance(exception, (httpx.ConnectError, httpx.TimeoutException, httpx.NetworkError)):
            return True

        if isinstance(exception, httpx.HTTPStatusError):
            return exception.response.status_code in [408, 429, 500, 502, 503, 504]

        return False

    def _make_single_request(self, method: str, endpoint: str, **kwargs) -> httpx.Response:
        """发送单次HTTP请求"""
        endpoint = endpoint.lstrip("/")
        response = self._client.request(method, endpoint, **kwargs)
        response.raise_for_status()
        return response

    def request(self, method: str, endpoint: str, **kwargs) -> httpx.Response:
        """带重试机制的HTTP请求"""
        retry_count = 0

        while retry_count <= self.max_retries:
            try:
                return self._make_single_request(method, endpoint, **kwargs)
            except Exception as e:
                if retry_count < self.max_retries and self._should_retry(e):
                    retry_count += 1
                    print(
                        f"{method} {endpoint} 请求失败，将在 {self.retry_delay:.1f} 秒后进行第 {retry_count} 次重试"
                    )
                    time.sleep(self.retry_delay)
                    continue
                else:
                    raise

    def close(self) -> None:
        """关闭HTTP客户端"""
        if self._client:
            self._client.close()


class BaseApiClient(ABC):
    """API客户端基类"""

    def __init__(self, http_client: HttpClient, secret: str):
        self.http_client = http_client
        self.secret = secret

    def _process_response(self, response: httpx.Response) -> Any:
        """处理API响应"""
        result = response.json()

        # 处理API返回的业务错误
        if result.get("code") == 10041:
            raise DeviceNotFoundException(result.get("msg"))
        elif result.get("code") == 10042:
            raise DeviceBindException(result.get("msg"))
        elif result.get("code") != 0:
            raise Exception(f"API返回错误: {result.get('msg', '未知错误')}")

        return result.get("data") if result.get("code") == 0 else None

    def _api_request(self, method: str, endpoint: str, **kwargs) -> Any:
        """执行API请求并处理响应"""
        response = self.http_client.request(method, endpoint, **kwargs)
        return self._process_response(response)


class ManageApiClient(BaseApiClient):
    """管理API客户端，负责具体的API调用"""

    _instance: Optional["ManageApiClient"] = None
    _http_client: Optional[HttpClient] = None

    def __new__(cls, config: Dict[str, Any]) -> "ManageApiClient":
        """单例模式确保全局唯一实例"""
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._initialize_client(config)
        return cls._instance

    @classmethod
    def _initialize_client(cls, config: Dict[str, Any]) -> None:
        """初始化客户端配置"""
        api_config = config.get("manager-api")
        if not api_config:
            raise Exception("manager-api配置错误")

        url = api_config.get("url")
        secret = api_config.get("secret")

        if not url or not secret:
            raise Exception("manager-api的url或secret配置错误")

        if "你" in secret:
            raise Exception("请先配置manager-api的secret")

        # 创建HTTP客户端
        cls._http_client = HttpClient(
            base_url=url,
            timeout=api_config.get("timeout", 30),
            max_retries=api_config.get("max_retries", 6),
            retry_delay=api_config.get("retry_delay", 10),
        )

        # 初始化实例
        cls._instance.__init__(cls._http_client, secret)

    def get_server_config(self) -> Optional[Dict[str, Any]]:
        """获取服务器基础配置"""
        return self._api_request("POST", "/config/server-base", json={"secret": self.secret})

    def get_agent_models(
        self, mac_address: str, client_id: str, selected_module: Dict[str, str]
    ) -> Optional[Dict[str, Any]]:
        """获取代理模型配置"""
        return self._api_request(
            "POST",
            "/config/agent-models",
            json={
                "secret": self.secret,
                "macAddress": mac_address,
                "clientId": client_id,
                "selectedModule": selected_module,
            },
        )

    @classmethod
    def safe_close(cls) -> None:
        """安全关闭连接池"""
        if cls._http_client:
            cls._http_client.close()
            cls._http_client = None
            cls._instance = None


# 全局API客户端实例访问函数
def get_server_config() -> Optional[Dict[str, Any]]:
    """获取服务器基础配置"""
    if ManageApiClient._instance is None:
        raise Exception("ManageApiClient未初始化")
    return ManageApiClient._instance.get_server_config()


def get_agent_models(
    mac_address: str, client_id: str, selected_module: Dict[str, str]
) -> Optional[Dict[str, Any]]:
    """获取代理模型配置"""
    if ManageApiClient._instance is None:
        raise Exception("ManageApiClient未初始化")
    return ManageApiClient._instance.get_agent_models(mac_address, client_id, selected_module)


def init_service(config: Dict[str, Any]) -> None:
    """初始化管理API服务"""
    ManageApiClient(config)


def manage_api_http_safe_close() -> None:
    """安全关闭HTTP连接"""
    ManageApiClient.safe_close()
