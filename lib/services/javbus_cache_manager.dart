import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// JavBus 正文图片缓存管理器。
///
/// 正文图片和原图预览共用缓存池，避免预览同一张图片时重复下载。
class JavBusPostImageCacheManager extends CacheManager with ImageCacheManager {
  static const String key = 'javbusPostImageCache';
  static JavBusPostImageCacheManager? _instance;

  factory JavBusPostImageCacheManager() {
    _instance ??= JavBusPostImageCacheManager._();
    return _instance!;
  }

  JavBusPostImageCacheManager._()
    : super(
        Config(
          key,
          stalePeriod: const Duration(days: 7),
          maxNrOfCacheObjects: 500,
          repo: JsonCacheInfoRepository(databaseName: key),
        ),
      );
}

/// JavBus 用户头像缓存管理器。
///
/// 头像体积小、复用率高，独立缓存避免被帖子大图淘汰。
class JavBusAvatarCacheManager extends CacheManager with ImageCacheManager {
  static const String key = 'javbusAvatarCache';
  static JavBusAvatarCacheManager? _instance;

  factory JavBusAvatarCacheManager() {
    _instance ??= JavBusAvatarCacheManager._();
    return _instance!;
  }

  JavBusAvatarCacheManager._()
    : super(
        Config(
          key,
          stalePeriod: const Duration(days: 30),
          maxNrOfCacheObjects: 2000,
          repo: JsonCacheInfoRepository(databaseName: key),
        ),
      );
}

/// JavBus 论坛表情缓存管理器。
///
/// 表情图片体积小且高频复用，独立缓存可以保持正文大图缓存稳定。
class JavBusEmojiCacheManager extends CacheManager with ImageCacheManager {
  static const String key = 'javbusEmojiCache';
  static JavBusEmojiCacheManager? _instance;

  factory JavBusEmojiCacheManager() {
    _instance ??= JavBusEmojiCacheManager._();
    return _instance!;
  }

  JavBusEmojiCacheManager._()
    : super(
        Config(
          key,
          stalePeriod: const Duration(days: 30),
          maxNrOfCacheObjects: 3000,
          repo: JsonCacheInfoRepository(databaseName: key),
        ),
      );
}
