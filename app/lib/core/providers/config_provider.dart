import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:ai_assistant/core/models/diy_config.dart';
import 'package:ai_assistant/core/models/dify_config.dart';
import 'package:ai_assistant/core/models/chat_service_config.dart';
import 'package:ai_assistant/core/models/server_model_config.dart';
import 'package:ai_assistant/core/utils/app_logger.dart';
import 'package:ai_assistant/core/api/modules_api.dart';
import 'package:ai_assistant/core/services/modules_cache_service.dart';
import 'package:ai_assistant/core/services/mac_address_service.dart';
import 'dart:async'; // 导入async

class ConfigProvider extends ChangeNotifier {
  List<DiyConfig> _diyConfigs = [];
  List<DifyConfig> _difyConfigs = [];
  String? _selectedDiyConfigId;
  bool _isLoaded = false;
  final Completer<void> _configsLoadedCompleter =
      Completer<void>(); // 添加Completer

  // 服务器模型配置管理
  final Map<String, ServerModelConfig> _serverModelConfigs = {};

  List<DiyConfig> get diyConfigs => _diyConfigs;
  List<DifyConfig> get difyConfigs => _difyConfigs;
  DifyConfig? get difyConfig =>
      _difyConfigs.isNotEmpty ? _difyConfigs.first : null;
  bool get isLoaded => _isLoaded;
  Future<void> get configsLoaded => _configsLoadedCompleter.future; // 添加getter

  /// 获取服务器模型配置的只读视图
  Map<String, ServerModelConfig> get serverModelConfigs {
    return Map.unmodifiable(_serverModelConfigs);
  }

  DiyConfig? get selectedDiyConfig {
    if (_diyConfigs.isEmpty) {
      return null;
    }

    if (_selectedDiyConfigId != null) {
      try {
        return _diyConfigs.firstWhere(
          (config) => config.id == _selectedDiyConfigId,
        );
      } catch (e) {
        // 如果找不到匹配的ID（例如，数据不一致），则返回第一个作为后备
        return _diyConfigs.first;
      }
    }
    // 如果没有选中的ID，也返回第一个
    return _diyConfigs.first;
  }

  ConfigProvider() {
    _loadConfigs();
  }

  Future<void> _loadConfigs() async {
    final prefs = await SharedPreferences.getInstance();

    // Load Diy configs
    final diyConfigsJson = prefs.getStringList('diyConfigs') ?? [];
    _diyConfigs =
        diyConfigsJson
            .map((json) => DiyConfig.fromJson(jsonDecode(json)))
            .toList();
    _selectedDiyConfigId = prefs.getString('selectedDiyConfigId');

    // 加载多个Dify配置
    final difyConfigsJson = prefs.getStringList('difyConfigs') ?? [];
    _difyConfigs =
        difyConfigsJson
            .map((json) => DifyConfig.fromJson(jsonDecode(json)))
            .toList();

    // 向后兼容：加载旧版单个Dify配置
    final oldDifyConfigJson = prefs.getString('difyConfig');
    if (oldDifyConfigJson != null && _difyConfigs.isEmpty) {
      final oldConfig = DifyConfig.fromJson(jsonDecode(oldDifyConfigJson));
      // 添加ID和名称，转换为新格式
      final updatedConfig = DifyConfig(
        id: const Uuid().v4(),
        name: "默认Dify",
        apiUrl: oldConfig.apiUrl,
        apiKey: oldConfig.apiKey,
      );
      _difyConfigs.add(updatedConfig);

      // 保存为新格式并删除旧数据
      await _saveConfigs();
      await prefs.remove('difyConfig');
    }

    _isLoaded = true;
    if (!_configsLoadedCompleter.isCompleted) {
      _configsLoadedCompleter.complete(); // 完成Completer
    }
    // 加载服务器模型配置
    await _loadModelConfigs();
    notifyListeners();
  }

  Future<void> _saveConfigs() async {
    final prefs = await SharedPreferences.getInstance();

    // Save Diy configs
    final diyConfigsJson =
        _diyConfigs.map((config) => jsonEncode(config.toJson())).toList();
    await prefs.setStringList('diyConfigs', diyConfigsJson);
    if (_selectedDiyConfigId != null) {
      await prefs.setString(
        'selectedDiyConfigId',
        _selectedDiyConfigId!,
      );
    }

    // 保存多个Dify配置
    final difyConfigsJson =
        _difyConfigs.map((config) => jsonEncode(config.toJson())).toList();
    await prefs.setStringList('difyConfigs', difyConfigsJson);
  }

  Future<void> addDiyConfig(
    String name,
    String websocketUrl, {
    String? customMacAddress,
    String? token,
    ServiceIcon? icon,
  }) async {
    // 检查名称重复，自动添加序号
    final uniqueName = _generateUniqueConfigName(name);

    // 如果提供了自定义MAC地址，使用自定义值；否则使用服务获取
    final macAddress = customMacAddress ?? await MacAddressService().getMacAddress();

    final newConfig = DiyConfig(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: uniqueName,  // 使用处理后的名称
      websocketUrl: websocketUrl,
      macAddress: macAddress,
      token: token ?? '',
      icon: icon ?? const ServiceIcon(
        iconData: Icons.smart_toy,
        backgroundColor: Color(0xFF9C27B0),
        iconColor: Color(0xFFFFFFFF),
      ),
    );

    _diyConfigs.add(newConfig);
    // 如果是第一个配置，则自动选中
    if (_diyConfigs.length == 1) {
      await selectDiyConfig(newConfig.id);
    }
    await _saveConfigs();
    notifyListeners();

    // 自动同步模型配置
    try {
      final response = await ModulesApi.fetchModules(websocketUrl);

      // 缓存模型列表
      await ModulesCacheService.cacheModules(newConfig.id, response.modules);

      // 使用默认配置创建 ServerModelConfig
      final serverConfig = ServerModelConfig(
        serverId: newConfig.id,
        selectedModels: response.defaultSelectedModule,
      );

      // 保存配置
      await updateModelConfig(serverConfig);
      logI('自动同步模型配置成功: ${newConfig.name}');
    } catch (e) {
      // 错误不阻塞配置添加
      logE('获取模型配置失败: $e');
    }
  }

