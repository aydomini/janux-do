import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../forum_adapter/models/forum_thread.dart';
import '../services/favorites_service.dart';

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
  @override
  List<ForumThread> build() {
    // 初始化服务并加载缓存
    final service = FavoritesService.instance;
    // init 是异步的，但 build 必须同步返回。
    // 使用初始空列表，init 完成后手动刷新。
    _initAsync();
    return service.all;
  }

  Future<void> _initAsync() async {
    await FavoritesService.instance.init();
    state = FavoritesService.instance.all;
  }

  /// 切换收藏状态，返回操作后的状态（true=已收藏）
  bool toggle(ForumThread thread) {
    final result = FavoritesService.instance.toggle(thread);
    state = FavoritesService.instance.all;
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
}
