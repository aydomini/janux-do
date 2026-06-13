import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../forum_adapter/models/forum_thread.dart';
import '../providers/forum_provider.dart';
import '../services/favorites_service.dart';
import '../services/thread_content_cache_service.dart';

/// 收藏帖子列表 Provider
///
/// 全局共享收藏状态。详情页按钮和收藏列表页通过此 Provider 同步。
final favoritesProvider = NotifierProvider<FavoritesNotifier, List<ForumThread>>(
  FavoritesNotifier.new,
);

/// 单帖收藏状态 Provider（用于详情页按钮）
final isFavoritedProvider = Provider.family<bool, int>((ref, threadId) {
  final favorites = ref.watch(favoritesProvider);
  return favorites.any((t) => t.threadId == threadId);
});

class FavoritesNotifier extends Notifier<List<ForumThread>> {
  bool _refreshing = false;

  @override
  List<ForumThread> build() {
    final service = FavoritesService.instance;
    _initAsync();
    return service.all;
  }

  Future<void> _initAsync() async {
    await FavoritesService.instance.init();
    state = FavoritesService.instance.all;
    // 后台刷新超过 24 小时的收藏帖元数据
    _refreshStaleIfNeeded();
  }

  /// 切换收藏状态，返回操作后的状态（true=已收藏）
  bool toggle(ForumThread thread) {
    final result = FavoritesService.instance.toggle(thread);
    state = FavoritesService.instance.all;
    if (result) {
      // 收藏成功，后台下载帖子首頁内容并写入文件缓存
      _downloadThreadContent(thread);
    }
    return result;
  }

  /// 取消收藏
  void remove(int threadId) {
    FavoritesService.instance.remove(threadId);
    state = FavoritesService.instance.all;
  }

  /// 是否已收藏
  bool isFavorited(int threadId) {
    return FavoritesService.instance.isFavorited(threadId);
  }

  /// 后台静默刷新过期收藏帖的元数据（浏览数、回复数、最后回复时间）
  ///
  /// 通过版块列表页获取完整线程元数据（含 views），按 forumId 分组后
  /// 对每个版块调一次 [ForumAdapter.getThreads]，从首页匹配 threadId 更新。
  /// 不在首页的过期帖暂不刷新（后续滚动翻页时可增量更新）。
  Future<void> _refreshStaleIfNeeded() async {
    if (_refreshing) return;
    final staleIds = FavoritesService.instance.staleThreadIds;
    if (staleIds.isEmpty) return;

    _refreshing = true;
    try {
      final currentFavorites = FavoritesService.instance.all;
      final adapter = ref.read(forumAdapterProvider);

      // 按 forumId 分组过期帖，仅处理 forumId > 0 的有效版块
      final byForum = <int, List<ForumThread>>{};
      for (final tid in staleIds) {
        final fav = currentFavorites.where((t) => t.threadId == tid);
        if (fav.isEmpty) continue;
        final thread = fav.first;
        if (thread.forumId <= 0) continue;
        byForum.putIfAbsent(thread.forumId, () => []).add(thread);
      }

      for (final entry in byForum.entries) {
        try {
          final result = await adapter.getThreads(
            forumId: entry.key,
            page: 1,
          );

          // 用 threadId 建索引，O(1) 匹配
          final freshMap = <int, ForumThread>{};
          for (final t in result.threads) {
            freshMap[t.threadId] = t;
          }

          for (final stale in entry.value) {
            final fresh = freshMap[stale.threadId];
            if (fresh == null) continue; // 不在首页，跳过
            FavoritesService.instance.updateMetadata(fresh);
          }
        } catch (_) {
          // 单个版块请求失败不影响其他版块
        }
      }

      // 统一刷新 UI
      state = FavoritesService.instance.all;
    } finally {
      _refreshing = false;
    }
  }

  /// 后台异步下载帖子首頁内容并写入文件缓存
  ///
  /// 在收藏操作成功时调用，不阻塞 UI，失败不影响收藏操作。
  void _downloadThreadContent(ForumThread thread) {
    final adapter = ref.read(forumAdapterProvider);
    Future(() async {
      try {
        final result = await adapter.getPosts(threadId: thread.threadId);
        final comments = await adapter.getComments(thread.threadId, page: 1);
        await ThreadContentCacheService.instance.save(
          threadId: thread.threadId,
          posts: result.posts,
          comments: comments,
          poll: result.poll,
          currentPage: result.currentPage,
          hasNextPage: result.hasNextPage,
          threadAuthorId: result.threadAuthorId,
          firstPagePostCount: result.posts.length,
        );
        // 后台下载正文图片、头像到帖子永久目录，表情走公共缓存池
        ThreadContentCacheService.instance
            .cacheImages(
              threadId: thread.threadId,
              posts: result.posts,
              comments: comments,
            )
            .ignore();
      } catch (_) {
        // 后台下载失败不影响收藏操作
      }
    }).ignore();
  }
}
