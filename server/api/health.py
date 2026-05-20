"""
健康检查API模块

提供服务健康状态检查和监控功能。
"""

from datetime import datetime
from typing import Any, Dict, Optional

from config.logger import setup_logging
from core.global_services import GlobalServices
from core.version import VersionManager, CompatibilityCheckResult, CompatibilityStatus
from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel

router = APIRouter()
logger = setup_logging()
TAG = __name__


class HealthResponse(BaseModel):
    """健康检查响应模型"""

    status: str
    message: str
    timestamp: str
    uptime: str
    version: str
    active_connections: int
    services_status: Dict[str, Any]
    # 版本兼容性信息
    version_info: Optional[Dict[str, Any]] = None
    # 升级警告（当客户端版本不兼容时返回）
    upgrade_warning: Optional[Dict[str, Any]] = None


class DetailedHealthResponse(BaseModel):
    """详细健康检查响应模型"""

    status: str
    message: str
    timestamp: str
    uptime: str
    version: str
    active_connections: int
    services_status: Dict[str, Any]
    system_info: Dict[str, Any]
    performance_metrics: Dict[str, Any]


@router.get("/health", response_model=HealthResponse)
async def health_check():
    """
    基础健康检查

    检查默认客户端版本的兼容性，如果不兼容则返回升级警告。

    Returns:
        HealthResponse: 服务健康状态信息
    """
    try:
        # 获取全局服务状态
        services_status = GlobalServices.get_service_status()
        active_connections = GlobalServices.get_active_connections_count()

        # 获取动态版本号和版本兼容性信息
        server_version = VersionManager.get_server_version()
        supported_versions = VersionManager.get_supported_versions()

        # 检查默认客户端版本兼容性
        config = VersionManager._load_config()
        default_client_version = config.get("default_client_version")
        upgrade_warning = None

        if default_client_version:
            # 检查默认客户端版本是否兼容
            compatibility_result = VersionManager.check_client_compatibility(
                default_client_version,
                "ios"  # 默认平台，后续可以从配置读取
            )

            # 如果不兼容或需要更新，添加警告
            if compatibility_result.status != CompatibilityStatus.COMPATIBLE:
                upgrade_warning = {
                    "status": compatibility_result.status.value,
                    "message": compatibility_result.message,
                    "current_version": compatibility_result.client_version,
                    "download_url": compatibility_result.download_url,
                }

        return HealthResponse(
            status="healthy",
            message="FastAPI统一服务运行正常",
            timestamp=datetime.utcnow().isoformat(),
            uptime="运行中",  # TODO: 实现实际运行时间计算
            version=server_version,
            active_connections=active_connections,
            services_status=services_status,
            version_info={
                "server_version": server_version,
                "min_client_version": supported_versions["min_client_version"],
                "max_client_version": supported_versions["max_client_version"],
                "recommended_client_version": supported_versions.get("recommended_client_version", ""),
            },
            upgrade_warning=upgrade_warning,
        )

    except Exception as e:
        logger.bind(tag=TAG).error(f"健康检查失败: {e}")
        raise HTTPException(
            status_code=503,
            detail={
                "status": "unhealthy",
                "message": "服务健康检查失败",
                "error": str(e),
                "timestamp": datetime.utcnow().isoformat(),
            },
        )


