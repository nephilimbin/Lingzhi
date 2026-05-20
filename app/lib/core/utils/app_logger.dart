import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:stack_trace/stack_trace.dart' as stack;

/// AppLogger: 统一日志工具
///
/// 特性：
/// - 自定义输出格式：[filename][method:line] message
/// - 同时输出到控制台与文件
/// - 根据构建模式自动设置日志级别（Release 下默认 warning 以上）
class AppLogger {
  AppLogger._internal();
  static final AppLogger instance = AppLogger._internal();

  late Logger _logger;
  IOSink? _fileSink;
  File? _logFile;

  Logger get raw => _logger;
  File? get logFile => _logFile;

  Future<void> init({Level? level, bool saveToFile = false}) async {
    // 选择日志级别
    final resolvedLevel = level ?? (kReleaseMode ? Level.warning : Level.debug);

    // 初始化文件输出（可选）
    if (saveToFile) {
      try {
        // 始终写入临时目录（调试用途，不在发布环境持久化）
        final dir = await getTemporaryDirectory();
        final logDir = Directory('${dir.path}/logs');
        if (!await logDir.exists()) {
          await logDir.create(recursive: true);
        }
        _logFile = File('${logDir.path}/app.log');
        _fileSink = _logFile!.openWrite(
          mode: FileMode.append,
          encoding: const SystemEncoding(),
        );
      } catch (_) {
        // 文件不可用时仅使用控制台
      }
    }

    final outputs = <LogOutput>[ConsoleOutput()];
    if (_fileSink != null) {
      outputs.add(_IOSinkOutput(_fileSink!));
    }

    _logger = Logger(
      level: resolvedLevel,
      printer: _CallerPrettyPrinter(),
      output: MultiOutput(outputs),
      filter: ProductionFilter(),
      // 禁用彩色输出和emoji，减少无用格式化字符
    );

    i(
      'AppLogger initialized. level=$resolvedLevel file=${_logFile?.path ?? 'N/A'}',
    );
  }

  // 简洁方法
  void v(message, [error, StackTrace? stackTrace]) =>
      _logger.t(message, error: error, stackTrace: stackTrace);
  void d(message, [error, StackTrace? stackTrace]) =>
      _logger.d(message, error: error, stackTrace: stackTrace);
  void i(message, [error, StackTrace? stackTrace]) =>
      _logger.i(message, error: error, stackTrace: stackTrace);
  void w(message, [error, StackTrace? stackTrace]) =>
      _logger.w(message, error: error, stackTrace: stackTrace);
  void e(message, [error, StackTrace? stackTrace]) =>
      _logger.e(message, error: error, stackTrace: stackTrace);
  void f(message, [error, StackTrace? stackTrace]) =>
      _logger.f(message, error: error, stackTrace: stackTrace);
  // 兼容旧调用，内部转发到 fatal
  void wtf(message, [error, StackTrace? stackTrace]) =>
      _logger.f(message, error: error, stackTrace: stackTrace);

  Future<void> dispose() async {
    await _fileSink?.flush();
    await _fileSink?.close();
    _fileSink = null;
  }
}

/// 自定义输出：在每条日志前附加 [filename][method:line]
class _CallerPrettyPrinter extends LogPrinter {
  // static final _dateFmt = DateFormat('yyyy-MM-dd HH:mm:ss.SSS');
  static final _dateFmt = DateFormat('HH:mm:ss.SSS');

  @override
  List<String> log(LogEvent event) {
    final now = _dateFmt.format(DateTime.now());
    final meta = _formatCaller(event.stackTrace ?? StackTrace.current);
    final level = _levelShort(event.level);

    final lines = <String>[];
    final msg = PrettyPrinter().stringifyMessage(event.message);
    for (final line in msg.split('\n')) {
      lines.add('[$now][$level] $meta $line');
    }

    if (event.error != null) {
      lines.add(
        '[$now][${_levelShort(event.level)}] $meta ERROR: ${event.error}',
      );
    }

    // 只在错误级别输出堆栈跟踪，减少无用信息
    if (event.stackTrace != null &&
        (event.level == Level.error || event.level == Level.fatal)) {
      final chain = stack.Chain.forTrace(event.stackTrace!);
      final terse = chain.terse.toString().split('\n');
      // 限制堆栈跟踪行数，避免过多输出
      final limitedLines = terse.take(5).toList();
      for (final l in limitedLines) {
        lines.add('[$now][$level] $meta $l');
      }
    }

    return lines;
  }

  String _levelShort(Level level) {
    switch (level) {
      case Level.trace:
        return 'T';
      case Level.debug:
        return 'D';
      case Level.info:
        return 'I';
      case Level.warning:
        return 'W';
      case Level.error:
        return 'E';
      case Level.fatal:
        return 'F';
      case Level.off:
        return 'O';
      default:
        return level.name.substring(0, 1).toUpperCase();
    }
  }

  /// 从堆栈获取最近一帧业务调用位置
  String _formatCaller(StackTrace stackTrace) {
    try {
      final chain = stack.Chain.forTrace(stackTrace).terse;
      final frames = chain.toTrace().frames;
      // 跳过 logger 自身和包内部调用帧
      final frame = frames.firstWhere(
        (f) =>
            !(f.library.contains('package:logger') ||
                f.library.contains('utils/app_logger.dart')),
        orElse:
            () =>
                frames.isNotEmpty
                    ? frames.first
                    : stack.Trace.current().frames.first,
      );

      // 只取文件名，去掉 .dart 后缀
      String fileName = frame.uri.pathSegments.last;
      if (fileName.endsWith('.dart')) {
        fileName = fileName.substring(0, fileName.length - 5);
      }

      // 获取方法名，去除可能的类名前缀
      String member = frame.member ?? '<fn>';
      if (member.startsWith('get:') || member.startsWith('set:')) {
        member = member.substring(4);
      }
      if (member.contains('.')) {
        member = member.substring(member.lastIndexOf('.') + 1);
      }
      final line = frame.line ?? 0;
      final lineStr = line.toString().padLeft(4, '0');
      return '[$fileName][$member:$lineStr]';
    } catch (_) {
      return '[unknown][unknown:0]';
    }
  }
}

/// 将日志写入到 IOSink（文件）
class _IOSinkOutput extends LogOutput {
  _IOSinkOutput(this._sink);
  final IOSink _sink;

  @override
  void output(OutputEvent event) {
    for (final line in event.lines) {
      _sink.writeln(line);
    }
  }
}

// 便捷的顶层方法
AppLogger get logger => AppLogger.instance;

void logD(message, [error, StackTrace? stackTrace]) =>
    logger.d(message, error, stackTrace);
void logI(message, [error, StackTrace? stackTrace]) =>
    logger.i(message, error, stackTrace);
void logW(message, [error, StackTrace? stackTrace]) =>
    logger.w(message, error, stackTrace);
void logE(message, [error, StackTrace? stackTrace]) =>
    logger.e(message, error, stackTrace);
