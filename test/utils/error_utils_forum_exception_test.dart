import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/forum_adapter/exceptions.dart';
import 'package:fluxdo/l10n/slang/strings.g.dart';
import 'package:fluxdo/utils/error_utils.dart';

void main() {
  setUpAll(() {
    LocaleSettings.setLocaleRaw('zh');
  });

  group('ErrorUtils maps JavBus forum exceptions', () {
    test('maps Cloudflare challenge to explicit security prompt', () {
      final info = ErrorUtils.getErrorInfo(
        const CloudflareChallengeException('JavBus 返回验证页'),
      );

      expect(info.title, 'JavBus 安全验证');
      expect(info.message, contains('Cloudflare'));
    });

    test('maps network errors to JavBus network prompt', () {
      final info = ErrorUtils.getErrorInfo(
        const ForumNetworkException('JavBus 网络请求失败'),
      );

      expect(info.title, 'JavBus 网络连接失败');
      expect(info.message, 'JavBus 网络请求失败');
    });

    test('maps response errors with status code context', () {
      final info = ErrorUtils.getErrorInfo(
        const ForumResponseException('JavBus 请求返回非 2xx 状态', statusCode: 503),
      );

      expect(info.title, 'JavBus 请求失败');
      expect(info.message, contains('JavBus 请求返回非 2xx 状态'));
      expect(info.message, contains('HTTP 503'));
    });

    test('maps parse errors to parser mismatch prompt', () {
      final info = ErrorUtils.getErrorInfo(
        const ForumParseException('未找到帖子楼层', parserName: 'ViewThreadParser'),
      );

      expect(info.title, 'JavBus 页面解析失败');
      expect(info.message, '未找到帖子楼层');
    });

    test('maps unsupported features to first-stage scope prompt', () {
      final info = ErrorUtils.getErrorInfo(
        const UnsupportedForumFeatureException('登录暂未实现'),
      );

      expect(info.title, '功能暂未支持');
      expect(info.message, '登录暂未实现');
    });
  });
}
