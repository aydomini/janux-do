import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../forum_adapter/adapter.dart';
import '../forum_adapter/javbus/javbus_adapter.dart';
import '../forum_adapter/models/forum_forum.dart';
import '../services/forum_cache_service.dart';

final forumAdapterProvider = Provider<ForumAdapter>((ref) {
  return JavbusAdapter();
});

/// 版块列表 Provider（缓存优先）
///
/// 启动时立即返回缓存数据，后台静默刷新。
/// 网络不可用时侧边栏仍可正常显示，收藏功能完全不受影响。
final forumListProvider =
    NotifierProvider<ForumListNotifier, AsyncValue<List<ForumForum>>>(
  ForumListNotifier.new,
);

class ForumListNotifier extends Notifier<AsyncValue<List<ForumForum>>> {

  @override
  AsyncValue<List<ForumForum>> build() {
    final cache = ForumCacheService.instance;
    if (cache.hasCache) {
      // 有缓存：立即返回，后台静默刷新
      _refreshInBackground();
      return AsyncValue.data(cache.cached);
    }
    // 无缓存：必须等待首次网络请求
    _fetchAndUpdate();
    return const AsyncValue.loading();
  }

  /// 手动刷新（用户下拉刷新 / 网络恢复后调用）
  Future<void> refresh() => _fetchAndUpdate();

  /// 后台静默刷新：成功则更新缓存和 UI，失败保持现有数据不变
  Future<void> _refreshInBackground() async {
    try {
      final adapter = ref.read(forumAdapterProvider);
      final forums = await adapter.getForums();
      _applyUpdate(forums);
    } catch (e) {
      debugPrint('[ForumList] 后台刷新失败（缓存数据不变）: $e');
    }
  }

  /// 前台获取：无缓存时必须等待，失败则进入 error 状态
  Future<void> _fetchAndUpdate() async {
    try {
      final adapter = ref.read(forumAdapterProvider);
      final forums = await adapter.getForums();
      _applyUpdate(forums);
    } catch (e, stack) {
      // 如果有缓存数据则保持，不进入错误状态
      if (ForumCacheService.instance.hasCache) {
        debugPrint('[ForumList] 刷新失败，保持缓存数据: $e');
        return;
      }
      state = AsyncValue.error(e, stack);
    }
  }

  void _applyUpdate(List<ForumForum> forums) {
    ForumCacheService.instance.update(forums);
    state = AsyncValue.data(forums);
  }
}
