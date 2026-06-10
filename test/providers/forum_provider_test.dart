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
import 'package:fluxdo/services/forum_cache_service.dart';

/// 等待 NotifierProvider 进入 data 状态并返回数据
Future<List<ForumForum>> _waitForForumListData(
  ProviderContainer container,
) {
  final completer = Completer<List<ForumForum>>();
  late final ProviderSubscription<AsyncValue<List<ForumForum>>> subscription;
  subscription = container.listen<AsyncValue<List<ForumForum>>>(
    forumListProvider,
    (_, next) {
      if (next is AsyncData && !completer.isCompleted) {
        completer.complete(next.value);
      }
    },
    fireImmediately: true,
  );

  return completer.future
      .timeout(const Duration(seconds: 5))
      .whenComplete(subscription.close);
}

/// 等待 NotifierProvider 进入 error 状态
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
  Future<SearchResult> search(String keyword, {int? searchId, int page = 1}) async {
    throw UnimplementedError('search not implemented');
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
    setUp(() {
      // 确保每个测试从干净的缓存状态开始
      ForumCacheService.instance.clearForTest();
    });

    test('loads forums, threads, and posts through ForumAdapter', () async {
      final container = ProviderContainer(
        overrides: [
          forumAdapterProvider.overrideWithValue(_FakeForumAdapter()),
        ],
      );
      addTearDown(container.dispose);

      final adapter = container.read(forumAdapterProvider);
      // NotifierProvider 使用异步 build，等待状态到达 data
      final forums = await _waitForForumListData(container);
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
