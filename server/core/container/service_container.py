import inspect
from typing import Any, Callable, Dict, Optional, Type, TypeVar

from config.logger import setup_logging

from .service_definitions import SERVICE_DEFINITIONS

T = TypeVar("T")
TAG = __name__


class ServiceContainer:
    """
    服务容器类，统一管理所有服务实例
    实现依赖注入机制，支持单例模式和懒加载
    """

    def __init__(self, config: Dict[str, Any]):
        self.config = config
        self.logger = setup_logging()
        self._services: Dict[str, Any] = {}
        self._service_configs: Dict[str, Dict[str, Any]] = {}
        self._service_factories: Dict[str, Callable] = {}
        self._singletons: Dict[str, bool] = {}
        self._initialized = False
        self._definitions = SERVICE_DEFINITIONS

        # 从定义中注册服务
        self._register_services_from_definitions()

    def _register_services_from_definitions(self):
        """从定义中注册所有服务工厂和单例配置"""
        for definition in self._definitions:
            self._service_factories[definition.name] = definition.factory
            self._singletons[definition.name] = definition.is_singleton

    def initialize_services(self):
        """初始化所有服务"""
        if self._initialized:
            return
        # 预加载服务配置
        self.logger.bind(tag=TAG).info("开始初始化服务容器中的所有服务...")
        self._load_service_configs()

        # 收集初始化失败的服务
        failed_services = []

        # 创建所有服务实例（懒加载，此处仅预热单例）
        for definition in self._definitions:
            if definition.is_singleton:
                try:
                    self.get_service(definition.name)
                except Exception as e:
                    self.logger.bind(tag=TAG).error(f"创建单例服务 {definition.name} 时出错: {e}")
                    failed_services.append((definition.name, str(e)))

        # 如果有服务初始化失败，抛出异常
        if failed_services:
            error_details = "; ".join([f"{name}: {error}" for name, error in failed_services])
            error_msg = f"服务初始化失败: {error_details}"
            self.logger.bind(tag=TAG).error(error_msg)
            raise RuntimeError(error_msg)

        # 验证核心服务是否可用
        self._validate_core_services()

        self._initialized = True
        self.logger.bind(tag=TAG).info("服务容器初始化完成")

    def _validate_core_services(self):
        """
        验证核心服务是否可用

        :raises RuntimeError: 当核心服务不可用时抛出异常
        """
        core_services = [d.name for d in self._definitions if d.is_core]
        missing_services = []

        for service_name in core_services:
            if not self.is_service_available(service_name):
                # 对于单例服务，检查是否在配置中但未创建实例
                if service_name in self._singletons and service_name in self._service_configs:
                    missing_services.append(f"{service_name}(配置存在但实例创建失败)")
                else:
                    missing_services.append(service_name)

        if missing_services:
            error_msg = f"核心服务验证失败，以下服务不可用: {', '.join(missing_services)}"
            self.logger.bind(tag=TAG).error(error_msg)
            raise RuntimeError(error_msg)

        self.logger.bind(tag=TAG).info("所有核心服务验证通过")

    def _load_service_configs(self):
        """加载服务配置"""
        for definition in self._definitions:
            provider_config = self._get_selected_provider_config(definition.config_key)
            provider_type = self._get_provider_type_or_name(definition.config_key)

            if provider_config and provider_type:
                self._service_configs[definition.name] = {
                    "type": provider_type,
                    "config": provider_config,
                }

    def _get_selected_provider_config(
        self, provider_type: str, override_selected_module: Optional[Dict[str, str]] = None
    ) -> Optional[Dict[str, Any]]:
        """
        获取当前选定提供者的配置

        :param provider_type: 提供者类型（如 "asr", "tts", "llm"）
        :param override_selected_module: 覆盖的选中模块配置（用于会话级别的配置更新）
        :return: 提供者配置字典
        """
        # 使用 override_selected_module（如果提供），否则使用全局配置
        selected_module = (
            override_selected_module if override_selected_module is not None else self.config.get("selected_module", {})
        )
        provider_name = selected_module.get(provider_type)
        if not provider_name:
            self.logger.bind(tag=TAG).warning(f"No provider selected for type: {provider_type}")
            return None

        provider_configs = self.config.get(provider_type)
        if not provider_configs or provider_name not in provider_configs:
            self.logger.bind(tag=TAG).warning(f"Configuration not found for {provider_type}: {provider_name}")
            return None

        return provider_configs[provider_name]

    def _get_provider_type_or_name(
        self, provider_type: str, override_selected_module: Optional[Dict[str, str]] = None
    ) -> Optional[str]:
        """
        获取提供者的类型（如果配置中指定）或其名称

        :param provider_type: 提供者类型（如 "asr", "tts", "llm"）
        :param override_selected_module: 覆盖的选中模块配置（用于会话级别的配置更新）
        :return: 提供者类型名称
        """
        selected_config = self._get_selected_provider_config(provider_type, override_selected_module)
        # 使用 override_selected_module（如果提供），否则使用全局配置
        selected_module = (
            override_selected_module if override_selected_module is not None else self.config.get("selected_module", {})
        )

        if not selected_config:
            return selected_module.get(provider_type)

        explicit_type = selected_config.get("type")
        return explicit_type if explicit_type else selected_module.get(provider_type)

    def _create_service(self, service_name: str) -> Optional[Any]:
        """创建服务实例"""
        if service_name not in self._service_configs:
            return None

        config_info = self._service_configs[service_name]
        factory = self._service_factories[service_name]

        service = factory(config_info["type"], config_info["config"])
        if service:
            self.logger.bind(tag=TAG).info(f"成功创建服务: {service_name} (类型: {config_info['type']})")
        return service

    def get_service(self, service_name: str) -> Optional[Any]:
        """获取服务实例"""
        if self._singletons.get(service_name, False) and service_name in self._services:
            return self._services[service_name]

        service = self._create_service(service_name)

        if self._singletons.get(service_name, False) and service:
            self._services[service_name] = service

        return service

    def get_all_services(self) -> Dict[str, Any]:
        """获取所有已创建服务的字典"""
        return self._services

    async def close_all_services(self):
        """关闭所有服务"""
        self.logger.bind(tag=TAG).info("开始关闭所有已创建的服务...")

        for service_name, service in self._services.items():
            if hasattr(service, "close") and callable(getattr(service, "close")):
                try:
                    result = service.close()
                    if inspect.isawaitable(result):
                        await result
                    self.logger.bind(tag=TAG).info(f"服务 {service_name} 已关闭")
                except Exception as e:
                    self.logger.bind(tag=TAG).error(f"关闭服务 {service_name} 时出错: {e}")

        self._services.clear()
        self._initialized = False
        self.logger.bind(tag=TAG).info("所有服务关闭完成")

    def is_service_available(self, service_name: str) -> bool:
        """
        检查服务是否可用（配置存在且实例已创建）

        :param service_name: 服务名称
        :return: 服务是否可用
        """
        # 检查配置是否存在
        if service_name not in self._service_configs:
            return False

        # 对于单例服务，检查实例是否已成功创建
        if service_name in self._singletons:
            return service_name in self._services

        return True

    async def reload_service(
        self, service_name: str, override_selected_module: Optional[Dict[str, str]] = None
    ) -> bool:
        """
        重新加载指定服务（关闭旧实例，创建新实例）

        :param service_name: 服务名称（如 "asr", "tts", "llm", "vad", "vlm", "memory"）
        :param override_selected_module: 覆盖的选中模块配置（用于会话级别的配置更新）
        :return: 是否成功重新加载
        """
        try:
            self.logger.bind(tag=TAG).info(f"==========开始重新加载服务: {service_name}==========")

            # 检查服务是否已注册
            if service_name not in self._service_factories:
                self.logger.bind(tag=TAG).error(f"服务 {service_name} 未在工厂中注册")
                return False

            # 检查是否为单例服务
            if not self._singletons.get(service_name, False):
                self.logger.bind(tag=TAG).warning(f"服务 {service_name} 不是单例服务，无需重新加载")
                return False

            # 关闭旧服务实例
            if service_name in self._services:
                old_service = self._services[service_name]
                if hasattr(old_service, "close") and callable(getattr(old_service, "close")):
                    try:
                        # 检查close方法是否为异步
                        import inspect

                        result = old_service.close()
                        if inspect.isawaitable(result):
                            await result
                    except Exception as e:
                        self.logger.bind(tag=TAG).error(f"关闭旧服务实例 {service_name} 时出错: {e}")
                        return False
                # 从服务字典中移除
                del self._services[service_name]

            # 重新加载服务配置
            definition = next((d for d in self._definitions if d.name == service_name), None)
            if not definition:
                self.logger.bind(tag=TAG).error(f"未找到服务 {service_name} 的定义")
                return False

            # 使用 override_selected_module（如果提供）来获取配置
            provider_config = self._get_selected_provider_config(definition.config_key, override_selected_module)
            provider_type = self._get_provider_type_or_name(definition.config_key, override_selected_module)

            if not provider_config or not provider_type:
                self.logger.bind(tag=TAG).error(f"无法获取服务 {service_name} 的新配置")
                return False

            # 更新服务配置
            self._service_configs[service_name] = {
                "type": provider_type,
                "config": provider_config,
            }

            # 创建新服务实例
            new_service = self._create_service(service_name)
            if new_service:
                self._services[service_name] = new_service
                self.logger.bind(tag=TAG).info(f"服务 {service_name} 重新加载成功 (新类型: {provider_type})")
                return True
            else:
                self.logger.bind(tag=TAG).error(f"创建新服务实例 {service_name} 失败")
                return False

        except Exception as e:
            self.logger.bind(tag=TAG).error(f"重新加载服务 {service_name} 时出错: {e}")
            return False

    @classmethod
    def get_all_provider_config_keys(cls) -> list[str]:
        """获取所有服务提供者的配置键名称

        Returns:
            List[str]: 所有配置键名称列表（如 ["VAD", "ASR", "LLM", "TTS", "Memory"]）
        """

        # 提取所有config_key并去重
        config_keys = [definition.config_key for definition in SERVICE_DEFINITIONS]
        return list(set(config_keys))


