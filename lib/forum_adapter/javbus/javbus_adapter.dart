import 'dart:math';

import 'package:dio/dio.dart';

import '../../constants.dart';
import '../../forum_adapter/adapter.dart';
import '../../forum_adapter/exceptions.dart';
import '../../forum_adapter/models/forum_forum.dart';
import '../../forum_adapter/models/forum_post.dart';
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
  String? _lastDesktopReferer; // 跟踪上一次桌面版请求 URL，作为 Referer

  /// 构建随机化 iPhone Safari UA（iOS 17-18.x），每次启动不同
  static String _buildMobileUserAgent() {
    final iosMajor = 17 + Random().nextInt(2); // 17-18
    final iosMinor = Random().nextInt(6); // 0-5
    // 使用十六进制构建号，避免 Dart 科学计数法
    final build = (0x15E100 + Random().nextInt(0xC8))
        .toRadixString(16)
        .toUpperCase();
    final safariBuild = 600 + Random().nextInt(50);
    return 'Mozilla/5.0 (iPhone; CPU iPhone OS ${iosMajor}_$iosMinor like Mac OS X) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) '
        'Version/$iosMajor.$iosMinor Mobile/${build}A '
        'Safari/$safariBuild.1.15';
  }

  late final String mobileUserAgent = _buildMobileUserAgent();

  /// 构建随机化 Firefox UA（136-140 之间），每次启动不同
  static String _buildDesktopUserAgent() {
    final major = 136 + Random().nextInt(5); // 136-140
    final minor = Random().nextInt(10); // 0-9
    final rv = '$major.$minor';
    return 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14.6; rv:$rv) '
        'Gecko/20100101 Firefox/$rv';
  }

  late final String desktopUserAgent = _buildDesktopUserAgent();

  /// 从持久化 CookieJar 恢复会话 cookie，避免每次启动都重新预热
  Future<void> _initCookies(Uri uri) async {
    if (_cookies.isNotEmpty) return;
    try {
      final canonical = await CookieJarService()
          .loadCanonicalCookiesForRequest(uri);
      for (final c in canonical) {
        final value = c.value;
        if (value.isNotEmpty) _cookies[c.name] = value;
      }
    } catch (_) {}
  }

  /// 模拟真人预热：首页 → 延迟 → 论坛首页，获取 session/cookie
  Future<String> _warmUp({bool restoreCookies = true}) async {
    final siteHomeUri = _apiMapper.siteHome();
    if (restoreCookies) await _initCookies(siteHomeUri);
    await _getHtml(
      siteHomeUri,
      userAgent: desktopUserAgent,
      browserNavigation: true,
    );
    _lastDesktopReferer = siteHomeUri.toString();
    // 模拟真人浏览延迟：200-500ms
    await Future.delayed(
      Duration(milliseconds: 200 + Random().nextInt(300)),
    );
    final forumHomeUri = _apiMapper.forumHome();
    final html = await _getHtml(
      forumHomeUri,
      userAgent: desktopUserAgent,
      referer: _lastDesktopReferer,
      browserNavigation: true,
    );
    _lastDesktopReferer = forumHomeUri.toString();
    JavBusUrlBuilder.detectUcHostFromHtml(html);
    return html;
  }

  @override
  Future<List<ForumForum>> getForums() async {
    var restoreCookies = true;
    // 预热：如果返回年龄验证页面，说明 cookie 过期，重新预热
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final html = await _warmUp(restoreCookies: restoreCookies);
        return _forumIndexParser.parse(
          html,
          requestUrl: _lastDesktopReferer!,
        );
      } on ForumResponseException catch (e) {
        // 年龄验证页面：清空过期 cookie，下次不恢复，重新获取
        if (e.statusCode == 200 && attempt < 1) {
          _cookies.clear();
          _commentsCache.clear();
          restoreCookies = false;
          continue;
        }
        rethrow;
      }
    }
    throw StateError('预热失败');
  }

  @override
  Future<ThreadListResult> getThreads({
    required int forumId,
    int? filterTypeId,
    int page = 1,
  }) async {
    // 使用桌面版 URL，一次请求即可获取主题列表和完整浏览量
    // 桌面版 HTML 包含"回复 X / 查看 Y"格式，parse() 直接提取 views
    final uri = _apiMapper.desktopForumDisplay(
      fid: forumId,
      filterTypeId: filterTypeId,
      page: page,
    );
    final html = await _getHtml(
      uri,
      userAgent: desktopUserAgent,
      referer: _lastDesktopReferer,
      browserNavigation: true,
    );
    _lastDesktopReferer = uri.toString();
    return _forumDisplayParser.parse(
      html,
      forumId: forumId,
      requestUrl: uri.toString(),
    );
  }

  @override
  Future<PostListResult> getPosts({required int threadId, int page = 1}) async {
    final uri = _apiMapper.viewThread(tid: threadId, page: page);
    final html = await _getHtml(
      uri,
      userAgent: mobileUserAgent,
      referer: _lastDesktopReferer,
    );
    return _viewThreadParser.parse(
      html,
      threadId: threadId,
      requestUrl: uri.toString(),
    );
  }

  final Map<String, Map<int, List<ForumComment>>> _commentsCache = {};

  String _commentCacheKey(int threadId, int page) => '$threadId-$page';

  @override
  Future<Map<int, List<ForumComment>>> getComments(int threadId, {int page = 1}) async {
    final key = _commentCacheKey(threadId, page);
    if (_commentsCache.containsKey(key)) return _commentsCache[key]!;

    final uri = _apiMapper.desktopViewThread(tid: threadId, page: page);
    try {
      final html = await _getHtml(
        uri,
        userAgent: desktopUserAgent,
        referer: _lastDesktopReferer,
        browserNavigation: true,
      );
      _lastDesktopReferer = uri.toString();
      // 解析第 1 页点评
      final allComments = ViewThreadParser.parseComments(html);
      // 检查哪些帖子有更多点评页
      final pagination = ViewThreadParser.parseCommentPagination(html);
      // 逐帖逐页抓取点评，模拟真人翻页间隔
      for (final entry in pagination.entries) {
        final pid = entry.key;
        for (var cp = 2; cp <= entry.value; cp++) {
          await Future.delayed(
            Duration(milliseconds: 150 + Random().nextInt(250)),
          );
          try {
            final moreUri = _apiMapper.commentMore(
              tid: threadId,
              pid: pid,
              page: cp,
            );
            final moreHtml = await _getHtml(
              moreUri,
              userAgent: desktopUserAgent,
              referer: _lastDesktopReferer,
              browserNavigation: true,
            );
            final moreComments = ViewThreadParser.parseComments(
              moreHtml,
              knownPid: pid,
            );
            for (final mc in moreComments.entries) {
              allComments.putIfAbsent(mc.key, () => []).addAll(mc.value);
            }
          } on DioException {
            // 单页失败不影响其他页
          } on ForumException {
            // 单页失败不影响其他页
          }
        }
      }
      _commentsCache[key] = allComments;
      return allComments;
    } on DioException {
      return {};
    } on ForumException {
      return {};
    }
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
                'text/html,application/xhtml+xml,application/xml;q=0.9,'
                'image/avif,image/webp,*/*;q=0.8',
            'Accept-Encoding': 'gzip, deflate, br',
            'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.5',
            'Connection': 'keep-alive',
            'DNT': '1',
            if (browserNavigation) ...{
              'Sec-Fetch-Dest': 'document',
              'Sec-Fetch-Mode': 'navigate',
              // 同站跳转用 same-origin，直接打开用 none
              if (referer != null &&
                  _isSameOrigin(referer, uri.toString()))
                'Sec-Fetch-Site': 'same-origin'
              else
                'Sec-Fetch-Site': 'none',
              'Sec-Fetch-User': '?1',
              'Upgrade-Insecure-Requests': '1',
              'Cache-Control': 'max-age=0',
            },
            // ignore: use_null_aware_elements
            if (referer != null) 'Referer': referer,
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

  /// 判断两个 URL 是否同源（scheme + host 一致）
  static bool _isSameOrigin(String urlA, String urlB) {
    try {
      final a = Uri.parse(urlA);
      final b = Uri.parse(urlB);
      return a.scheme == b.scheme && a.host == b.host;
    } catch (_) {
      return false;
    }
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
