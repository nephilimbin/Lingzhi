import 'package:uuid/uuid.dart';

/// 统一的唯一ID生成器
/// 参考后端 server/core/utils/util.py::set_unique_id
class IdGenerator {
  // 私有构造函数，防止实例化
  IdGenerator._();

  static final Uuid _uuid = Uuid();

  /// 生成唯一ID
  /// 格式: {type}_{timestamp}_{uuid4_hex}
  ///
  /// 参数:
  /// - type: ID类型，如 'hello', 'listen', 'abort' 等
  /// - timestamp: 可选的时间戳，如果不提供则使用当前时间
  /// - random: 可选的随机字符串，如果不提供则使用UUID4的hex格式
  ///
  /// 返回: 唯一ID字符串，如 "hello_20250103123456_1a2b3c4d5e6f7890"
  static String generateUniqueId({
    required String type,
    String? timestamp,
    String? random,
  }) {
    // 生成时间戳 (格式: yyyyMMddHHmmss)
    final idTimestamp = timestamp ?? _getCurrentTimestamp();

    // 生成随机字符串 (UUID4的hex格式，无横线)
    final idRandom = random ?? _uuid.v4().replaceAll('-', '');

    // 组合为唯一ID
    return '${type}_$idTimestamp'
        '_$idRandom';
  }

  /// 获取当前时间戳
  /// 格式: yyyyMMddHHmmss
  static String _getCurrentTimestamp() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
  }
}
