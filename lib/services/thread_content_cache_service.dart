import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../forum_adapter/javbus/utils/url_builder.dart';
import '../forum_adapter/models/forum_poll.dart';
import '../forum_adapter/models/forum_post.dart';
import '../pages/javbus/image_header_service.dart';
import 'javbus_cache_manager.dart';

/// 帖子正文文件缓存服务
///
/// 每个收藏帖子的正文（首帖 + 回复 + 投票 + 楼中楼点评）以 JSON 格式
/// 持久化到应用文档目录，正文图片和头像直接下载到帖子目录下，取消收藏时
/// 一并以整个目录删除。表情图继续走 [JavBusEmojiCacheManager] 公共池。
///
/// 存储结构：
///   {appDocDir}/thread_cache/
///   ├── .image_index.json          ← 全局 URL→本地路径 索引
///   ├── {threadId}.json            ← 正文缓存
///   └── {threadId}/
///       └── images/                ← 该帖永久图片
class ThreadContentCacheService {
  ThreadContentCacheService._();

  static final ThreadContentCacheService instance = ThreadContentCacheService._();

  static const Duration maxAge = Duration(hours: 24);

  Directory? _cacheDir;

  /// URL → 相对于 _cacheDir 的本地路径（如 "123/images/abc.jpg"）
  final Map<String, String> _imagePaths = {};

  // ── 初始化 ──────────────────────────────────────────────

  /// 初始化缓存目录并加载图片索引
  Future<void> init() async {
    final appDir = await getApplicationDocumentsDirectory();
    _cacheDir = Directory('${appDir.path}/thread_cache');
    if (!_cacheDir!.existsSync()) {
      await _cacheDir!.create(recursive: true);
    }
    _loadImageIndex();
  }

  String _filePath(int threadId) => '${_cacheDir!.path}/$threadId.json';

  // ── 正文 JSON 缓存 ──────────────────────────────────────

  /// 保存帖子正文缓存
  Future<void> save({
    required int threadId,
    required List<ForumPost> posts,
    required Map<int, List<ForumComment>> comments,
    required int currentPage,
    required bool hasNextPage,
    ForumPoll? poll,
    int? threadAuthorId,
    int firstPagePostCount = 0,
  }) async {
    if (_cacheDir == null) await init();
    try {
      final json = <String, dynamic>{
        'threadId': threadId,
        'cachedAt': DateTime.now().toUtc().toIso8601String(),
        'posts': posts.map((p) => p.toJson()).toList(growable: false),
        'comments': comments.map((k, v) =>
            MapEntry(k.toString(), v.map((c) => c.toJson()).toList())),
        'currentPage': currentPage,
        'hasNextPage': hasNextPage,
        if (poll != null) 'poll': poll.toJson(),
        if (threadAuthorId != null) 'threadAuthorId': threadAuthorId,
        'firstPagePostCount': firstPagePostCount,
      };
      await File(_filePath(threadId)).writeAsString(
        jsonEncode(json),
        flush: true,
      );
    } catch (e) {
      debugPrint('[ThreadContentCacheService] 保存缓存失败 (tid=$threadId): $e');
    }
  }

