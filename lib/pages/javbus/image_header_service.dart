import '../../services/network/cookie/cookie_jar_service.dart';

/// 图片资源请求头服务
///
/// 缓存 session cookie 供所有图片请求复用，避免每个 widget 独立异步加载。
/// 调用 [refresh] 更新缓存（通常在页面数据加载后调用）。
class ImageHeaderService {
  ImageHeaderService._();
  static final ImageHeaderService instance = ImageHeaderService._();

  String? _cookieHeader;

  static const _userAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_6) AppleWebKit/605.1.15 '
      '(KHTML, like Gecko) Version/17.5 Safari/605.1.15';

  static const _referer = 'https://www.javbus.com/';

  /// 从 CookieJarService 刷新缓存的 cookie 头
  Future<void> refresh() async {
    try {
      final jar = CookieJarService();
      if (!jar.isInitialized) await jar.initialize();
      final parts = <String>[];
      final t = await jar.getTToken();
      if (t != null && t.isNotEmpty) parts.add('_t=$t');
      final cf = await jar.getCfClearance();
      if (cf != null && cf.isNotEmpty) parts.add('cf_clearance=$cf');
      _cookieHeader = parts.isEmpty ? null : parts.join('; ');
    } catch (_) {
      _cookieHeader = null;
    }
  }

  /// 同步获取请求头（不含 cookie 时仅带 UA + Referer）
  Map<String, String> get headers {
    return {
      'User-Agent': _userAgent,
      'Referer': _referer,
      'Cookie': ?_cookieHeader,
    };
  }
}
