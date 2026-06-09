import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../javbus_cache_manager.dart';

/// 缓存大小计算服务
class CacheSizeService {
  /// flutter_cache_manager 的缓存 key 列表
  static const _cacheKeys = [
    JavBusPostImageCacheManager.key,
    JavBusAvatarCacheManager.key,
    JavBusEmojiCacheManager.key,
  ];

  static const cacheKeysForTesting = _cacheKeys;

  /// 计算图片缓存大小
  static Future<int> getImageCacheSize() async {
    final tempDir = await getTemporaryDirectory();
    int totalSize = 0;
    for (final key in _cacheKeys) {
      totalSize += await _getDirectorySize(Directory('${tempDir.path}/$key'));
    }
    return totalSize;
  }

  /// 计算 AI 聊天数据大小
  static Future<int> getAiChatDataSize(SharedPreferences prefs) async {
    int totalSize = 0;
    for (final key in prefs.getKeys()) {
      if (key.startsWith('ai_chat_')) {
        final value = prefs.get(key);
        if (value is String) {
          totalSize += value.length * 2;
        } else if (value is List<String>) {
          for (final item in value) {
            totalSize += item.length * 2;
          }
        }
      }
    }
    return totalSize;
  }

  /// 计算 Cookie 缓存大小
  static Future<int> getCookieCacheSize() async {
    final docDir = await getApplicationSupportDirectory();
    return _getDirectorySize(Directory('${docDir.path}/.cookies'));
  }

  static Future<int> _getDirectorySize(Directory dir) async {
    if (!await dir.exists()) return 0;
    int totalSize = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        totalSize += await entity.length();
      }
    }
    return totalSize;
  }

  /// 删除图片缓存目录
  static Future<void> deleteImageCacheDirs() async {
    final tempDir = await getTemporaryDirectory();
    for (final key in _cacheKeys) {
      final dir = Directory('${tempDir.path}/$key');
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    }
  }

  /// 格式化字节为可读字符串
  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
