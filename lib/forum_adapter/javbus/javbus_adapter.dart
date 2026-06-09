import 'package:dio/dio.dart';

import '../../constants.dart';
import '../../forum_adapter/adapter.dart';
import '../../forum_adapter/exceptions.dart';
import '../../forum_adapter/models/forum_forum.dart';
import '../../forum_adapter/models/forum_results.dart';
import '../../services/network/cookie/cookie_jar_service.dart';
import 'api_mapper.dart';
import 'parsers/forumdisplay_parser.dart';
import 'parsers/forumindex_parser.dart';
import 'parsers/post_html_cleaner.dart';
import 'parsers/viewthread_parser.dart';
import 'utils/time_parser.dart';
import 'utils/url_builder.dart';

class JavbusAdapter extends ForumAdapter {
  JavbusAdapter({
    Dio? dio,
    JavBusApiMapper? apiMapper,
    JavBusUrlBuilder urlBuilder = const JavBusUrlBuilder(),
    DiscuzTimeParser? timeParser,
  }) : _dio = dio ??
           Dio(BaseOptions(
             connectTimeout: const Duration(seconds: 15),
             receiveTimeout: const Duration(seconds: 30),
           )),
       _apiMapper = apiMapper ?? JavBusApiMapper(urlBuilder: urlBuilder),
       _forumIndexParser = ForumIndexParser(urlBuilder: urlBuilder),
       _forumDisplayParser = ForumDisplayParser(
         urlBuilder: urlBuilder,
         timeParser: timeParser,
       ),
       _viewThreadParser = ViewThreadParser(
         urlBuilder: urlBuilder,
         timeParser: timeParser,
         htmlCleaner: PostHtmlCleaner(urlBuilder: urlBuilder),
       );

  final Dio _dio;
  final JavBusApiMapper _apiMapper;
  final ForumIndexParser _forumIndexParser;
  final ForumDisplayParser _forumDisplayParser;
  final ViewThreadParser _viewThreadParser;
  final Map<String, String> _cookies = {};

  static const String mobileUserAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 '
      'Mobile/15E148 Safari/604.1';

