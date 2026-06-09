import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/forum_adapter/javbus/parsers/forumdisplay_parser.dart';
import 'package:fluxdo/forum_adapter/javbus/utils/time_parser.dart';
import 'package:fluxdo/forum_adapter/javbus/utils/url_builder.dart';

void main() {
  group('ForumDisplayParser', () {
    final parser = ForumDisplayParser(
      urlBuilder: const JavBusUrlBuilder(),
      timeParser: DiscuzTimeParser(now: DateTime(2026, 6, 8, 12)),
    );

    test('parses pinned and normal threads with pagination', () {
      final html = File(
        'test/fixtures/javbus/forumdisplay_page_1.html',
      ).readAsStringSync();
      final result = parser.parse(html, forumId: 2);

      expect(result.threads, hasLength(2));
      expect(result.threads.first.threadId, 1001);
      expect(result.threads.first.isPinned, isTrue);
      expect(result.threads.first.title, '置顶公告');
      expect(result.threads.first.author, '管理员');
      expect(result.threads.first.replies, 2);
      expect(result.threads.first.views, 30);
      expect(result.threads.first.createdAt, DateTime(2026, 6, 7, 14, 30));
      expect(result.threads.last.isPinned, isFalse);
      expect(result.currentPage, 1);
      expect(result.totalPages, 2);
      expect(result.hasNextPage, isTrue);
    });

    test('parses mobile real reply counts from compact thread rows', () {
      final html = File(
        'test/fixtures/javbus/forumdisplay_mobile_real_stats.html',
      ).readAsStringSync();
      final result = parser.parse(html, forumId: 2);

      expect(result.threads, hasLength(2));
      expect(result.threads.first.threadId, 15172);
      expect(result.threads.first.replies, 2891);
      expect(result.threads.first.author, '管理员');
      expect(result.threads.first.authorId, 1);
      expect(result.threads.first.createdAt, DateTime(2017, 9, 9));
      expect(result.threads.last.threadId, 172074);
      expect(result.threads.last.replies, 61);
      expect(result.threads.last.author, 'hAIsEnky');
      expect(result.threads.last.authorId, 409091);
      expect(result.threads.last.createdAt, DateTime(2026, 6, 8, 9));
    });

    test('falls back to current time when created time is unparseable', () {
      const html = '''
        <html><body>
          <div class="thread">
            <a href="forum.php?mod=viewthread&tid=172070">缺少时间主题</a>
            <span>回 12</span>
          </div>
        </body></html>
      ''';

      final result = parser.parse(html, forumId: 2, requestUrl: 'https://example.test');

      expect(result.threads.single.threadId, 172070);
      expect(result.threads.single.createdAt, isNotNull);
      expect(result.threads.single.createdAt, isA<DateTime>());
    });

    test('parses last page without next page', () {
      final html = File(
        'test/fixtures/javbus/forumdisplay_page_2.html',
      ).readAsStringSync();
      final result = parser.parse(html, forumId: 2);

      expect(result.threads.single.threadId, 1003);
      expect(result.currentPage, 2);
      expect(result.totalPages, 2);
      expect(result.hasNextPage, isFalse);
    });
  });
}
