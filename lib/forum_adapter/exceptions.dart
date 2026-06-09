class ForumException implements Exception {
  const ForumException(
    this.message, {
    this.requestUrl,
    this.statusCode,
    this.responseSnippet,
  });

  final String message;
  final String? requestUrl;
  final int? statusCode;
  final String? responseSnippet;

  @override
  String toString() {
    final details = <String>[
      message,
      if (requestUrl != null) 'url=$requestUrl',
      if (statusCode != null) 'status=$statusCode',
      if (responseSnippet != null) 'snippet=$responseSnippet',
    ];
    return '${runtimeType.toString()}: ${details.join(', ')}';
  }
}

class ForumNetworkException extends ForumException {
  const ForumNetworkException(
    super.message, {
    super.requestUrl,
    super.statusCode,
    super.responseSnippet,
  });
}

class ForumResponseException extends ForumException {
  const ForumResponseException(
    super.message, {
    super.requestUrl,
    super.statusCode,
    super.responseSnippet,
  });
}

class ForumParseException extends ForumException {
  const ForumParseException(
    super.message, {
    required this.parserName,
    super.requestUrl,
    super.statusCode,
    super.responseSnippet,
  });

  final String parserName;

  @override
  String toString() => '${super.toString()}, parser=$parserName';
}

class CloudflareChallengeException extends ForumException {
  const CloudflareChallengeException(
    super.message, {
    super.requestUrl,
    super.statusCode,
    super.responseSnippet,
  });
}

class UnsupportedForumFeatureException extends ForumException {
  const UnsupportedForumFeatureException(
    super.message, {
    super.requestUrl,
  });
}