  static const String desktopUserAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 14.6; rv:127.0) '
      'Gecko/20100101 Firefox/127.0';

  @override
  Future<List<ForumForum>> getForums() async {
    final siteHomeUri = _apiMapper.siteHome();
    await _getHtml(
      siteHomeUri,
      userAgent: desktopUserAgent,
      browserNavigation: true,
    );
    final forumHomeUri = _apiMapper.forumHome();
    final html = await _getHtml(
      forumHomeUri,
      userAgent: desktopUserAgent,
      referer: siteHomeUri.toString(),
      browserNavigation: true,
    );
    JavBusUrlBuilder.detectUcHostFromHtml(html);
    return _forumIndexParser.parse(html, requestUrl: forumHomeUri.toString());
  }

  @override
  Future<ThreadListResult> getThreads({
    required int forumId,
    int? filterTypeId,
    int page = 1,
  }) async {
    final uri = _apiMapper.forumDisplay(
      fid: forumId,
      filterTypeId: filterTypeId,
      page: page,
    );
    final html = await _getHtml(uri, userAgent: mobileUserAgent);
    return _forumDisplayParser.parse(
      html,
      forumId: forumId,
      requestUrl: uri.toString(),
    );
  }

  @override
  Future<PostListResult> getPosts({required int threadId, int page = 1}) async {
    final uri = _apiMapper.viewThread(tid: threadId, page: page);
    final html = await _getHtml(uri, userAgent: mobileUserAgent);
    return _viewThreadParser.parse(
      html,
      threadId: threadId,
      requestUrl: uri.toString(),
    );
  }

  Future<String> _getHtml(
    Uri uri, {
    required String userAgent,
    String? referer,
    bool browserNavigation = false,
  }) async {
    DioException? lastTransientError;
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        return await _getHtmlOnce(
          uri,
          userAgent: userAgent,
          referer: referer,
          browserNavigation: browserNavigation,
        );
      } on DioException catch (error) {
        if (attempt < 3 && _isTransientNetworkError(error)) {
          lastTransientError = error;
          await Future.delayed(Duration(milliseconds: 400 * (attempt + 1)));
          continue;
        }
        _throwForumNetworkError(uri, error);
      }
    }
    _throwForumNetworkError(uri, lastTransientError!);
  }

  Future<String> _getHtmlOnce(
    Uri uri, {
    required String userAgent,
    String? referer,
    bool browserNavigation = false,
  }) async {
    try {
      final response = await _dio.getUri<String>(
        uri,
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'User-Agent': userAgent,
            'Accept':
                'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            if (browserNavigation) ...const {
              'Accept-Language': 'zh-CN',
              'Sec-Fetch-Dest': 'document',
              'Sec-Fetch-Mode': 'navigate',
              'Sec-Fetch-Site': 'none',
              'Sec-Fetch-User': '?1',
              'Upgrade-Insecure-Requests': '1',
            },
            'Referer': ?referer,
            if (_cookies.isNotEmpty) 'Cookie': _cookieHeader(),
          },
        ),
      );
      _storeCookies(response.headers);
      final statusCode = response.statusCode ?? 0;
      final body = response.data ?? '';
      if (statusCode < 200 || statusCode >= 300) {
        throw ForumResponseException(
          'JavBus 请求返回非 2xx 状态',
          requestUrl: uri.toString(),
          statusCode: statusCode,
          responseSnippet: _snippet(body),
        );
      }
      if (_isCloudflareChallenge(body)) {
        throw CloudflareChallengeException(
          'JavBus 返回 Cloudflare 验证页面',
          requestUrl: uri.toString(),
          statusCode: statusCode,
          responseSnippet: _snippet(body),
        );
      }
      if (_isAgeVerificationPage(body)) {
        throw ForumResponseException(
          'JavBus 返回年龄确认页面，请先在浏览器完成 JavBus 年龄确认后重试',
          requestUrl: uri.toString(),
          statusCode: statusCode,
          responseSnippet: _snippet(body),
        );
      }
      return body;
    } on ForumException {
      rethrow;
    }
  }

  static bool _isTransientNetworkError(DioException error) {
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.connectionError => true,
      _ => false,
    };
  }

  Never _throwForumNetworkError(Uri uri, DioException error) {
    final body = error.response?.data?.toString();
    final statusCode = error.response?.statusCode;
    if (statusCode != null) {
      throw ForumResponseException(
        'JavBus 请求失败: ${error.message}',
        requestUrl: uri.toString(),
        statusCode: statusCode,
        responseSnippet: body == null ? null : _snippet(body),
      );
    }
    throw ForumNetworkException(
      'JavBus 网络请求失败: ${error.message}',
      requestUrl: uri.toString(),
    );
  }

  static bool _isCloudflareChallenge(String html) {
    final lower = html.toLowerCase();
    return lower.contains('just a moment') ||
        lower.contains('challenge-running') ||
        lower.contains('cf-challenge');
  }

  static bool _isAgeVerificationPage(String html) {
    return html.contains('Age Verification JavBus') ||
        html.contains('你是否已經成年') ||
        html.contains('/doc/driver-verify');
  }

  static String _snippet(String text, {int maxLength = 300}) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxLength) return normalized;
    return normalized.substring(0, maxLength);
  }

  void _storeCookies(Headers headers) {
    final setCookies = headers['set-cookie'] ?? const <String>[];
    for (final setCookie in setCookies) {
      final pair = setCookie.split(';').first.trim();
      final separatorIndex = pair.indexOf('=');
      if (separatorIndex <= 0) continue;
      final name = pair.substring(0, separatorIndex).trim();
      final value = pair.substring(separatorIndex + 1).trim();
      if (value.isEmpty) {
        _cookies.remove(name);
      } else {
        _cookies[name] = value;
      }
    }
    _syncToCookieJar();
  }

  /// 将适配器内部 cookie 同步到全局 CookieJarService，
  /// 供图片请求等服务使用。
  void _syncToCookieJar() {
    try {
      final jar = CookieJarService();
      for (final entry in _cookies.entries) {
        jar.setCookie(
          entry.key,
          entry.value,
          url: AppConstants.baseUrl,
          path: '/',
        );
      }
    } catch (_) {}
  }

  String _cookieHeader() {
    return _cookies.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
  }
}