@router.get("/health/detailed", response_model=DetailedHealthResponse)
async def detailed_health_check():
    """
    详细健康检查

    Returns:
        DetailedHealthResponse: 详细的健康状态信息
    """
    try:
        # 获取基本健康信息
        services_status = GlobalServices.get_service_status()
        active_connections = GlobalServices.get_active_connections_count()
        connection_ids = GlobalServices.get_connection_ids()

        # 系统信息
        import platform

        import psutil

        system_info = {
            "platform": platform.platform(),
            "python_version": platform.python_version(),
            "cpu_count": psutil.cpu_count(),
            "memory_total": f"{psutil.virtual_memory().total // (1024**3)}GB",
            "memory_available": f"{psutil.virtual_memory().available // (1024**3)}GB",
            "disk_usage": f"{psutil.disk_usage('/').percent}%",
        }

        # 性能指标
        performance_metrics = {
            "cpu_percent": psutil.cpu_percent(interval=1),
            "memory_percent": psutil.virtual_memory().percent,
            "active_connections": active_connections,
            "connection_ids": connection_ids[:10] if connection_ids else [],  # 只显示前10个
        }

        return DetailedHealthResponse(
            status="healthy",
            message="FastAPI统一服务详细状态正常",
            timestamp=datetime.utcnow().isoformat(),
            uptime="运行中",  # TODO: 实现实际运行时间计算
            version="1.0.0",
            active_connections=active_connections,
            services_status=services_status,
            system_info=system_info,
            performance_metrics=performance_metrics,
        )

    except Exception as e:
        logger.bind(tag=TAG).error(f"详细健康检查失败: {e}")
        raise HTTPException(
            status_code=503,
            detail={
                "status": "unhealthy",
                "message": "服务详细健康检查失败",
                "error": str(e),
                "timestamp": datetime.utcnow().isoformat(),
            },
        )


@router.get("/health/ready")
async def readiness_check():
    """
    就绪检查

    检查服务是否准备好接受请求。

    Returns:
        Dict[str, Any]: 就绪状态信息
    """
    try:
        # 检查全局服务是否已初始化
        services_status = GlobalServices.get_service_status()

        if services_status.get("status") != "initialized":
            raise HTTPException(
                status_code=503,
                detail={
                    "ready": False,
                    "message": "服务尚未完成初始化",
                    "timestamp": datetime.utcnow().isoformat(),
                },
            )

        return {
            "ready": True,
            "message": "服务已准备就绪",
            "timestamp": datetime.utcnow().isoformat(),
            "services_status": services_status,
        }

    except HTTPException:
        raise
    except Exception as e:
        logger.bind(tag=TAG).error(f"就绪检查失败: {e}")
        raise HTTPException(
            status_code=503,
            detail={
                "ready": False,
                "message": "就绪检查失败",
                "error": str(e),
                "timestamp": datetime.utcnow().isoformat(),
            },
        )


@router.get("/health/live")
async def liveness_check():
    """
    存活检查

    简单的存活检查，用于容器编排系统。

    Returns:
        Dict[str, Any]: 存活状态信息
    """
    return {"alive": True, "message": "服务正在运行", "timestamp": datetime.utcnow().isoformat()}


@router.get("/metrics")
async def get_metrics():
    """
    获取服务指标

    Returns:
        Dict[str, Any]: 服务性能指标
    """
    try:
        import psutil

        # 基本系统指标
        metrics = {
            "timestamp": datetime.utcnow().isoformat(),
            "connections": {
                "active": GlobalServices.get_active_connections_count(),
                "total_created": len(GlobalServices.get_connection_ids()),
            },
            "system": {
                "cpu_percent": psutil.cpu_percent(interval=1),
                "memory": {
                    "total": psutil.virtual_memory().total,
                    "available": psutil.virtual_memory().available,
                    "percent": psutil.virtual_memory().percent,
                    "used": psutil.virtual_memory().used,
                },
                "disk": {
                    "total": psutil.disk_usage("/").total,
                    "used": psutil.disk_usage("/").used,
                    "free": psutil.disk_usage("/").free,
                    "percent": psutil.disk_usage("/").percent,
                },
            },
            "services": GlobalServices.get_service_status(),
        }

        return metrics

    except Exception as e:
        logger.bind(tag=TAG).error(f"获取指标失败: {e}")
        raise HTTPException(
            status_code=500,
            detail={
                "message": "获取服务指标失败",
                "error": str(e),
                "timestamp": datetime.utcnow().isoformat(),
            },
        )
