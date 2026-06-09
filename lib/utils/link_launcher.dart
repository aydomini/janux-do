import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

const _browserChannel = MethodChannel('com.github.lingyan000.fluxdo/browser');

/// 打开外部链接
///
/// 根据用户偏好决定使用内置浏览器还是外部浏览器
Future<void> launchExternalLink(BuildContext context, String url) async {
  if (url.isEmpty) return;
  final uri = Uri.tryParse(url);
  if (uri == null) return;

  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// 强制在外部浏览器打开链接，绕过 App Links
///
/// 在 Android 上通过原生代码排除自己的应用，直接用外部浏览器打开，
/// 避免被应用的 intent-filter 拦截导致链接又回到应用本身。
Future<bool> launchInExternalBrowser(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;

  if (Platform.isAndroid) {
    try {
      final result = await _browserChannel.invokeMethod<bool>(
        'openInBrowser',
        {'url': url},
      );
      return result ?? false;
    } catch (e) {
      debugPrint('[LinkLauncher] Failed to launch browser: $e');
      // 回退到 url_launcher
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return true;
      }
      return false;
    }
  } else {
    // iOS 和其他平台使用 url_launcher
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return true;
    }
    return false;
  }
}
