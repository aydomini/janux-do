import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/forum_adapter/exceptions.dart';
import 'package:fluxdo/forum_adapter/javbus/parsers/viewthread_parser.dart';
import 'package:fluxdo/forum_adapter/javbus/parsers/post_html_cleaner.dart';
import 'package:fluxdo/forum_adapter/javbus/utils/time_parser.dart';
import 'package:fluxdo/forum_adapter/javbus/utils/url_builder.dart';

void main() {
  group('ViewThreadParser', () {
    final parser = ViewThreadParser(
      urlBuilder: const JavBusUrlBuilder(),
      timeParser: DiscuzTimeParser(now: DateTime(2026, 6, 8, 12)),
      htmlCleaner: const PostHtmlCleaner(urlBuilder: JavBusUrlBuilder()),
    );

    test('parses thread title and posts', () {
      final html = File(
        'test/fixtures/javbus/viewthread_single_page.html',
      ).readAsStringSync();
      final result = parser.parse(html, threadId: 1002);

      expect(result.threadTitle, '普通主题');
      expect(result.posts, hasLength(2));
      expect(result.posts.first.postId, 501);
      expect(result.posts.first.threadId, 1002);
      expect(result.posts.first.floorNumber, 1);
      expect(result.posts.first.author, '楼主');
      expect(result.posts.first.authorId, 42);
      expect(result.posts.first.isThreadAuthor, isTrue);
      expect(result.posts.first.createdAt, DateTime(2026, 6, 7, 10));
      expect(result.posts.last.isThreadAuthor, isFalse);
      expect(result.currentPage, 1);
      expect(result.totalPages, 1);
      expect(result.hasNextPage, isFalse);
    });

    test('cleans lazy images and attachment links in post content', () {
      final html = File(
        'test/fixtures/javbus/viewthread_with_images.html',
      ).readAsStringSync();
      final result = parser.parse(html, threadId: 1004);

      expect(result.threadTitle, '图片主题');
      expect(
        result.posts.single.contentHtml,
        contains('https://www.javbus.com/forum/data/attachment/forum/a.jpg'),
      );
      expect(
        result.posts.single.contentHtml,
        contains(
          'https://www.javbus.com/forum/forum.php?mod=attachment&amp;aid=abc',
        ),
      );
      expect(result.posts.single.attachments, hasLength(1));
      expect(result.posts.single.attachments.single.attachmentId, 'abc');
      expect(result.posts.single.attachments.single.fileName, '附件.txt');
      expect(
        result.posts.single.attachments.single.url,
        'https://www.javbus.com/forum/forum.php?mod=attachment&aid=abc',
      );
      expect(result.posts.single.contentHtml, isNot(contains('secret')));
      expect(result.posts.single.contentHtml, contains('visible'));
    });

    test('parses common Discuz mobile postlist structure', () {
      final html = File(
        'test/fixtures/javbus/viewthread_discuz_mobile.html',
      ).readAsStringSync();
      final result = parser.parse(html, threadId: 1005);

      expect(result.threadTitle, '真实移动结构主题');
      expect(result.posts, hasLength(2));
      expect(result.posts.first.postId, 701);
      expect(result.posts.first.author, '真实楼主');
      expect(result.posts.first.authorId, 101);
      expect(result.posts.first.floorNumber, 1);
      expect(result.posts.first.contentHtml, contains('第一楼正文'));
      expect(result.posts.last.postId, 702);
      expect(result.posts.last.author, '回复用户');
      expect(result.posts.last.floorNumber, 2);
      expect(result.posts.last.contentHtml, contains('第二楼正文'));
      expect(result.posts.last.attachments.single.attachmentId, 'xyz');
      expect(result.currentPage, 1);
      expect(result.totalPages, 2);
      expect(result.hasNextPage, isTrue);
    });

    test('解析 Discuz 桌面 postmessage 正文结构', () {
      final html = File(
        'test/fixtures/javbus/viewthread_discuz_desktop.html',
      ).readAsStringSync();
      final result = parser.parse(html, threadId: 1006);

      expect(result.threadTitle, '桌面结构主题');
      expect(result.posts, hasLength(2));
      expect(result.posts.first.postId, 801);
      expect(result.posts.first.author, '桌面楼主');
      expect(result.posts.first.authorId, 201);
      expect(
        result.posts.first.avatarUrl,
        'https://www.javbus.com/forum/uc_server/avatar.php?uid=201&size=middle',
      );
      expect(result.posts.first.floorNumber, 1);
      expect(result.posts.first.createdAt, DateTime(2026, 6, 8, 10, 20));
      expect(result.posts.first.contentHtml, contains('桌面第一楼正文'));
      expect(result.posts.last.postId, 802);
      expect(result.posts.last.author, '桌面回复者');
      expect(
        result.posts.last.avatarUrl,
        'https://www.javbus.com/forum/uc_server/avatar.php?uid=202&size=middle',
      );
      expect(result.posts.last.floorNumber, 2);
      expect(result.posts.last.createdAt, DateTime(2026, 6, 8, 11, 20));
      expect(result.posts.last.contentHtml, contains('桌面回复正文'));
      expect(result.hasNextPage, isTrue);
    });

    test('无 message 包裹时也能解析 postmessage 正文', () {
      final html = File(
        'test/fixtures/javbus/viewthread_postmessage_only.html',
      ).readAsStringSync();
      final result = parser.parse(html, threadId: 1007);

      expect(result.threadTitle, 'PostMessage 结构主题');
      expect(result.posts, hasLength(2));
      expect(result.posts.first.contentHtml, contains('postmessage 第一楼正文'));
      expect(result.posts.last.contentHtml, contains('postmessage 回复正文'));
    });

    test('解析 pid 锚点后相邻楼层容器里的正文图片和附件', () {
      final html = File(
        'test/fixtures/javbus/viewthread_mobile_pid_sibling.html',
      ).readAsStringSync();
      final result = parser.parse(html, threadId: 1008);

      expect(result.threadTitle, '移动相邻结构主题');
      expect(result.posts, hasLength(2));
      expect(result.posts.first.postId, 1001);
      expect(result.posts.first.author, '相邻楼主');
      expect(result.posts.first.authorId, 401);
      expect(result.posts.first.floorNumber, 1);
      expect(result.posts.first.contentHtml, contains('相邻第一楼正文'));
      expect(
        result.posts.first.contentHtml,
        contains(
          'https://www.javbus.com/forum/data/attachment/forum/cover.jpg',
        ),
      );
      expect(result.posts.first.attachments.single.attachmentId, 'sibling-aid');
      expect(result.posts.first.attachments.single.fileName, '相邻附件.zip');
      expect(result.posts.last.postId, 1002);
      expect(result.posts.last.author, '相邻回复者');
      expect(result.posts.last.floorNumber, 2);
      expect(result.posts.last.contentHtml, contains('相邻回复正文'));
      expect(
        result.posts.last.contentHtml,
        contains(
          'https://www.javbus.com/forum/data/attachment/forum/reply.jpg',
        ),
      );
      expect(result.hasNextPage, isTrue);
    });

    test('解析到楼层但没有任何正文时抛出解析错误', () {
      final html = File(
        'test/fixtures/javbus/viewthread_empty_content.html',
      ).readAsStringSync();

      expect(
        () => parser.parse(html, threadId: 1009),
        throwsA(
          isA<ForumParseException>().having(
            (error) => error.message,
            'message',
            contains('未解析到任何帖子正文'),
          ),
        ),
      );
    });

    test('解析 Discuz mobile API XML 中的帖子正文图片和附件', () {
      final html = File(
        'test/fixtures/javbus/viewthread_mobile_api.xml',
      ).readAsStringSync();
      final result = parser.parse(html, threadId: 1010);

      expect(result.threadTitle, '移动 API 主题');
      expect(result.currentPage, 1);
      expect(result.totalPages, 3);
      expect(result.hasNextPage, isTrue);
      expect(result.posts, hasLength(2));
      expect(result.posts.first.postId, 1201);
      expect(result.posts.first.floorNumber, 1);
      expect(result.posts.first.author, 'API 楼主');
      expect(result.posts.first.authorId, 601);
      expect(result.posts.first.contentHtml, contains('API 第一楼正文'));
      expect(
        result.posts.first.contentHtml,
        contains(
          'https://www.javbus.com/forum/data/attachment/forum/api-cover.jpg',
        ),
      );
      expect(result.posts.first.attachments.single.attachmentId, 'api-aid');
      expect(result.posts.first.attachments.single.fileName, 'API附件.rar');
      expect(result.posts.last.postId, 1202);
      expect(result.posts.last.author, 'API 回复者');
      expect(result.posts.last.contentHtml, contains('API 回复正文'));
    });

    test('解析 XHTML Mobile 空 pid 锚点后兄弟节点里的正文图片和附件', () {
      final html = File(
        'test/fixtures/javbus/viewthread_xhtml_mobile_sibling_scope.html',
      ).readAsStringSync();
      final result = parser.parse(html, threadId: 1011);

      expect(result.threadTitle, 'XHTML Mobile 主题');
      expect(result.posts, hasLength(2));
      expect(result.posts.first.postId, 1301);
      expect(result.posts.first.author, 'XHTML 楼主');
      expect(result.posts.first.authorId, 701);
      expect(result.posts.first.contentHtml, contains('XHTML 第一楼正文'));
      expect(
        result.posts.first.contentHtml,
        contains(
          'https://www.javbus.com/forum/data/attachment/forum/xhtml-cover.jpg',
        ),
      );
      expect(result.posts.first.attachments.single.attachmentId, 'xhtml-aid');
      expect(result.posts.first.attachments.single.fileName, 'XHTML附件.7z');
      expect(result.posts.last.postId, 1302);
      expect(result.posts.last.author, 'XHTML 回复者');
      expect(result.posts.last.contentHtml, contains('XHTML 回复正文'));
    });

    test('解析 JavBus XHTML Mobile 楼层头和正文分离结构', () {
      final html = File(
        'test/fixtures/javbus/viewthread_javbus_xhtml_mobile_split.html',
      ).readAsStringSync();
      final result = parser.parse(html, threadId: 172070);

      expect(result.threadTitle, 'JavBus XHTML Mobile 真实分离结构');
      expect(result.posts, hasLength(2));
      expect(result.posts.first.postId, 1401);
      expect(result.posts.first.author, '真实楼主');
      expect(result.posts.first.authorId, 801);
      expect(result.posts.first.floorNumber, 1);
      expect(result.posts.first.createdAt, DateTime(2026, 6, 8, 10));
      expect(result.posts.first.contentHtml, contains('JavBus 第一楼正文'));
      expect(
        result.posts.first.contentHtml,
        contains(
          'https://www.javbus.com/forum/data/attachment/forum/javbus-cover.jpg',
        ),
      );
      expect(result.posts.first.attachments.single.attachmentId, 'real-aid');
      expect(result.posts.first.attachments.single.fileName, '真实附件.zip');
      expect(result.posts.last.postId, 1402);
      expect(result.posts.last.author, '回复用户');
      expect(result.posts.last.floorNumber, 9);
      expect(result.posts.last.createdAt, DateTime(2026, 6, 8, 11));
      expect(result.posts.last.contentHtml, contains('JavBus 第二楼回复正文'));
      expect(result.currentPage, 1);
      expect(result.totalPages, 7);
      expect(result.hasNextPage, isTrue);
    });
  });
}
