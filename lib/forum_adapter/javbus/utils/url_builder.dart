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

    final relative = trimmed.startsWith('/')
        ? _stripBasePathPrefix(trimmed.substring(1))
        : trimmed;
    return baseUri.resolve(relative).toString();
  }

  String _stripBasePathPrefix(String path) {
    final basePath = baseUri.path;
    final normalizedBase = basePath.startsWith('/')
        ? basePath.substring(1)
        : basePath;
    if (path.startsWith(normalizedBase)) {
      return path.substring(normalizedBase.length);
    }
    return path;
  }

  /// 构造 Discuz UC 头像 URL
  ///
  /// 使用 uc_server/avatar.php 动态生成头像，与站点 HTML 中的格式一致。
  /// 格式: {baseUrl}uc_server/avatar.php?uid={uid}&size=middle
  String? buildAvatarUrl(int? authorId) {
    if (authorId == null) return null;
    return resolve('uc_server/avatar.php?uid=$authorId&size=middle');
  }

  static bool _looksLikeHostUrl(String value) {
    final firstSegment = value.split('/').first;
    return firstSegment.contains('.') &&
        !firstSegment.contains('..') &&
        RegExp(r'^[A-Za-z0-9.-]+(?::\d+)?$').hasMatch(firstSegment);
  }
}
