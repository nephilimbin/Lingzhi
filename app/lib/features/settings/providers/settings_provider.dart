import 'package:flutter/material.dart';
import 'package:ai_assistant/core/providers/config_provider.dart';
import 'package:ai_assistant/core/models/diy_config.dart';
import 'package:ai_assistant/core/models/dify_config.dart';
import 'package:ai_assistant/core/models/chat_service_config.dart';
import 'package:ai_assistant/core/models/icon_option.dart';

class SettingsProvider with ChangeNotifier {
  // 自定义配置编辑控制器
  final diyNameController = TextEditingController();
  final diyWebsocketUrlController = TextEditingController();
  final diyMacAddressController = TextEditingController();
  final diyTokenController = TextEditingController();

  // 新增自定义配置控制器
  final newDiyNameController = TextEditingController();
  final newDiyWebsocketUrlController = TextEditingController();
  final newDiyMacAddressController = TextEditingController();
  final newDiyTokenController = TextEditingController();

  // Tab Controller (nullable since ServerSettingsScreen uses its own)
  TabController? tabController;

  // State for Diy config selection
  bool _isDiySelectionMode = false;
  bool get isDiySelectionMode => _isDiySelectionMode;
  final Set<String> _selectedDiyConfigIds = {};
  Set<String> get selectedDiyConfigIds => _selectedDiyConfigIds;

  // State for Dify config selection
  bool _isDifySelectionMode = false;
  bool get isDifySelectionMode => _isDifySelectionMode;
  final Set<String> _selectedDifyConfigIds = {};
  Set<String> get selectedDifyConfigIds => _selectedDifyConfigIds;

  // Controllers for adding/editing configs
  final newDifyNameController = TextEditingController();
  final newDifyApiKeyController = TextEditingController();
  final newDifyApiUrlController = TextEditingController();

  final editDifyNameController = TextEditingController();
  final editDifyApiUrlController = TextEditingController();
  final editDifyApiKeyController = TextEditingController();

  // 选中的图标选项
  IconOption? selectedDiyIcon;
  IconOption? selectedDifyIcon;
  IconOption? editingDiyIcon;
  IconOption? editingDifyIcon;

