import 'dart:io' show Platform;
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:native_dio_adapter/native_dio_adapter.dart';

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
import 'parsers/search_parser.dart';
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
  }) : _dio = dio ?? _createDio(),
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
       ),
       _searchParser = SearchParser(
         urlBuilder: urlBuilder,
         timeParser: timeParser,
       );

  /// 创建 Dio 实例，macOS 上使用原生 NSURLSession 适配器以兼容系统网络栈。
  static Dio _createDio() {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ));
    if (Platform.isMacOS) {
      dio.httpClientAdapter = NativeAdapter();
    }
    return dio;
  }

  final Dio _dio;
  final JavBusApiMapper _apiMapper;
  final ForumIndexParser _forumIndexParser;
  final ForumDisplayParser _forumDisplayParser;
  final ViewThreadParser _viewThreadParser;
  final SearchParser _searchParser;
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
    // 全新安装无 Cookie 时程序化设置年龄验证 Cookie
    // 这些 Cookie 是 JavBus 年龄验证网关的通行证，服务器接受程序化设置
    if (!_cookies.containsKey('existmag') || _cookies['existmag'] != 'all') {
      _cookies['existmag'] = 'all';
    }
    if (!_cookies.containsKey('age') || _cookies['age'] != 'verified') {
      _cookies['age'] = 'verified';
    }
    _syncToCookieJar();
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

  /// 启动阶段预热：校验 Cookie 有效性并建立会话。
  ///
  /// 应用重启时论坛列表从缓存加载（跳过 _warmUp），但 Cookie 可能已过期。
  /// 此方法在 [main] 启动阶段非阻塞调用，提前发现问题并重试，
  /// 避免用户点击分区后才被动报错。
  ///
  /// 返回 true 表示会话就绪，false 表示网络不可达或服务端异常。
  @override
  Future<bool> warmUpSession() async {
    // 先尝试从 CookieJar 恢复持久化 Cookie（含 session、cf_clearance 等）
    await _initCookies(_apiMapper.siteHome());
    // 确保年龄验证 Cookie 存在（可能被 _initCookies 加载，也可能全新）
    _cookies['existmag'] = 'all';
    _cookies['age'] = 'verified';
    _syncToCookieJar();

    try {
      // 轻量请求：访问主站首页验证 Cookie 是否仍有效
      final siteHomeUri = _apiMapper.siteHome();
      await _getHtml(
        siteHomeUri,
        userAgent: desktopUserAgent,
        browserNavigation: true,
      );
      _lastDesktopReferer = siteHomeUri.toString();
      return true;
    } on ForumException {
      // 年龄验证页或登录页 → Cookie 失效，清空后重试
      _cookies.clear();
      _cookies['existmag'] = 'all';
      _cookies['age'] = 'verified';
      _syncToCookieJar();
      try {
        await _getHtml(
          _apiMapper.siteHome(),
          userAgent: desktopUserAgent,
          browserNavigation: true,
        );
        return true;
      } catch (_) {
        return false;
      }
    } on DioException {
      return false; // 网络不可达
    }
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
    SortMode? sort,
  }) async {
    final uri = _apiMapper.desktopForumDisplay(
      fid: forumId,
      filterTypeId: filterTypeId,
      page: page,
      sort: sort,
    );
    final html = await _getHtml(
      uri,
      userAgent: desktopUserAgent,
      referer: _lastDesktopReferer,
      browserNavigation: true,
    );
    _lastDesktopReferer = uri.toString();
    final result = _forumDisplayParser.parse(
      html,
      forumId: forumId,
      requestUrl: uri.toString(),
    );
    // 浏览量和主题来自同一份桌面版 HTML，真正原子加载
    final viewCounts = ForumDisplayParser.parseThreadViews(html);
    return ThreadListResult(
      threads: result.threads,
      currentPage: result.currentPage,
      totalPages: result.totalPages,
      hasNextPage: result.hasNextPage,
      viewCounts: viewCounts,
    );
  }

  @override
  Future<SearchResult> search(String keyword,
      {int? searchId, int page = 1}) async {
    final Uri uri;
    if (searchId != null) {
      uri = _apiMapper.searchForumPage(
        searchId: searchId,
        keyword: keyword,
        page: page,
      );
    } else {
      uri = _apiMapper.searchForum(keyword: keyword);
    }
    final html = await _getHtml(
      uri,
      userAgent: desktopUserAgent,
      referer: _lastDesktopReferer,
      browserNavigation: true,
    );
    _lastDesktopReferer = uri.toString();

    // 检测 60 秒频率限制
    if (_isSearchRateLimited(html)) {
      throw ForumResponseException(
        '搜索频率限制：60 秒内只能进行一次搜索',
        requestUrl: uri.toString(),
        statusCode: 200,
        responseSnippet: _snippet(html),
      );
    }

    return _searchParser.parse(html, requestUrl: uri.toString());
  }

  /// 检测 Discuz 搜索频率限制页面
  static bool _isSearchRateLimited(String html) {
    return html.contains('60 秒內只能進行一次搜索') ||
        html.contains('60 秒内只能进行一次搜索');
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
      // 提取 formhash（Discuz CSRF token），commentmore 翻页必须带
      final formhash = _extractFormhash(html);
      // 检查哪些帖子有更多点评页
      final pagination = ViewThreadParser.parseCommentPagination(html);
      // 逐帖逐页抓取点评，动态检测是否还有下一页
      for (final entry in pagination.entries) {
        final pid = entry.key;
        var maxPage = entry.value;
        for (var cp = 2; cp <= maxPage; cp++) {
          await Future.delayed(
            Duration(milliseconds: 150 + Random().nextInt(250)),
          );
          try {
            final moreUri = _apiMapper.commentMore(
              tid: threadId,
              pid: pid,
              page: cp,
              formhash: formhash,
            );
            final moreHtml = await _getHtml(
              moreUri,
              userAgent: desktopUserAgent,
              referer: _lastDesktopReferer,
            );
            final moreComments = ViewThreadParser.parseComments(
              moreHtml,
              knownPid: pid,
            );
            for (final mc in moreComments.entries) {
              allComments.putIfAbsent(mc.key, () => []).addAll(mc.value);
            }
            // 检查 commentmore 返回是否还有更多页
            final morePagination =
                ViewThreadParser.parseCommentPagination(moreHtml);
            final nextMax = morePagination[pid];
            if (nextMax != null && nextMax > maxPage) {
              maxPage = nextMax;
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
      } on ForumResponseException catch (_) {
        // 登录页检测已自动设置 Cookie，重试一次
        if (attempt < 1) {
          await Future.delayed(const Duration(milliseconds: 300));
          continue;
        }
        rethrow;
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
    // 确保年龄验证 Cookie 始终存在。
    // 不依赖 _warmUp 调用时机 —— 任何请求在发送前都强制补齐 Cookie，
    // 避免 _warmUp 未执行或 Cookie 被清空后首次请求即被 302 到登录页。
    if (!_cookies.containsKey('existmag') || _cookies['existmag'] != 'all') {
      _cookies['existmag'] = 'all';
    }
    if (!_cookies.containsKey('age') || _cookies['age'] != 'verified') {
      _cookies['age'] = 'verified';
    }
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
      if (_isLoginPage(body)) {
        // 无 Cookie 时论坛页面 302 重定向到登录页，说明年龄验证 Cookie 缺失
        _cookies['existmag'] = 'all';
        _cookies['age'] = 'verified';
        _syncToCookieJar();
        throw ForumResponseException(
          'JavBus 重定向到登录页（年龄验证 Cookie 缺失），已自动设置 Cookie，请重试',
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

  /// 无 Cookie 访问论坛页面时被 302 重定向到登录页
  static bool _isLoginPage(String html) {
    return (html.contains('member.php?mod=logging') ||
            html.contains('member.php?mod=logging&amp;')) &&
        html.contains('action=login');
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

  /// 从 HTML 中提取 formhash（Discuz CSRF token）
  static String? _extractFormhash(String html) {
    final match = RegExp(
      r'<input[^>]*name="formhash"[^>]*value="([^"]*)"',
    ).firstMatch(html);
    return match?.group(1);
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
