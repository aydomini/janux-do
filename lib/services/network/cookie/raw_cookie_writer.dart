import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 通过原生平台通道写入 raw Set-Cookie 头到 WebView cookie store
/// 保留完整的 cookie 语义（host-only / domain / sameSite 等）
class RawCookieWriter {
  RawCookieWriter._();
  static final instance = RawCookieWriter._();

  static const _channel = MethodChannel('com.fluxdo/raw_cookie');

  /// 是否支持当前平台
  /// Windows 走 CDP 不需要平台通道；Linux WPE 暂无原生通道实现
  bool get isSupported =>
      io.Platform.isAndroid ||
      io.Platform.isIOS ||
      io.Platform.isMacOS;

  /// 通过原始 Set-Cookie 头字符串写入 cookie
  ///
  /// [url] — cookie 所属的 URL（如 https://linux.do）
  /// [rawSetCookie] — 原始 Set-Cookie 头（如 "_t=xxx; path=/; secure; httponly"）
  ///
  /// 各平台实现：
  /// - Android: CookieManager.setCookie(url, rawSetCookie)
  /// - iOS/macOS: HTTPCookie.cookies(withResponseHeaderFields:for:) → WKHTTPCookieStore.setCookie
  /// - Linux: soup_cookie_jar_set_cookie(jar, uri, rawSetCookie)
  Future<bool> setRawCookie(String url, String rawSetCookie) async {
    try {
      final result = await _channel.invokeMethod<bool>('setRawCookie', {
        'url': url,
        'rawSetCookie': rawSetCookie,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('[RawCookieWriter] setRawCookie failed: $e');
      return false;
    } on MissingPluginException {
      debugPrint('[RawCookieWriter] Platform channel not available');
      return false;
    }
  }

  /// 批量写入多个 raw Set-Cookie 头
  Future<int> setRawCookies(String url, List<String> rawSetCookies) async {
    var written = 0;
    for (final raw in rawSetCookies) {
      if (await setRawCookie(url, raw)) written++;
    }
    return written;
  }
}
