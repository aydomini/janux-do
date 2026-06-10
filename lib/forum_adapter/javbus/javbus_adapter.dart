import 'dart:io' show Platform;
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:native_dio_adapter/native_dio_adapter.dart';

import '../../forum_adapter/adapter.dart';
import '../../forum_adapter/exceptions.dart';
import '../../forum_adapter/models/forum_forum.dart';
import '../../forum_adapter/models/forum_post.dart';
import '../../forum_adapter/models/forum_results.dart';
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

  /// macOS 使用 NativeAdapter（NSURLSession），其他平台用 Dart HttpClient。
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
  String? _lastDesktopReferer;
  bool _isWarmingUp = false;

  /// 随机 Firefox UA（136-140），每次启动不同
  static String _buildDesktopUserAgent() {
    final major = 136 + Random().nextInt(5);
    final minor = Random().nextInt(10);
    final rv = '$major.$minor';
    return 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14.6; rv:$rv) '
        'Gecko/20100101 Firefox/$rv';
  }

  late final String desktopUserAgent = _buildDesktopUserAgent();

  /// 随机 iPhone Safari UA（iOS 17-18），每次启动不同
  static String _buildMobileUserAgent() {
    final iosMajor = 17 + Random().nextInt(2);
    final iosMinor = Random().nextInt(6);
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

  // ═══════════════════════════════════════════════════════════════════════
  // 预热：首页 → 延迟 → 论坛首页，建立浏览轨迹
  // ═══════════════════════════════════════════════════════════════════════

  Future<String> _warmUp() async {
    _isWarmingUp = true;
    try {
      final siteHomeUri = _apiMapper.siteHome();
      await _getHtml(
        siteHomeUri,
        userAgent: desktopUserAgent,
        browserNavigation: true,
      );
      _lastDesktopReferer = siteHomeUri.toString();

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
    } finally {
      _isWarmingUp = false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 公共接口
  // ═══════════════════════════════════════════════════════════════════════

  @override
  Future<List<ForumForum>> getForums() async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final html = await _warmUp();
        return _forumIndexParser.parse(
          html,
          requestUrl: _lastDesktopReferer!,
        );
      } on ForumResponseException catch (e) {
        if (e.statusCode == 200 && attempt < 1) {
          _lastDesktopReferer = null;
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
    await _ensureSessionWarm();
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
    await _ensureSessionWarm();
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

  static bool _isSearchRateLimited(String html) {
    return html.contains('60 秒內只能進行一次搜索') ||
        html.contains('60 秒内只能进行一次搜索');
  }

  @override
  Future<PostListResult> getPosts({required int threadId, int page = 1}) async {
    await _ensureSessionWarm();
    final uri = _apiMapper.desktopViewThread(tid: threadId, page: page);
    final html = await _getHtml(
      uri,
      userAgent: desktopUserAgent,
      referer: _lastDesktopReferer,
      browserNavigation: true,
    );
    _lastDesktopReferer = uri.toString();
    return _viewThreadParser.parse(
      html,
      threadId: threadId,
      requestUrl: uri.toString(),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 点评
  // ═══════════════════════════════════════════════════════════════════════

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
      final allComments = ViewThreadParser.parseComments(html);
      final formhash = _extractFormhash(html);
      final pagination = ViewThreadParser.parseCommentPagination(html);
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
            final morePagination =
                ViewThreadParser.parseCommentPagination(moreHtml);
            final nextMax = morePagination[pid];
            if (nextMax != null && nextMax > maxPage) {
              maxPage = nextMax;
            }
          } on DioException {
            // 单页失败不影响
          } on ForumException {
            // 单页失败不影响
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

  // ═══════════════════════════════════════════════════════════════════════
  // 会话预热（补位：_warmUp 未完成时抢先点击分区）
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _ensureSessionWarm() async {
    if (_lastDesktopReferer != null) return;
    if (_isWarmingUp) return;
    _isWarmingUp = true;
    try {
      final siteHomeUri = _apiMapper.siteHome();
      await _getHtml(
        siteHomeUri,
        userAgent: desktopUserAgent,
        browserNavigation: true,
      );
      _lastDesktopReferer = siteHomeUri.toString();
      await Future.delayed(
        Duration(milliseconds: 100 + Random().nextInt(200)),
      );
    } catch (_) {
      // 预热失败不阻塞主请求
    } finally {
      _isWarmingUp = false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // HTTP 请求
  // ═══════════════════════════════════════════════════════════════════════

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
        if (error.type == DioExceptionType.connectionTimeout) {
          if (attempt == 0) {
            await Future.delayed(const Duration(seconds: 2));
            continue;
          }
          _throwForumNetworkError(uri, error);
        }
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
            'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.5',
            'Connection': 'keep-alive',
            'DNT': '1',
            if (browserNavigation) ...{
              'Sec-Fetch-Dest': 'document',
              'Sec-Fetch-Mode': 'navigate',
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
          },
        ),
      );
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

  // ═══════════════════════════════════════════════════════════════════════
  // 错误分类
  // ═══════════════════════════════════════════════════════════════════════

  static bool _isTransientNetworkError(DioException error) {
    return switch (error.type) {
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

  static bool _isAgeVerificationPage(String html) {
    return html.contains('Age Verification JavBus') ||
        html.contains('/doc/driver-verify');
  }

  static bool _isCloudflareChallenge(String html) {
    final lower = html.toLowerCase();
    return lower.contains('just a moment') ||
        lower.contains('challenge-running') ||
        lower.contains('cf-challenge');
  }

  static bool _isSameOrigin(String urlA, String urlB) {
    try {
      final a = Uri.parse(urlA);
      final b = Uri.parse(urlB);
      return a.scheme == b.scheme && a.host == b.host;
    } catch (_) {
      return false;
    }
  }

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
}
