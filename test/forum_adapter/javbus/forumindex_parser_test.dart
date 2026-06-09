import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/forum_adapter/exceptions.dart';
import 'package:fluxdo/forum_adapter/javbus/parsers/forumindex_parser.dart';
import 'package:fluxdo/forum_adapter/javbus/utils/url_builder.dart';

void main() {
  group('ForumIndexParser', () {
    const parser = ForumIndexParser(urlBuilder: JavBusUrlBuilder());

    test('parses forum links from XHTML mobile forum index', () {
      final html = File(
        'test/fixtures/javbus/forumindex.html',
      ).readAsStringSync();
      final forums = parser.parse(html);

      expect(forums, hasLength(2));
      expect(forums.first.forumId, 2);
      expect(forums.first.name, '有码讨论');
      expect(forums.first.description, contains('有码作品交流'));
      expect(forums.first.threadCount, 12);
      expect(forums.first.todayPostCount, 3);
      expect(
        forums.first.url,
        'https://www.javbus.com/forum/forum.php?mod=forumdisplay&fid=2',
      );
    });

    test('parses all forum entries from desktop forum index', () {
      final html = File(
        'test/fixtures/javbus/forumindex_desktop_full.html',
      ).readAsStringSync();
      final forums = parser.parse(html);

      expect(forums.map((forum) => forum.name), [
        '老司機福利討論區',
        '求福利帶帶我',
        '網站建議阿哩哩',
        '日本AV',
        '韓國成人',
        '歐美色情',
        '國產福利',
        '動漫遊戲',
        '性息尋歡分享',
      ]);
      expect(forums.first.forumId, 2);
      expect(forums.first.threadCount, 38827);
      expect(forums.first.todayPostCount, 619);
      final japaneseAv = forums[3];
      expect(japaneseAv.forumId, 2);
      expect(japaneseAv.filterTypeId, 8);
      expect(japaneseAv.description, contains('日本AV影片'));
      expect(
        japaneseAv.url,
        'https://www.javbus.com/forum/forum.php?mod=forumdisplay&fid=2&filter=typeid&typeid=8',
      );
    });

    test('throws parse exception when no forum links are found', () {
      expect(
        () => parser.parse('<html><body>unexpected</body></html>'),
        throwsA(isA<ForumParseException>()),
      );
    });
  });
}
