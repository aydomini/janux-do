import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../forum_adapter/models/forum_thread.dart';

/// 收藏帖子服务
///
/// 使用 SharedPreferences 持久化收藏列表，存储完整帖子元数据以支持离线显示。
/// 数据按 favoritedAt 倒序排列（最近收藏的在前）。
class FavoritesService {
  FavoritesService._();

  static final FavoritesService instance = FavoritesService._();

  static const String _key = 'favorite_threads';

  SharedPreferences? _prefs;
  final List<ForumThread> _cached = [];
  bool _loaded = false;

  /// 初始化：从 SharedPreferences 加载缓存
  Future<void> init() async {
    if (_loaded) return;
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            _cached.add(_fromJson(item));
          }
        }
      } catch (e) {
        debugPrint('[FavoritesService] 加载收藏数据失败: $e');
      }
    }
    _loaded = true;
  }

  /// 获取所有收藏（按收藏时间倒序）
  List<ForumThread> get all => List.unmodifiable(_cached);

  /// 收藏数量
  int get count => _cached.length;

  /// 是否已收藏
  bool isFavorited(int threadId) {
    return _cached.any((t) => t.threadId == threadId);
  }

  /// 添加收藏，已存在则移动到最前（更新时间戳）
  void add(ForumThread thread) {
    _cached.removeWhere((t) => t.threadId == thread.threadId);
    _cached.insert(0, thread);
    _save();
  }

  /// 取消收藏
  void remove(int threadId) {
    _cached.removeWhere((t) => t.threadId == threadId);
    _save();
  }

  /// 切换收藏状态，返回操作后的状态（true=已收藏）
  bool toggle(ForumThread thread) {
    if (isFavorited(thread.threadId)) {
      remove(thread.threadId);
      return false;
    } else {
      add(thread);
      return true;
    }
  }

  void _save() {
    final list = _cached.map(_toJson).toList(growable: false);
    _prefs?.setString(_key, jsonEncode(list));
  }

  Map<String, dynamic> _toJson(ForumThread thread) {
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
    };
  }

  ForumThread _fromJson(Map<String, dynamic> json) {
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
    );
  }
}
