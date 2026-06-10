import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/forum_adapter/adapter.dart';
import 'package:fluxdo/forum_adapter/exceptions.dart';
import 'package:fluxdo/forum_adapter/models/forum_attachment.dart';
import 'package:fluxdo/forum_adapter/models/forum_forum.dart';
import 'package:fluxdo/forum_adapter/models/forum_post.dart';
import 'package:fluxdo/forum_adapter/models/forum_results.dart';
import 'package:fluxdo/forum_adapter/models/forum_thread.dart';

class _UnsupportedAdapter extends ForumAdapter {
  @override
  Future<List<ForumForum>> getForums() async => const [];

  @override
  Future<ThreadListResult> getThreads({
    required int forumId,
    int? filterTypeId,
    int page = 1,
    SortMode? sort,
  }) async {
    return const ThreadListResult(
      threads: [],
      currentPage: 1,
      totalPages: 1,
      hasNextPage: false,
    );
  }

  @override
  Future<PostListResult> getPosts({required int threadId, int page = 1}) async {
    return const PostListResult(
      posts: [],
      currentPage: 1,
      totalPages: 1,
      hasNextPage: false,
      threadTitle: '',
    );
  }

  @override
  Future<SearchResult> search(String keyword,
      {int? searchId, int page = 1}) async {
    throw const UnsupportedForumFeatureException('搜索功能将在后续阶段实现');
  }
}

void main() {
  group('forum models', () {
    test('ForumForum uses typed defaults for anonymous browsing fields', () {
      const forum = ForumForum(forumId: 2, name: '有码讨论');

      expect(forum.forumId, 2);
      expect(forum.name, '有码讨论');
      expect(forum.description, isNull);
      expect(forum.parentForumId, isNull);
      expect(forum.filterTypeId, isNull);
      expect(forum.threadCount, 0);
      expect(forum.todayPostCount, 0);
      expect(forum.url, isNull);
    });

    test('ForumThread uses typed defaults for optional counters and flags', () {
      const thread = ForumThread(
        threadId: 123,
        forumId: 2,
        title: '标题',
        author: '作者',
      );

      expect(thread.replies, 0);
      expect(thread.views, 0);
      expect(thread.isPinned, false);
      expect(thread.isDigest, false);
      expect(thread.hasAttachment, false);
      expect(thread.attachments, isEmpty);
      expect(thread.createdAt, isNull);
      expect(thread.lastReplyAt, isNull);
    });

    test('ForumPost stores sanitized HTML and attachments', () {
      const attachment = ForumAttachment(
        fileName: 'cover.jpg',
        url: 'https://www.javbus.com/forum/data/attachment/forum/cover.jpg',
        thumbnailUrl: 'https://www.javbus.com/forum/thumb.jpg',
        fileSize: '128 KB',
        mimeType: 'image/jpeg',
      );
      const post = ForumPost(
        postId: 456,
        threadId: 123,
        floorNumber: 1,
        author: '楼主',
        contentHtml: '<p>正文</p>',
        attachments: [attachment],
        isThreadAuthor: true,
      );

      expect(post.contentHtml, '<p>正文</p>');
      expect(post.attachments, hasLength(1));
      expect(post.attachments.single.fileName, 'cover.jpg');
      expect(post.isThreadAuthor, isTrue);
      expect(post.avatarUrl, isNull);
    });

    test('result containers preserve pagination metadata', () {
      const threads = ThreadListResult(
        threads: [
          ForumThread(threadId: 123, forumId: 2, title: '标题', author: '作者'),
        ],
        currentPage: 2,
        totalPages: 5,
        hasNextPage: true,
      );
      const posts = PostListResult(
        posts: [
          ForumPost(
            postId: 456,
            threadId: 123,
            floorNumber: 1,
            author: '楼主',
            contentHtml: '<p>正文</p>',
          ),
        ],
        currentPage: 1,
        totalPages: 1,
        hasNextPage: false,
        threadTitle: '标题',
      );

      expect(threads.threads.single.threadId, 123);
      expect(threads.hasNextPage, isTrue);
      expect(posts.threadTitle, '标题');
      expect(posts.hasNextPage, isFalse);
    });
  });

  group('forum exceptions', () {
    test('ForumException keeps request context in toString', () {
      const exception = ForumResponseException(
        '返回内容不是 XHTML Mobile 页面',
        requestUrl: 'https://www.javbus.com/forum/api/mobile/index.php',
        statusCode: 403,
        responseSnippet: '<html>forbidden</html>',
      );

      expect(exception.message, contains('XHTML'));
      expect(exception.requestUrl, contains('javbus.com'));
      expect(exception.statusCode, 403);
      expect(exception.toString(), contains('403'));
      expect(exception.toString(), contains('forbidden'));
    });

    test('ForumParseException includes parser name', () {
      const exception = ForumParseException(
        '未找到帖子楼层',
        parserName: 'ViewthreadParser',
        requestUrl: 'https://www.javbus.com/forum/',
      );

      expect(exception.parserName, 'ViewthreadParser');
      expect(exception.toString(), contains('ViewthreadParser'));
    });
  });

  group('ForumAdapter unsupported first-stage features', () {
    test('login and posting APIs throw explicit unsupported errors', () async {
      final adapter = _UnsupportedAdapter();

      await expectLater(
        adapter.login(username: 'user', password: 'pass'),
        throwsA(isA<UnsupportedForumFeatureException>()),
      );
      await expectLater(
        adapter.createThread(forumId: 2, title: '标题', content: '正文'),
        throwsA(isA<UnsupportedForumFeatureException>()),
      );
      await expectLater(
        adapter.reply(threadId: 123, content: '回复'),
        throwsA(isA<UnsupportedForumFeatureException>()),
      );
    });
  });
}
