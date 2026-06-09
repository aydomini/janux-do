import '../../../l10n/s.dart';

/// 429 Rate Limit 异常（重试耗尽后抛出）
class RateLimitException implements Exception {
  final int? retryAfterSeconds;
  final String? message;

  RateLimitException([this.retryAfterSeconds, this.message]);

  @override
  String toString() => message ?? S.current.error_rateLimitedRetryLater;
}

/// 服务器错误异常（502/503/504 重试耗尽后抛出）
class ServerException implements Exception {
  final int statusCode;
  ServerException(this.statusCode);

  @override
  String toString() => '${S.current.error_serviceUnavailableRetry} ($statusCode)';
}

/// 帖子进入审核队列异常
class PostEnqueuedException implements Exception {
  final int pendingCount;
  PostEnqueuedException({this.pendingCount = 0});

  @override
  String toString() => S.current.network_postPendingReview;
}

/// Cloudflare 验证异常
class CfChallengeException implements Exception {
  final bool userCancelled;
  final bool inCooldown;
  /// 原始错误（用于调试，保留验证/重试失败的实际原因）
  final Object? cause;
  CfChallengeException({this.userCancelled = false, this.inCooldown = false, this.cause});

  @override
  String toString() {
    if (inCooldown) return S.current.cf_cooldown;
    if (userCancelled) return S.current.cf_userCancelled;
    if (cause != null) return S.current.cf_failedWithCause('$cause');
    return S.current.cf_failedRetry;
  }
}
