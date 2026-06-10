import 'exceptions.dart';
import 'models/forum_forum.dart';
import 'models/forum_post.dart';
import 'models/forum_results.dart';

enum SortMode { latest, hot, trending, digest }

abstract class ForumAdapter {
  Future<List<ForumForum>> getForums();

  Future<ThreadListResult> getThreads({
    required int forumId,
    int? filterTypeId,
    int page = 1,
    SortMode? sort,
  });

  Future<PostListResult> getPosts({required int threadId, int page = 1});

  /// 论坛帖子搜索（匿名可用，60 秒冷却）
  ///
  /// 首次搜索不传 [searchId]，Discuz 分配 searchid 后通过
  /// [SearchResult.searchId] 返回，用于后续翻页。
  Future<SearchResult> search(String keyword, {int? searchId, int page = 1});

  /// 获取楼中楼点评（从桌面版 HTML 解析 pstl 块）
  Future<Map<int, List<ForumComment>>> getComments(int threadId, {int page = 1}) async {
    return {};
  }

  Future<void> login({
    required String username,
    required String password,
  }) async {
    throw const UnsupportedForumFeatureException('登录功能将在后续阶段实现');
  }

  Future<void> createThread({
    required int forumId,
    required String title,
    required String content,
  }) async {
    throw const UnsupportedForumFeatureException('发帖功能将在后续阶段实现');
  }

  Future<void> reply({required int threadId, required String content}) async {
    throw const UnsupportedForumFeatureException('回复功能将在后续阶段实现');
  }

  /// 启动阶段预热：校验 Cookie 有效性并建立会话。
  ///
  /// 返回 true 表示会话就绪。默认实现返回 true，
  /// 子类可按需覆盖执行实际网络预热。
  Future<bool> warmUpSession() async => true;
}
