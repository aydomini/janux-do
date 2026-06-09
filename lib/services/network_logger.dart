import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// 网络日志工具
/// 写入到应用文档目录，方便在生产环境查看
class NetworkLogger {
  static NetworkLogger? _instance;
  static File? _logFile;
  static bool _initialized = false;
  static bool _enabled = false;

  factory NetworkLogger() {
    _instance ??= NetworkLogger._();
    return _instance!;
  }

  NetworkLogger._();

  static Future<void> _ensureInitialized({bool clearIfExists = false}) async {
    if (_initialized) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final logDir = Directory('${dir.path}/logs');
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }
      _logFile = File('${logDir.path}/network_debug.log');
      if (clearIfExists && await _logFile!.exists()) {
        await _logFile!.writeAsString('');
      }
      _initialized = true;
    } catch (e) {
      // 忽略初始化错误
    }
  }

  /// 初始化日志文件
  static Future<void> init() async {
    await _ensureInitialized(clearIfExists: true);
    _enabled = true;
    await log('=== Network Log Started ===');
  }

  /// 设置启用状态
  static Future<void> setEnabled(bool enabled) async {
    if (_enabled == enabled) {
      if (enabled && !_initialized) {
        await _ensureInitialized(clearIfExists: true);
        await log('=== Network Log Started ===');
      }
      return;
    }
    _enabled = enabled;
    if (_enabled) {
      await _ensureInitialized(clearIfExists: true);
      await log('=== Network Log Started ===');
    }
  }

  static bool get isEnabled => _enabled;

  /// 写入日志
  static Future<void> log(String message) async {
    if (!_enabled) return;
    if (!_initialized) {
      await _ensureInitialized();
    }
    if (_logFile == null) return;
    try {
      final timestamp = DateTime.now().toIso8601String();
      await _logFile!.writeAsString(
        '[$timestamp] $message\n',
        mode: FileMode.append,
      );
    } catch (e) {
      // 忽略写入错误
    }
  }

  /// 记录网络请求
  static Future<void> logRequest({
    required String method,
    required String url,
    required int durationMs,
    int? statusCode,
    String? error,
  }) async {
    final status = statusCode != null ? '$statusCode' : 'ERR';
    final errorMsg = error != null ? ' | $error' : '';
    await log('[NET] ${durationMs}ms $status $method $url$errorMsg');
  }

  /// 记录 DOH 解析
  static Future<void> logDoh({
    required String host,
    required int durationMs,
    String? resolvedIp,
    String? error,
  }) async {
    if (error != null) {
      await log('[DOH] ${durationMs}ms FAIL $host | $error');
    } else {
      await log('[DOH] ${durationMs}ms OK $host -> $resolvedIp');
    }
  }

  /// 获取日志文件路径
  static Future<String?> getLogPath() async {
    if (!_initialized) {
      await _ensureInitialized();
    }
    if (_logFile == null) return null;
    return _logFile!.path;
  }

  /// 读取日志内容
  static Future<String?> readLogs() async {
    if (!_initialized) {
      await _ensureInitialized();
    }
    if (_logFile == null || !await _logFile!.exists()) return null;
    return _logFile!.readAsString();
  }

  /// 清除日志
  static Future<void> clear() async {
    if (!_initialized) {
      await _ensureInitialized();
    }
    if (_logFile == null) return;
    try {
      if (await _logFile!.exists()) {
        await _logFile!.writeAsString('');
      }
      await log('=== Network Log Cleared ===');
    } catch (e) {
      // 忽略清除错误
    }
  }
}
