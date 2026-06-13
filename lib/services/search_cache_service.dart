import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../forum_adapter/models/forum_thread.dart';

/// 搜索结果本地缓存服务
///
/// 将最后一次搜索结果持久化到 SharedPreferences，重启应用后可恢复。
/// 缓存 24 小时后自动失效，下次打开搜索页时不恢复。
class SearchCacheService {
  SearchCacheService._();

  static final SearchCacheService instance = SearchCacheService._();

  static const String _key = 'cached_search_results';
  static const Duration _maxAge = Duration(hours: 24);

  SharedPreferences? _prefs;
  bool _loaded = false;

  /// 初始化：从 SharedPreferences 加载 SharedPreferences 实例
  Future<void> init() async {
    if (_loaded) return;
    _prefs = await SharedPreferences.getInstance();
    _loaded = true;
  }

  /// 是否有有效缓存（未过期）
  bool get hasValidCache {
    final data = _read();
    return data != null;
  }

  /// 获取缓存的搜索结果（过期返回 null）
  SearchCacheData? load() {
    return _read();
  }

  /// 保存搜索结果
  Future<void> save(SearchCacheData data) async {
    if (!_loaded) await init();
    final json = <String, dynamic>{
      'keyword': data.keyword,
      'threads': data.threads.map(_threadToJson).toList(growable: false),
      'currentPage': data.currentPage,
      'totalPages': data.totalPages,
      'totalResults': data.totalResults,
      'hasNextPage': data.hasNextPage,
      'searchId': data.searchId,
      'cachedAt': DateTime.now().toUtc().toIso8601String(),
    };
    _prefs?.setString(_key, jsonEncode(json));
  }

  /// 清除缓存
  Future<void> clear() async {
    if (!_loaded) await init();
    _prefs?.remove(_key);
  }

  SearchCacheData? _read() {
    if (!_loaded) return null;
    final raw = _prefs?.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final cachedAtStr = map['cachedAt'] as String?;
      if (cachedAtStr == null) return null;
      final cachedAt = DateTime.parse(cachedAtStr);
      if (DateTime.now().toUtc().difference(cachedAt) > _maxAge) {
        // 过期，清理
        _prefs?.remove(_key);
        return null;
      }
      final threadsList = map['threads'] as List<dynamic>?;
      final threads = threadsList
              ?.whereType<Map<String, dynamic>>()
              .map(_threadFromJson)
              .toList(growable: false) ??
          [];
      return SearchCacheData(
        keyword: map['keyword'] as String? ?? '',
        threads: threads,
        currentPage: (map['currentPage'] as num?)?.toInt() ?? 1,
        totalPages: (map['totalPages'] as num?)?.toInt() ?? 1,
        totalResults: (map['totalResults'] as num?)?.toInt() ?? 0,
        hasNextPage: map['hasNextPage'] as bool? ?? false,
        searchId: (map['searchId'] as num?)?.toInt(),
        cachedAt: cachedAt,
      );
    } catch (e) {
      debugPrint('[SearchCacheService] 读取缓存失败: $e');
      return null;
    }
  }

  Map<String, dynamic> _threadToJson(ForumThread thread) {
    return {
      'threadId': thread.threadId,
      'forumId': thread.forumId,
      'title': thread.title,
      'author': thread.author,
      if (thread.authorId != null) 'authorId': thread.authorId,
      'replies': thread.replies,
      'views': thread.views,
      if (thread.createdAt != null)
        'createdAt': thread.createdAt!.toUtc().toIso8601String(),
      if (thread.lastReplyAt != null)
        'lastReplyAt': thread.lastReplyAt!.toUtc().toIso8601String(),
      if (thread.forumName != null) 'forumName': thread.forumName,
      if (thread.excerpt != null) 'excerpt': thread.excerpt,
    };
  }

  ForumThread _threadFromJson(Map<String, dynamic> json) {
    return ForumThread(
      threadId: (json['threadId'] as num).toInt(),
      forumId: (json['forumId'] as num).toInt(),
      title: json['title'] as String? ?? '',
      author: json['author'] as String? ?? '',
      authorId: (json['authorId'] as num?)?.toInt(),
      replies: (json['replies'] as num?)?.toInt() ?? 0,
      views: (json['views'] as num?)?.toInt() ?? 0,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
      lastReplyAt: json['lastReplyAt'] != null
          ? DateTime.parse(json['lastReplyAt'] as String)
          : null,
      forumName: json['forumName'] as String?,
      excerpt: json['excerpt'] as String?,
    );
  }
}

/// 缓存的搜索数据
class SearchCacheData {
  const SearchCacheData({
    required this.keyword,
    required this.threads,
    required this.currentPage,
    required this.totalPages,
    required this.totalResults,
    required this.hasNextPage,
    this.searchId,
    required this.cachedAt,
  });

  final String keyword;
  final List<ForumThread> threads;
  final int currentPage;
  final int totalPages;
  final int totalResults;
  final bool hasNextPage;
  final int? searchId;
  final DateTime cachedAt;
}
