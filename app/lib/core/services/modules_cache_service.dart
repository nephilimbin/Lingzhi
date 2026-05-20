import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_assistant/core/models/module_info.dart';

/// 模块缓存服务
///
/// 负责将从后端获取的模块列表缓存到本地SharedPreferences
/// 缓存长期有效，只有手动刷新时才更新
class ModulesCacheService {
  // 私有构造函数，防止实例化
  ModulesCacheService._();

  /// 缓存数据键前缀
  static const String _cacheKeyPrefix = 'cached_modules_';

  /// 缓存时间戳键前缀
  static const String _cacheTimestampKeyPrefix = 'cached_modules_timestamp_';

  /// 获取缓存的模块数据
  ///
  /// [serverId] 服务器ID
  /// 返回模块数据，如果缓存不存在则返回null
  /// 缓存长期有效，不检查过期时间
  static Future<Map<String, List<ModuleInfo>>?> getCachedModules(
    String serverId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = '$_cacheKeyPrefix$serverId';

    final cachedData = prefs.getString(cacheKey);

    // 只要有缓存就直接返回，不检查有效期
    if (cachedData != null) {
      final json = jsonDecode(cachedData) as Map<String, dynamic>;
      return _parseModulesJson(json);
    }
    return null;
  }

  /// 缓存模块数据
  ///
  /// [serverId] 服务器ID
  /// [modules] 要缓存的模块数据
  static Future<void> cacheModules(
    String serverId,
    Map<String, List<ModuleInfo>> modules,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = '$_cacheKeyPrefix$serverId';
    final timestampKey = '$_cacheTimestampKeyPrefix$serverId';

    final json = _serializeModules(modules);
    await prefs.setString(cacheKey, jsonEncode(json));
    await prefs.setInt(timestampKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// 清除指定服务器的缓存
  ///
  /// [serverId] 服务器ID
  static Future<void> clearCache(String serverId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_cacheKeyPrefix$serverId');
    await prefs.remove('$_cacheTimestampKeyPrefix$serverId');
  }

  /// 解析模块JSON数据
  static Map<String, List<ModuleInfo>> _parseModulesJson(
    Map<String, dynamic> json,
  ) {
    final result = <String, List<ModuleInfo>>{};
    for (final entry in json.entries) {
      final list =
          (entry.value as List)
              .map((item) => ModuleInfo.fromJson(item as Map<String, dynamic>))
              .toList();
      result[entry.key] = list;
    }
    return result;
  }

  /// 序列化模块数据
  static Map<String, dynamic> _serializeModules(
    Map<String, List<ModuleInfo>> modules,
  ) {
    final result = <String, dynamic>{};
    for (final entry in modules.entries) {
      result[entry.key] = entry.value.map((m) => m.toJson()).toList();
    }
    return result;
  }
}
