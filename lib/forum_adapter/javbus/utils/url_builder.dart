class JavBusUrlBuilder {
  const JavBusUrlBuilder({this.baseUrl = defaultBaseUrl});

  static const String defaultBaseUrl = 'https://www.javbus.com/forum/';

  final String baseUrl;

  Uri get baseUri {
    final parsed = Uri.parse(baseUrl);
    final normalizedPath = parsed.path.endsWith('/')
        ? parsed.path
        : '${parsed.path}/';
    return parsed.replace(path: normalizedPath);
  }

  String resolve(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) {
      return baseUri.toString();
    }
    if (trimmed.startsWith('//')) {
      return Uri.parse('${baseUri.scheme}:$trimmed').toString();
    }
    final absolute = Uri.tryParse(trimmed);
    if (absolute != null && absolute.hasScheme) {
      return absolute.toString();
    }
    if (_looksLikeHostUrl(trimmed)) {
      return Uri.parse('https://$trimmed').toString();
    }

    // Dart Uri.resolve 对以 / 开头的绝对路径会正确替换整个 path，
    // 对相对路径会自然追加到 base path 后面，无需手动剥离前缀
    return baseUri.resolve(trimmed).toString();
  }

  /// UC 头像域名（从桌面版页面 HTML 中自动检测）
  static String? _detectedUcHost;

  /// 从 HTML 中检测 UC 头像域名
  ///
  /// 桌面版页面中包含形如 `https://uc.xxx.com/uc/data/avatar/...` 的 img 标签，
  /// 调用此方法提取 UC 域名供 [buildAvatarUrl] 使用。
  static void detectUcHostFromHtml(String html) {
    final match = RegExp(
      r'https?://(uc\.[^/"]+)/uc/data/avatar/',
    ).firstMatch(html);
    if (match != null) {
      _detectedUcHost = match.group(1);
    }
  }

  /// 构造 Discuz UC 头像 URL
  ///
  /// 优先使用从 HTML 中检测到的 UC 数据目录格式:
  ///   https://uc.{host}/uc/data/avatar/000/50/64/57_avatar_middle.jpg
  /// 未检测到 UC 域名时回退到 PHP 脚本格式:
  ///   {baseUrl}uc_server/avatar.php?uid={uid}&size=middle
  String? buildAvatarUrl(int? authorId) {
    if (authorId == null) return null;
    final ucHost = _detectedUcHost;
    if (ucHost != null) {
      final padded = authorId.toString().padLeft(9, '0');
      final dir = '${padded.substring(0, 3)}'
          '/${padded.substring(3, 5)}'
          '/${padded.substring(5, 7)}';
      final file = '${padded.substring(7, 9)}_avatar_middle.jpg';
      return 'https://$ucHost/uc/data/avatar/$dir/$file';
    }
    return resolve('uc_server/avatar.php?uid=$authorId&size=middle');
  }

  static bool _looksLikeHostUrl(String value) {
    final firstSegment = value.split('/').first;
    return firstSegment.contains('.') &&
        !firstSegment.contains('..') &&
        RegExp(r'^[A-Za-z0-9.-]+(?::\d+)?$').hasMatch(firstSegment);
  }
}
