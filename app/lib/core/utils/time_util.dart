import 'package:intl/intl.dart';
import 'package:ai_assistant/core/utils/app_logger.dart';

class TimeUtil {
  // 私有构造函数，防止实例化
  TimeUtil._();

  /// 获取当前系统时间
  /// 直接使用系统时间，不进行任何转换
  static DateTime getCurrentTime() {
    final now = DateTime.now();

    // 调试输出，帮助诊断时间问题
    logI('TimeUtil: 系统时间 ${now.toString()}');

    return now;
  }

  /// 格式化时间显示 (HH:mm)
  static String formatTime(DateTime dateTime) {
    return DateFormat('HH:mm').format(dateTime);
  }

  /// 格式化详细时间显示 (yyyy-MM-dd HH:mm:ss)
  static String formatDetailedTime(DateTime dateTime) {
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(dateTime);
  }

  /// 获取时间差描述
  static String getTimeDifference(DateTime messageTime, DateTime currentTime) {
    final duration = currentTime.difference(messageTime);

    if (duration.inSeconds < 60) {
      return '${duration.inSeconds}秒前';
    } else if (duration.inMinutes < 60) {
      return '${duration.inMinutes}分钟前';
    } else if (duration.inHours < 24) {
      return '${duration.inHours}小时前';
    } else {
      return '${duration.inDays}天前';
    }
  }
}
