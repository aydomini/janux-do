import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/forum_adapter/javbus/parsers/post_html_cleaner.dart';
import 'package:fluxdo/forum_adapter/javbus/utils/url_builder.dart';

void main() {
  group('PostHtmlCleaner', () {
    const cleaner = PostHtmlCleaner(urlBuilder: JavBusUrlBuilder());

    test('restores Discuz lazy image file attribute', () {
      final cleaned = cleaner.clean(
        '<img src="static/image/common/none.gif" file="data/attachment/forum/a.jpg"/>',
      );

      expect(
        cleaned,
        contains(
          'src="https://www.javbus.com/forum/data/attachment/forum/a.jpg"',
        ),
      );
      expect(cleaned, isNot(contains('file="data/attachment')));
    });

    test('resolves relative links and removes unsupported BBCode blocks', () {
      final cleaned = cleaner.clean(
        '<a href="forum.php?mod=attachment&amp;aid=abc">附件</a> [hide]secret[/hide] visible',
      );

      expect(
        cleaned,
        contains(
          'href="https://www.javbus.com/forum/forum.php?mod=attachment&amp;aid=abc"',
        ),
      );
      expect(cleaned, contains('visible'));
      expect(cleaned, isNot(contains('secret')));
    });

    test(
      'removes low contrast inline text colors but keeps emphasis colors',
      () {
        final cleaned = cleaner.clean(
          '<p>'
          '<span style="color:#000000; font-weight: bold">暗色不可读正文</span>'
          '<span style="color: #000 !important">强制黑色正文</span>'
          '<font color="black">黑色字体标签</font>'
          '<span style="color: rgb(4, 4, 4)">接近黑色正文</span>'
          '<span style="color: red">红色重点</span>'
          '<span style="color:#ff0000">十六进制红色重点</span>'
          '</p>',
        );

        expect(cleaned, contains('暗色不可读正文'));
        expect(cleaned, contains('font-weight: bold'));
        expect(cleaned, contains('强制黑色正文'));
        expect(cleaned, contains('黑色字体标签'));
        expect(cleaned, contains('接近黑色正文'));
        expect(cleaned, contains('color: red'));
        expect(cleaned, contains('color:#ff0000'));
        expect(cleaned, isNot(contains('color:#000000')));
        expect(cleaned, isNot(contains('#000 !important')));
        expect(cleaned, isNot(contains('color="black"')));
        expect(cleaned, isNot(contains('rgb(4, 4, 4)')));
      },
    );
  });
}
