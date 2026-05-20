import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:ai_assistant/core/utils/app_logger.dart';

/// MAC地址服务
///
/// 负责设备MAC地址的生成、持久化和获取
class MacAddressService {
  /// SharedPreferences中存储MAC地址的key
  static const String _macAddressKey = 'device_mac_address';

  /// 最大重试次数
  static const int _maxRetries = 3;

  /// 单例实例
  static final MacAddressService _instance = MacAddressService._internal();
  factory MacAddressService() => _instance;
  MacAddressService._internal();

  /// 获取设备MAC地址
  ///
  /// 首次调用时生成并持久化，后续调用直接从缓存读取
  /// 如果缓存不存在，则重新生成并持久化
  Future<String> getMacAddress() async {
    final prefs = await SharedPreferences.getInstance();

    // 尝试从缓存读取
    final cachedMacAddress = prefs.getString(_macAddressKey);
    if (cachedMacAddress != null && cachedMacAddress.isNotEmpty) {
      logI('从缓存读取MAC地址: $cachedMacAddress');
      return cachedMacAddress;
    }

    // 缓存不存在，生成新的MAC地址
    logI('缓存中无MAC地址，开始生成...');
    final macAddress = await _generateMacAddressWithRetry();

    // 持久化存储
    await prefs.setString(_macAddressKey, macAddress);
    logI('MAC地址已持久化: $macAddress');

    return macAddress;
  }

  /// 生成MAC地址（带重试机制）
  Future<String> _generateMacAddressWithRetry() async {
    for (int i = 1; i <= _maxRetries; i++) {
      try {
        logI('尝试获取设备信息 (第$i次/$_maxRetries)');
        final deviceId = await _getDeviceId();

        if (deviceId.isEmpty) {
          throw Exception('获取到的设备ID为空');
        }

        // 生成MAC地址
        final macAddress = _generateMacFromDeviceId(deviceId);
        logI('成功生成MAC地址: $macAddress');
        return macAddress;

      } catch (e) {
        logW('第$i次获取设备信息失败: $e');

        if (i >= _maxRetries) {
          logE('达到最大重试次数，仍然无法获取设备信息');
          throw Exception(
            '无法获取设备信息以生成MAC地址，请确保应用已获得必要的权限。'
          );
        }

        // 等待一小段时间后重试
        await Future.delayed(Duration(milliseconds: 500 * i));
      }
    }

    // 理论上不会执行到这里
    throw Exception('生成MAC地址失败');
  }

  /// 获取设备ID
  Future<String> _getDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();

    try {
      // 尝试获取Android设备ID
      final androidInfo = await deviceInfo.androidInfo;
      final deviceId = androidInfo.id;
      if (deviceId.isNotEmpty) {
        logI('获取到Android设备ID');
        return deviceId;
      }
    } catch (e) {
      logW('获取Android设备ID失败: $e');
    }

    try {
      // 尝试获取iOS设备ID
      final iosInfo = await deviceInfo.iosInfo;
      final deviceId = iosInfo.identifierForVendor ?? '';
      if (deviceId.isNotEmpty) {
        logI('获取到iOS设备ID');
        return deviceId;
      }
    } catch (e) {
      logW('获取iOS设备ID失败: $e');
    }

    try {
      // 尝试获取Web浏览器信息
      final webInfo = await deviceInfo.webBrowserInfo;
      final deviceId = webInfo.userAgent ?? '';
      if (deviceId.isNotEmpty) {
        logI('获取到Web设备信息');
        return deviceId;
      }
    } catch (e) {
      logW('获取Web设备信息失败: $e');
    }

    throw Exception('无法从任何平台获取设备ID');
  }

  /// 从设备ID生成MAC地址
  String _generateMacFromDeviceId(String deviceId) {
    final bytes = utf8.encode(deviceId);
    final digest = md5.convert(bytes);
    final hash = digest.toString();

    // 格式化为MAC地址格式 (XX:XX:XX:XX:XX:XX)
    final List<String> macParts = [];
    for (int i = 0; i < 6; i++) {
      macParts.add(hash.substring(i * 2, i * 2 + 2));
    }

    return macParts.join(':');
  }

  /// 清除持久化的MAC地址（用于测试或重置）
  Future<void> clearMacAddress() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_macAddressKey);
    logI('已清除持久化的MAC地址');
  }

  /// 检查是否已有持久化的MAC地址
  Future<bool> hasMacAddress() async {
    final prefs = await SharedPreferences.getInstance();
    final macAddress = prefs.getString(_macAddressKey);
    return macAddress != null && macAddress.isNotEmpty;
  }
}
