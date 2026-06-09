import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../forum_adapter/adapter.dart';
import '../forum_adapter/javbus/javbus_adapter.dart';
import '../forum_adapter/models/forum_forum.dart';
import '../forum_adapter/models/forum_results.dart';

final forumAdapterProvider = Provider<ForumAdapter>((ref) {
  return JavbusAdapter();
});

final forumListProvider = FutureProvider<List<ForumForum>>((ref) async {
  return ref.watch(forumAdapterProvider).getForums();
});

class ThreadListParams {
  const ThreadListParams({
    required this.forumId,
    this.filterTypeId,
    this.page = 1,
  });

  final int forumId;
  final int? filterTypeId;
  final int page;

  @override
  bool operator ==(Object other) {
    return other is ThreadListParams &&
        other.forumId == forumId &&
        other.filterTypeId == filterTypeId &&
        other.page == page;
  }

  @override
  int get hashCode => Object.hash(forumId, filterTypeId, page);
}

final threadListProvider =
    FutureProvider.family<ThreadListResult, ThreadListParams>((ref, params) {
      return ref
          .watch(forumAdapterProvider)
          .getThreads(
            forumId: params.forumId,
            filterTypeId: params.filterTypeId,
            page: params.page,
          );
    });

class PostListParams {
  const PostListParams({required this.threadId, this.page = 1});

  final int threadId;
  final int page;

  @override
  bool operator ==(Object other) {
    return other is PostListParams &&
        other.threadId == threadId &&
        other.page == page;
  }

  @override
  int get hashCode => Object.hash(threadId, page);
}

final postListProvider = FutureProvider.family<PostListResult, PostListParams>((
  ref,
  params,
) {
  return ref
      .watch(forumAdapterProvider)
      .getPosts(threadId: params.threadId, page: params.page);
});
