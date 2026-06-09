import 'exceptions.dart';
import 'models/forum_forum.dart';
import 'models/forum_results.dart';

abstract class ForumAdapter {
  Future<List<ForumForum>> getForums();

  Future<ThreadListResult> getThreads({
    required int forumId,
    int? filterTypeId,
    int page = 1,
  });

  Future<PostListResult> getPosts({required int threadId, int page = 1});

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
}