  /// 读取缓存（过期仍返回数据，仅不更新 cachedAt）
  ThreadContentCacheData? load(int threadId) {
    if (_cacheDir == null) return null;
    try {
      final file = File(_filePath(threadId));
      if (!file.existsSync()) return null;
      final raw = file.readAsStringSync();
      final map = jsonDecode(raw) as Map<String, dynamic>;

      final postsList = (map['posts'] as List<dynamic>?)
              ?.map((e) => ForumPost.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];

      final commentsRaw = map['comments'] as Map<String, dynamic>?;
      final comments = <int, List<ForumComment>>{};
      if (commentsRaw != null) {
        for (final entry in commentsRaw.entries) {
          final postId = int.tryParse(entry.key);
          if (postId == null) continue;
          comments[postId] = (entry.value as List<dynamic>)
              .map((e) => ForumComment.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      }

      final pollJson = map['poll'] as Map<String, dynamic>?;
      final poll = pollJson != null ? ForumPoll.fromJson(pollJson) : null;

      final cachedAt = DateTime.parse(map['cachedAt'] as String);

      return ThreadContentCacheData(
        threadId: threadId,
        posts: postsList,
        comments: comments,
        poll: poll,
        currentPage: (map['currentPage'] as num?)?.toInt() ?? 1,
        hasNextPage: map['hasNextPage'] as bool? ?? false,
        threadAuthorId: (map['threadAuthorId'] as num?)?.toInt(),
        firstPagePostCount:
            (map['firstPagePostCount'] as num?)?.toInt() ?? 0,
        cachedAt: cachedAt,
      );
    } catch (e) {
      debugPrint('[ThreadContentCacheService] 读取缓存失败 (tid=$threadId): $e');
      return null;
    }
  }

  /// 删除指定帖子的全部缓存（正文 JSON + 图片目录 + 索引条目）
  Future<void> remove(int threadId) async {
    if (_cacheDir == null) await init();
    // 删除 JSON
    try {
      final file = File(_filePath(threadId));
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('[ThreadContentCacheService] 删除 JSON 失败 (tid=$threadId): $e');
    }
    // 删除图片目录
    try {
      final imageDir = Directory(_imageDirPath(threadId));
      if (await imageDir.exists()) {
        await imageDir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('[ThreadContentCacheService] 删除图片目录失败 (tid=$threadId): $e');
    }
    // 清理索引中属于该帖的条目
    _imagePaths.removeWhere((_, path) => path.startsWith('$threadId/'));
    _saveImageIndex().ignore();
  }

  /// 检查缓存是否已过期（超过 24 小时）
  bool isStale(int threadId) {
    final data = load(threadId);
    if (data == null) return false;
    return DateTime.now().toUtc().difference(data.cachedAt) > maxAge;
  }

  /// 获取所有已缓存的帖子 ID 列表
  List<int> get allCachedThreadIds {
    if (_cacheDir == null || !_cacheDir!.existsSync()) return [];
    try {
      return _cacheDir!
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json') && !f.path.endsWith('.image_index.json'))
          .map((f) => int.tryParse(
              f.uri.pathSegments.last.replaceAll('.json', '')))
          .whereType<int>()
          .toList(growable: false);
    } catch (_) {
      return [];
    }
  }

  /// 清除所有过期缓存
  Future<void> cleanExpired() async {
    final ids = allCachedThreadIds;
    for (final id in ids) {
      if (isStale(id)) {
        await remove(id);
      }
    }
  }

  // ── 图片永久缓存 ────────────────────────────────────────

  String _imageDirPath(int threadId) => '${_cacheDir!.path}/$threadId/images';
  String _imageIndexPath() => '${_cacheDir!.path}/.image_index.json';

  /// 从索引文件加载 URL→本地路径 映射
  void _loadImageIndex() {
    try {
      final file = File(_imageIndexPath());
      if (!file.existsSync()) return;
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      _imagePaths.clear();
      for (final entry in json.entries) {
        _imagePaths[entry.key] = entry.value as String;
      }
    } catch (_) {}
  }

  /// 将 URL→本地路径 映射持久化到索引文件
  Future<void> _saveImageIndex() async {
    try {
      await File(_imageIndexPath()).writeAsString(
        jsonEncode(_imagePaths),
        flush: true,
      );
    } catch (_) {}
  }

  /// 查询某 URL 对应的本地文件（用于渲染时查缓存）
  ///
  /// 返回 [File] 当且仅当：URL 在索引中 AND 对应文件存在。
  /// 若索引有记录但文件缺失（被外部删除），同步清理索引。
  File? getImageFile(String url) {
    final relativePath = _imagePaths[url];
    if (relativePath == null) return null;
    final file = File('${_cacheDir!.path}/$relativePath');
    if (file.existsSync()) return file;
    // 文件已丢失，清理索引
    _imagePaths.remove(url);
    _saveImageIndex().ignore();
    return null;
  }

  /// 下载并永久缓存帖子内的正文图片和头像
  ///
  /// 从 [posts] 和 [comments] 中提取所有图片 URL，
  /// 下载到 `thread_cache/{threadId}/images/` 目录，
  /// 同时更新全局 `.image_index.json` 索引。
  ///
  /// 调用方应在 [save] 之后 fire-and-forget，不阻塞 UI。
  Future<void> cacheImages({
    required int threadId,
    required List<ForumPost> posts,
    required Map<int, List<ForumComment>> comments,
  }) async {
    if (_cacheDir == null) await init();

    final imageUrls = <String>{};   // 正文图片
    final avatarUrls = <String>{};  // 头像
    final emojiUrls = <String>{};   // 表情（走公共池）

    final urlBuilder = const JavBusUrlBuilder();
    final imgRegex = RegExp(
      '''<img[^>]+src=["']([^"']+)["']''',
      caseSensitive: false,
    );

    for (final post in posts) {
      // 正文 HTML 中的图片
      for (final match in imgRegex.allMatches(post.contentHtml)) {
        final src = match.group(1);
        if (src == null || src.isEmpty) continue;
        final resolved = urlBuilder.resolve(src);
        if (_isEmojiUrl(resolved)) {
          emojiUrls.add(resolved);
        } else {
          imageUrls.add(resolved);
        }
      }
      // 头像
      if (post.avatarUrl != null && post.avatarUrl!.isNotEmpty) {
        avatarUrls.add(post.avatarUrl!);
      }
      // 点评头像
      for (final comment in comments[post.postId] ?? <ForumComment>[]) {
        if (comment.avatarUrl != null && comment.avatarUrl!.isNotEmpty) {
          avatarUrls.add(comment.avatarUrl!);
        }
      }
    }

    final imageDir = Directory(_imageDirPath(threadId));
    if (!imageDir.existsSync()) {
      await imageDir.create(recursive: true);
    }

    // 正文图片 + 头像 → darts 本地目录
    final allUrls = {...imageUrls, ...avatarUrls};
    for (final url in allUrls) {
      if (_imagePaths.containsKey(url)) continue; // 已缓存
      final filename = _filenameFromUrl(url);
      final filePath = '${imageDir.path}/$filename';
      final downloaded = await _download(url, filePath);
      if (downloaded) {
        final relativePath = '$threadId/images/$filename';
        _imagePaths[url] = relativePath;
      }
    }

    // 表情 → 走公共缓存池（LRU 管理，不占用帖子目录）
    final headers = ImageHeaderService.instance.headers;
    for (final url in emojiUrls) {
      JavBusEmojiCacheManager()
          .getSingleFile(url, headers: headers)
          .then((_) => null)
          .catchError((_) => null);
    }

    await _saveImageIndex();
  }

  /// HTTP 下载图片到本地路径，成功返回 true
  Future<bool> _download(String url, String savePath) async {
    try {
      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse(url));
        final headers = ImageHeaderService.instance.headers;
        for (final entry in headers.entries) {
          request.headers.set(entry.key, entry.value);
        }
        final response = await request.close();
        if (response.statusCode != 200) return false;

        final bytes = await response
            .fold<List<int>>([], (prev, chunk) => prev..addAll(chunk));
        await File(savePath).writeAsBytes(bytes, flush: true);
        return true;
      } finally {
        client.close();
      }
    } catch (_) {
      return false;
    }
  }

  /// URL → 去重文件名（base64url 后缀 + 扩展名）
  ///
  /// 从 base64 编码末尾取 48 字符——URL 后段是文件名/路径，前段是域名/协议，
  /// 同 CDN 的多张图前段高度一致，只取前 24 字符会导致碰撞。
  /// 48 字符 ≈ 36 字节原始数据，足够覆盖路径+文件名，且远低于文件系统 255 限制。
  String _filenameFromUrl(String url) {
    final encoded = base64Url.encode(utf8.encode(url));
    final start = encoded.length > 48 ? encoded.length - 48 : 0;
    final name = encoded.substring(start);
    final ext = _extensionFromUrl(url);
    return '$name.$ext';
  }

  String _extensionFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return 'jpg';
    final last = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
    final dot = last.lastIndexOf('.');
    if (dot == -1) return 'jpg';
    return last.substring(dot + 1).split('?').first;
  }

  /// 通过 URL 路径判断是否为论坛表情图
  static bool _isEmojiUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('/face/') ||
        lower.contains('/faces/') ||
        lower.contains('/emoticon') ||
        lower.contains('smiley');
  }
}

/// 缓存的帖子正文数据
class ThreadContentCacheData {
  const ThreadContentCacheData({
    required this.threadId,
    required this.posts,
    required this.comments,
    this.poll,
    required this.currentPage,
    required this.hasNextPage,
    this.threadAuthorId,
    this.firstPagePostCount = 0,
    required this.cachedAt,
  });

  final int threadId;
  final List<ForumPost> posts;
  final Map<int, List<ForumComment>> comments;
  final ForumPoll? poll;
  final int currentPage;
  final bool hasNextPage;
  final int? threadAuthorId;

  /// 首次加载时第一页的帖子数，用于后台刷新时按页替换和保护。
  final int firstPagePostCount;
  final DateTime cachedAt;
}