class DependencyInjector:
    """
    依赖注入器，通过构造函数签名反射，实现通用的依赖关系管理
    """

    def __init__(self, service_container: ServiceContainer):
        self.service_container = service_container
        self.logger = setup_logging()

    def create(self, target_class: Type[T], **kwargs) -> T:
        """
        通用创建方法，自动解析并注入依赖
        :param target_class: 目标类
        :param kwargs: 需要手动传入的额外参数 (例如 websocket, config)
        :return: 目标类的实例
        """

        # 1. 获取构造函数需要的参数
        constructor_signature = inspect.signature(target_class.__init__)
        required_params = constructor_signature.parameters

        dependencies_to_inject = {}
        missing_services = []

        # 2. 遍历所有需要的参数
        for name, param in required_params.items():
            # 忽略 self, args, kwargs
            if name in ["self", "args", "kwargs"]:
                continue

            # 如果参数已手动提供，则跳过
            if name in kwargs:
                dependencies_to_inject[name] = kwargs[name]
                continue

            # 如果请求的是服务容器本身，则直接注入
            if name == "service_container":
                dependencies_to_inject[name] = self.service_container
                continue

            # 3. 尝试从服务容器中获取服务
            service = self.service_container.get_service(name)
            if service:
                dependencies_to_inject[name] = service
            # 如果服务不存在且参数没有默认值，则记录为缺失
            elif param.default is inspect.Parameter.empty:
                missing_services.append(name)

        # 4. 如果有缺失的服务，则抛出异常
        if missing_services:
            raise RuntimeError(f"无法创建 {target_class.__name__}: 缺少必要的服务或参数: {', '.join(missing_services)}")

        # 5. 使用解析出的依赖创建实例
        try:
            return target_class(**dependencies_to_inject)
        except TypeError as e:
            self.logger.bind(tag=TAG).error(f"创建 {target_class.__name__} 实例时发生类型错误: {e}")
            self.logger.bind(tag=TAG).error(f"预期参数: {list(required_params.keys())}")
            self.logger.bind(tag=TAG).error(f"实际提供参数: {list(dependencies_to_inject.keys())}")
            raise

    def get_service_container(self) -> ServiceContainer:
        """获取服务容器"""
        return self.service_container
