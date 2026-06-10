import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../forum_adapter/models/forum_forum.dart';

/// 版块列表本地缓存服务
///
/// 启动时立即从 SharedPreferences 加载缓存数据，
/// 后台静默刷新，网络不可用时仍可展示侧边栏和收藏。
class ForumCacheService {
  ForumCacheService._();

  static final ForumCacheService instance = ForumCacheService._();

  static const String _key = 'cached_forum_list';

  SharedPreferences? _prefs;
  List<ForumForum> _cached = [];
  bool _loaded = false;
  DateTime? _lastFetchAt;

  /// 初始化：从 SharedPreferences 加载缓存
  Future<void> init() async {
    if (_loaded) return;
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        _cached = list
            .whereType<Map<String, dynamic>>()
            .map(_fromJson)
            .toList(growable: false);
      } catch (e) {
        debugPrint('[ForumCacheService] 加载缓存失败: $e');
      }
    }
    _loaded = true;
  }

  /// 清空缓存状态（仅用于测试清理）
  void clearForTest() {
    _cached = [];
    _loaded = false;
    _prefs = null;
  }

  /// 是否有缓存数据
  bool get hasCache => _cached.isNotEmpty;

  /// 获取当前缓存（同步，不等待网络）
  List<ForumForum> get cached => List.unmodifiable(_cached);

  /// 上次成功获取时间
  DateTime? get lastFetchAt => _lastFetchAt;

  /// 用网络数据更新缓存
  void update(List<ForumForum> forums) {
    _cached = List.of(forums);
    _lastFetchAt = DateTime.now();
    final list = _cached.map(_toJson).toList(growable: false);
    _prefs?.setString(_key, jsonEncode(list));
  }

  Map<String, dynamic> _toJson(ForumForum forum) {
    return {
      'forumId': forum.forumId,
      'name': forum.name,
      if (forum.description != null) 'description': forum.description,
      if (forum.parentForumId != null) 'parentForumId': forum.parentForumId,
      if (forum.filterTypeId != null) 'filterTypeId': forum.filterTypeId,
      'threadCount': forum.threadCount,
      'todayPostCount': forum.todayPostCount,
      if (forum.url != null) 'url': forum.url,
    };
  }

  ForumForum _fromJson(Map<String, dynamic> json) {
    return ForumForum(
      forumId: (json['forumId'] as num).toInt(),
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      parentForumId: (json['parentForumId'] as num?)?.toInt(),
      filterTypeId: (json['filterTypeId'] as num?)?.toInt(),
      threadCount: (json['threadCount'] as num?)?.toInt() ?? 0,
      todayPostCount: (json['todayPostCount'] as num?)?.toInt() ?? 0,
      url: json['url'] as String?,
    );
  }
}