  Future<void> updateDiyConfig(DiyConfig updatedConfig) async {
    final index = _diyConfigs.indexWhere(
      (config) => config.id == updatedConfig.id,
    );
    if (index != -1) {
      _diyConfigs[index] = updatedConfig;
      await _saveConfigs();
      notifyListeners();
    }
  }

  Future<void> deleteDiyConfig(String id) async {
    _diyConfigs.removeWhere((config) => config.id == id);

    // 如果删除的是当前选中的配置，则重置选中状态
    if (_selectedDiyConfigId == id) {
      _selectedDiyConfigId =
          _diyConfigs.isNotEmpty ? _diyConfigs.first.id : null;
    }

    // 级联删除对应的模型配置
    await _clearModelConfig(id);

    await _saveConfigs();
    notifyListeners();

    // 通知所有使用此配置的对话
    // ConversationProvider 会通过 listener 感知变化
    logI('已删除配置 $id，所有相关对话将标记为配置缺失');
  }

  Future<void> selectDiyConfig(String id) async {
    if (_diyConfigs.any((config) => config.id == id)) {
      _selectedDiyConfigId = id;
      await _saveConfigs();
      notifyListeners();
    }
  }

  // 添加Dify配置
  Future<void> addDifyConfig(
    String name,
    String apiKey,
    String apiUrl, {
    ServiceIcon? icon,
  }) async {
    final newConfig = DifyConfig(
      id: const Uuid().v4(),
      name: name,
      apiUrl: apiUrl,
      apiKey: apiKey,
      icon: icon ?? const ServiceIcon(
        iconData: Icons.chat_bubble_outline,
        backgroundColor: Color(0xFF2196F3),
        iconColor: Color(0xFFFFFFFF),
      ),
    );

    _difyConfigs.add(newConfig);
    await _saveConfigs();
    notifyListeners();
  }

  // 更新Dify配置
  Future<void> updateDifyConfig(DifyConfig updatedConfig) async {
    final index = _difyConfigs.indexWhere(
      (config) => config.id == updatedConfig.id,
    );
    if (index != -1) {
      _difyConfigs[index] = updatedConfig;
      await _saveConfigs();
      notifyListeners();
    }
  }

  // 删除Dify配置
  Future<void> deleteDifyConfig(String id) async {
    _difyConfigs.removeWhere((config) => config.id == id);
    await _saveConfigs();
    notifyListeners();
  }

  // 向后兼容的旧方法，设置第一个Dify配置
  Future<void> setDifyConfig(String apiKey, String apiUrl) async {
    if (_difyConfigs.isEmpty) {
      await addDifyConfig("默认Dify", apiKey, apiUrl);
    } else {
      final updated = _difyConfigs.first.copyWith(
        apiKey: apiKey,
        apiUrl: apiUrl,
      );
      await updateDifyConfig(updated);
    }
  }

  /// 检查配置名称是否重复
  bool _isConfigNameExists(String name, {String? excludeId}) {
    return _diyConfigs.any((config) =>
      config.name == name && config.id != excludeId
    );
  }

  /// 生成唯一的配置名称
  String _generateUniqueConfigName(String baseName) {
    if (!_isConfigNameExists(baseName)) {
      return baseName;
    }

    // 查找已有序号的最大值
    int maxSuffix = 0;
    final regex = RegExp(r'^' + RegExp.escape(baseName) + r' \((\d+)\)$');

    for (final config in _diyConfigs) {
      final match = regex.firstMatch(config.name);
      if (match != null) {
        final suffix = int.parse(match.group(1)!);
        if (suffix > maxSuffix) {
          maxSuffix = suffix;
        }
      }
    }

    return '$baseName (${maxSuffix + 1})';
  }

  /// 获取指定服务器的模型配置
  ServerModelConfig? getModelConfig(String serverId) {
    return _serverModelConfigs[serverId];
  }

  /// 更新服务器模型配置
  Future<void> updateModelConfig(ServerModelConfig config) async {
    _serverModelConfigs[config.serverId] = config;
    await _saveModelConfigs();
    notifyListeners();
  }

  /// 加载服务器模型配置
  Future<void> _loadModelConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    const key = 'server_model_configs';
    final data = prefs.getString(key);
    if (data != null) {
      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        _serverModelConfigs.clear();
        json.forEach((key, value) {
          _serverModelConfigs[key] = ServerModelConfig.fromJson(
            value as Map<String, dynamic>,
          );
        });
      } catch (e) {
        logE('加载模型配置失败: $e');
      }
    }
  }

  /// 保存服务器模型配置
  Future<void> _saveModelConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    const key = 'server_model_configs';
    final json = <String, dynamic>{};
    _serverModelConfigs.forEach((key, value) {
      json[key] = value.toJson();
    });
    await prefs.setString(key, jsonEncode(json));
  }

  /// 清除指定服务器的模型配置
  Future<void> _clearModelConfig(String serverId) async {
    _serverModelConfigs.remove(serverId);
    await _saveModelConfigs();
  }
}
