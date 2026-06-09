import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/forum_adapter/adapter.dart';
import 'package:fluxdo/forum_adapter/exceptions.dart';
import 'package:fluxdo/forum_adapter/models/forum_forum.dart';
import 'package:fluxdo/forum_adapter/models/forum_post.dart';
import 'package:fluxdo/forum_adapter/models/forum_results.dart';
import 'package:fluxdo/forum_adapter/models/forum_thread.dart';
import 'package:fluxdo/providers/forum_provider.dart';

Future<AsyncValue<List<ForumForum>>> _waitForForumListError(
  ProviderContainer container,
) {
  final completer = Completer<AsyncValue<List<ForumForum>>>();
  late final ProviderSubscription<AsyncValue<List<ForumForum>>> subscription;
  subscription = container.listen<AsyncValue<List<ForumForum>>>(
    forumListProvider,
    (_, next) {
      if (next.hasError && !completer.isCompleted) {
        completer.complete(next);
      }
    },
    fireImmediately: true,
  );

  return completer.future
      .timeout(const Duration(seconds: 5))
      .whenComplete(subscription.close);
}

class _FakeForumAdapter extends ForumAdapter {
  _FakeForumAdapter({this.fail = false});

  final bool fail;

  Future<void> _throwIfNeeded() async {
    await Future<void>.delayed(Duration.zero);
    if (fail) {
      throw const ForumNetworkException('测试网络失败');
    }
  }

  @override
  Future<List<ForumForum>> getForums() async {
    await _throwIfNeeded();
    return const [ForumForum(forumId: 2, name: '有码讨论')];
  }

  @override
  Future<ThreadListResult> getThreads({
    required int forumId,
    int? filterTypeId,
    int page = 1,
    SortMode? sort,
  }) async {
    await _throwIfNeeded();
    return ThreadListResult(
      threads: [
        ForumThread(
          threadId: 1001,
          forumId: forumId,
          title: '主题',
          author: '作者',
        ),
      ],
      currentPage: page,
      totalPages: 2,
      hasNextPage: page < 2,
    );
  }

  @override
  Future<PostListResult> getPosts({required int threadId, int page = 1}) async {
    await _throwIfNeeded();
    return PostListResult(
      posts: [
        ForumPost(
          postId: 501,
          threadId: threadId,
          floorNumber: 1,
          author: '楼主',
          contentHtml: '<p>正文</p>',
        ),
      ],
      currentPage: page,
      totalPages: 1,
      hasNextPage: false,
      threadTitle: '主题',
    );
  }
}

void main() {
  group('forum providers', () {
    test('loads forums, threads, and posts through ForumAdapter', () async {
      final container = ProviderContainer(
        overrides: [
          forumAdapterProvider.overrideWithValue(_FakeForumAdapter()),
        ],
      );
      addTearDown(container.dispose);

      final adapter = container.read(forumAdapterProvider);
      final forums = await container.read(forumListProvider.future);
      final threads = await adapter.getThreads(forumId: 2);
      final posts = await adapter.getPosts(threadId: 1001);

      expect(forums.single.name, '有码讨论');
      expect(threads.threads.single.threadId, 1001);
      expect(posts.posts.single.postId, 501);
    });

    test('propagates adapter errors as AsyncValue errors', () async {
      final container = ProviderContainer(
        overrides: [
          forumAdapterProvider.overrideWithValue(_FakeForumAdapter(fail: true)),
        ],
      );
      addTearDown(container.dispose);

      final errorState = await _waitForForumListError(container);

      expect(errorState.error, isA<ForumNetworkException>());
    });
  });
}
