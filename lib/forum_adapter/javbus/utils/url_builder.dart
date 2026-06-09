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
  /// 格式: {scheme}://uc.{host}/uc/data/avatar/{uid_9digits}/{uid}_avatar_middle.jpg
  /// 示例: uid=133191 → 000/13/31/91_avatar_middle.jpg
  String? buildAvatarUrl(int? authorId) {
    if (authorId == null) return null;
    final padded = authorId.toString().padLeft(9, '0');
    final dir = '${padded.substring(0, 3)}'
        '/${padded.substring(3, 6)}'
        '/${padded.substring(6, 9)}';
    final host = baseUri.host.replaceFirst('www.', '');
    return '${baseUri.scheme}://uc.$host'
        '/uc/data/avatar/$dir/${authorId}_avatar_middle.jpg';
  }

  static bool _looksLikeHostUrl(String value) {
    final firstSegment = value.split('/').first;
    return firstSegment.contains('.') &&
        !firstSegment.contains('..') &&
        RegExp(r'^[A-Za-z0-9.-]+(?::\d+)?$').hasMatch(firstSegment);
  }
}
