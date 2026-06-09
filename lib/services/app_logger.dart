import 'package:catcher_2/catcher_2.dart';
import 'package:flutter/foundation.dart';

import 'log/log_writer.dart';

/// 统一日志入口
///
/// - `info()` / `warning()` 在 Debug 模式输出到控制台，同时写入文件
/// - `error()` 在 Debug 模式输出到控制台，同时桥接到 Catcher2 写入日志文件
class AppLogger {
  AppLogger._();

  static bool _enabled = true;

  /// 设置日志开关
  static void setEnabled(bool enabled) {
    _enabled = enabled;
  }

  /// 信息级别日志（控制台 + 文件）
  static void info(String message, {String? tag}) {
    if (!_enabled) return;

    if (kDebugMode) {
      debugPrint(_format('INFO', tag, message));
    }

    // 写入文件（fire-and-forget）
    LogWriter.instance.write({
      'timestamp': DateTime.now().toIso8601String(),
      'level': 'info',
      'type': 'general',
      'message': message,
      if (tag != null) 'tag': tag,
    });
  }

  /// 警告级别日志（控制台 + 文件）
  static void warning(String message, {String? tag}) {
    if (!_enabled) return;

    if (kDebugMode) {
      debugPrint(_format('WARN', tag, message));
    }

    // 写入文件（fire-and-forget）
    LogWriter.instance.write({
      'timestamp': DateTime.now().toIso8601String(),
      'level': 'warning',
      'type': 'general',
      'message': message,
      if (tag != null) 'tag': tag,
    });
  }

  /// 错误级别日志（控制台 + 写入文件）
  static void error(
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!_enabled) return;

    if (kDebugMode) {
      debugPrint(_format('ERROR', tag, message));
      if (error != null) debugPrint('  Error: $error');
      if (stackTrace != null) debugPrint('  StackTrace: $stackTrace');
    }

    // 桥接到 Catcher2，写入日志文件
    Catcher2.reportCheckedError(
      error ?? message,
      stackTrace ?? StackTrace.current,
      extraData: {
        if (tag != null) 'tag': tag,
        'message': message,
      },
    );
  }

  /// 格式化日志消息，兼容现有 `debugPrint('[模块名] 消息')` 约定
  static String _format(String level, String? tag, String message) {
    if (tag != null) {
      return '[$tag] $message';
    }
    return '[$level] $message';
  }
}