  void initTabController(TickerProvider vsync) {
    tabController = TabController(length: 3, vsync: vsync);
    tabController?.addListener(() {
      if (tabController?.indexIsChanging ?? false) {
        // Exit selection mode when switching tabs
        if (_isDiySelectionMode) {
          _isDiySelectionMode = false;
          _selectedDiyConfigIds.clear();
        }
        if (_isDifySelectionMode) {
          _isDifySelectionMode = false;
          _selectedDifyConfigIds.clear();
        }
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    tabController?.dispose();
    diyNameController.dispose();
    diyWebsocketUrlController.dispose();
    diyMacAddressController.dispose();
    diyTokenController.dispose();
    newDiyNameController.dispose();
    newDiyWebsocketUrlController.dispose();
    newDiyMacAddressController.dispose();
    newDiyTokenController.dispose();
    newDifyNameController.dispose();
    newDifyApiKeyController.dispose();
    newDifyApiUrlController.dispose();
    editDifyNameController.dispose();
    editDifyApiUrlController.dispose();
    editDifyApiKeyController.dispose();
    super.dispose();
  }

  // --- Diy ---
  void toggleDiySelectionMode() {
    _isDiySelectionMode = !_isDiySelectionMode;
    if (!_isDiySelectionMode) {
      _selectedDiyConfigIds.clear();
    }
    notifyListeners();
  }

  void toggleDiyConfigSelection(String id) {
    if (_selectedDiyConfigIds.contains(id)) {
      _selectedDiyConfigIds.remove(id);
    } else {
      _selectedDiyConfigIds.add(id);
    }
    notifyListeners();
  }

  void clearDiySelections() {
    _selectedDiyConfigIds.clear();
    _isDiySelectionMode = false;
    notifyListeners();
  }

  void setAllDiySelections(List<DiyConfig> configs) {
    _selectedDiyConfigIds.clear();
    _selectedDiyConfigIds.addAll(configs.map((c) => c.id));
    notifyListeners();
  }

  // --- Dify ---
  void toggleDifySelectionMode() {
    _isDifySelectionMode = !_isDifySelectionMode;
    if (!_isDifySelectionMode) {
      _selectedDifyConfigIds.clear();
    }
    notifyListeners();
  }

  void toggleDifyConfigSelection(String id) {
    if (_selectedDifyConfigIds.contains(id)) {
      _selectedDifyConfigIds.remove(id);
    } else {
      _selectedDifyConfigIds.add(id);
    }
    notifyListeners();
  }

  void clearDifySelections() {
    _selectedDifyConfigIds.clear();
    _isDifySelectionMode = false;
    notifyListeners();
  }

  void clearDifyControllers() {
    newDifyNameController.clear();
    newDifyApiKeyController.clear();
    newDifyApiUrlController.clear();
  }

  void loadDifyConfigForEditing(DifyConfig config) {
    editDifyNameController.text = config.name;
    editDifyApiUrlController.text = config.apiUrl;
    editDifyApiKeyController.text = config.apiKey;
  }

  void toggleSelectAllDify(List<DifyConfig> allConfigs) {
    if (_selectedDifyConfigIds.length == allConfigs.length) {
      _selectedDifyConfigIds.clear();
    } else {
      _selectedDifyConfigIds.addAll(allConfigs.map((c) => c.id));
    }
    notifyListeners();
  }

  void toggleSelectAllDiy(List<String> allConfigIds) {
    if (_selectedDiyConfigIds.length == allConfigIds.length) {
      _selectedDiyConfigIds.clear();
    } else {
      _selectedDiyConfigIds.addAll(allConfigIds);
    }
    notifyListeners();
  }

  Future<void> addDifyConfig(ConfigProvider configProvider) async {
    final name = newDifyNameController.text.trim();
    final apiUrl = newDifyApiUrlController.text.trim();
    final apiKey = newDifyApiKeyController.text.trim();

    if (name.isEmpty || apiUrl.isEmpty || apiKey.isEmpty) {
      throw Exception('请填写所有字段');
    }

    /// 创建服务图标配置
    final serviceIcon =
        selectedDifyIcon != null
            ? ServiceIcon(
              iconData: selectedDifyIcon!.icon,
              backgroundColor: selectedDifyIcon!.backgroundColor,
              iconColor: selectedDifyIcon!.iconColor,
            )
            : null;

    await configProvider.addDifyConfig(name, apiKey, apiUrl, icon: serviceIcon);
    clearDifyControllers();
    selectedDifyIcon = null; // 清除图标选择
  }

  Future<void> updateDifyConfig(
    ConfigProvider configProvider,
    String id,
  ) async {
    final name = newDifyNameController.text.trim();
    final apiUrl = newDifyApiUrlController.text.trim();
    final apiKey = newDifyApiKeyController.text.trim();

    if (name.isEmpty || apiUrl.isEmpty || apiKey.isEmpty) {
      throw Exception('请填写所有字段');
    }

    /// 创建服务图标配置，如果用户选择了新图标则使用新图标，否则使用默认图标
    final serviceIcon =
        editingDifyIcon != null
            ? ServiceIcon(
              iconData: editingDifyIcon!.icon,
              backgroundColor: editingDifyIcon!.backgroundColor,
              iconColor: editingDifyIcon!.iconColor,
            )
            : const ServiceIcon(
              iconData: Icons.chat_bubble_outline,
              backgroundColor: Color(0xFF2196F3),
              iconColor: Color(0xFFFFFFFF),
            );

    final updatedConfig = DifyConfig(
      id: id,
      name: name,
      apiUrl: apiUrl,
      apiKey: apiKey,
      icon: serviceIcon,
    );

    await configProvider.updateDifyConfig(updatedConfig);
    clearDifyControllers();
    editingDifyIcon = null; // 清除编辑图标选择
  }

  Future<void> deleteDifyConfig(
    ConfigProvider configProvider,
    String id,
  ) async {
    await configProvider.deleteDifyConfig(id);
  }

  Future<void> batchDeleteDifyConfigs(ConfigProvider configProvider) async {
    final idsToDelete = List<String>.from(_selectedDifyConfigIds);
    for (final id in idsToDelete) {
      await configProvider.deleteDifyConfig(id);
    }
    clearDifySelections();
  }

  Future<void> deleteDiyConfig(
    ConfigProvider configProvider,
    String id,
  ) async {
    await configProvider.deleteDiyConfig(id);
    // No need to call notifyListeners() here because ConfigProvider will do it,
    // and the UI will rebuild automatically.
  }

  Future<void> batchDeleteDiyConfigs(ConfigProvider configProvider) async {
    final idsToDelete = List<String>.from(_selectedDiyConfigIds);
    for (final id in idsToDelete) {
      await configProvider.deleteDiyConfig(id);
    }
    clearDiySelections();
  }

  // 更新编辑表单的控制器
  void loadDiyConfigForEditing(DiyConfig config) {
    diyNameController.text = config.name;
    diyWebsocketUrlController.text = config.websocketUrl;
    diyMacAddressController.text = config.macAddress;
    diyTokenController.text = config.token;
  }

  void clearDiyControllers() {
    newDiyNameController.clear();
    newDiyWebsocketUrlController.clear();
    newDiyMacAddressController.clear();
    newDiyTokenController.clear();
  }

  // 添加新的自定义配置
  Future<void> addDiyConfig(ConfigProvider configProvider) async {
    final name = newDiyNameController.text.trim();
    final websocketUrl = newDiyWebsocketUrlController.text.trim();
    final macAddress = newDiyMacAddressController.text.trim();
    final token = newDiyTokenController.text.trim();

    if (name.isEmpty || websocketUrl.isEmpty) {
      throw Exception('请填写所有必填字段');
    }

    /// 创建服务图标配置
    final serviceIcon =
        selectedDiyIcon != null
            ? ServiceIcon(
              iconData: selectedDiyIcon!.icon,
              backgroundColor: selectedDiyIcon!.backgroundColor,
              iconColor: selectedDiyIcon!.iconColor,
            )
            : null;

    await configProvider.addDiyConfig(
      name,
      websocketUrl,
      customMacAddress: macAddress.isNotEmpty ? macAddress : null,
      token: token.isNotEmpty ? token : null,
      icon: serviceIcon,
    );

    newDiyNameController.clear();
    newDiyWebsocketUrlController.clear();
    newDiyMacAddressController.clear();
    newDiyTokenController.clear();
    selectedDiyIcon = null; // 清除图标选择
    notifyListeners();
  }

  // 更新现有的自定义配置
  Future<void> updateDiyConfig(
    ConfigProvider configProvider,
    DiyConfig oldConfig,
  ) async {
    /// 创建服务图标配置，如果用户选择了新图标则使用新图标，否则保留原配置的图标
    ServiceIcon? serviceIcon;
    if (editingDiyIcon != null) {
      serviceIcon = ServiceIcon(
        iconData: editingDiyIcon!.icon,
        backgroundColor: editingDiyIcon!.backgroundColor,
        iconColor: editingDiyIcon!.iconColor,
      );
    } else {
      serviceIcon = oldConfig.icon;
    }

    final updatedConfig = oldConfig.copyWith(
      name: diyNameController.text.trim(),
      websocketUrl: diyWebsocketUrlController.text.trim(),
      macAddress: diyMacAddressController.text.trim(),
      token: diyTokenController.text.trim(),
      icon: serviceIcon,
    );
    await configProvider.updateDiyConfig(updatedConfig);
    editingDiyIcon = null; // 清除编辑图标选择
    notifyListeners();
  }
}
