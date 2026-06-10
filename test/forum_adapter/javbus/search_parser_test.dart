import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/forum_adapter/javbus/parsers/search_parser.dart';
import 'package:fluxdo/forum_adapter/javbus/utils/time_parser.dart';
import 'package:fluxdo/forum_adapter/javbus/utils/url_builder.dart';

void main() {
  group('SearchParser', () {
    final parser = SearchParser(
      urlBuilder: const JavBusUrlBuilder(),
      timeParser: DiscuzTimeParser(now: DateTime(2026, 6, 8, 12)),
    );

    test('parses search results with pagination and stats', () {
      final html = File(
        'test/fixtures/javbus/search_result_page_1.html',
      ).readAsStringSync();
      final result = parser.parse(html);

      expect(result.totalResults, 60);
      expect(result.matchedKeyword, 'SSIS');
      expect(result.searchId, 1814);
      expect(result.currentPage, 1);
      expect(result.totalPages, 2);
      expect(result.hasNextPage, isTrue);

      expect(result.threads, hasLength(3));

      // 第一个结果：带高亮标签的标题
      expect(result.threads[0].threadId, 170484);
      expect(result.threads[0].title, '求香水纯的SSIS-876【9.6G】');
      expect(result.threads[0].author, '二流子呀呀哟');
      expect(result.threads[0].authorId, 400291);
      expect(result.threads[0].replies, 26);
      expect(result.threads[0].views, 15036);
      expect(result.threads[0].createdAt, DateTime(2026, 5, 2, 10, 56));
      expect(result.threads[0].forumId, 36);
      expect(result.threads[0].forumName, '求福利帶帶我');
      expect(result.threads[0].excerpt, '要LADA跑的，9.6G版本的，LADA跑的真和无码似的。');
      expect(result.threads[0].isPinned, isFalse);

      // 第二个结果
      expect(result.threads[1].threadId, 170348);
      expect(result.threads[1].title, '求一个剧情AV');
      expect(result.threads[1].author, 'dlgkhouse');
      expect(result.threads[1].replies, 2);
      expect(result.threads[1].views, 3786);
      expect(result.threads[1].createdAt, DateTime(2026, 4, 27, 17, 13));
      expect(result.threads[1].forumName, '求福利帶帶我');

      // 第三个结果：不同版块 + 大数字
      expect(result.threads[2].threadId, 129236);
      expect(result.threads[2].replies, 114);
      expect(result.threads[2].views, 223183);
      expect(result.threads[2].createdAt, DateTime(2023, 12, 27, 11, 18));
      expect(result.threads[2].forumId, 2);
      expect(result.threads[2].forumName, '老司機福利討論區');
    });

    test('parses empty search results', () {
      const html = '''
        <html><body>
          <div class="tl">
            <div class="sttl mbn">
              <h2>結果: <em>找到 「NOTFOUND」 相關內容 0 個</em></h2>
            </div>
            <div class="slst mtw" id="threadlist">
              <ul></ul>
            </div>
          </div>
        </body></html>
      ''';
      final result = parser.parse(html);

      expect(result.threads, isEmpty);
      expect(result.totalResults, 0);
      expect(result.matchedKeyword, 'NOTFOUND');
      expect(result.totalPages, 1);
      expect(result.hasNextPage, isFalse);
    });
  });
}
