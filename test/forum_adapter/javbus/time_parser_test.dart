import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/forum_adapter/javbus/utils/time_parser.dart';

void main() {
  group('DiscuzTimeParser', () {
    final parser = DiscuzTimeParser(now: DateTime(2026, 6, 8, 12));

    test('parses absolute Discuz dates', () {
      expect(parser.parse('2026-6-7 14:30'), DateTime(2026, 6, 7, 14, 30));
      expect(parser.parse('2026-06-07 14:30'), DateTime(2026, 6, 7, 14, 30));
    });

    test('parses relative Chinese times', () {
      expect(parser.parse('1 分钟前'), DateTime(2026, 6, 8, 11, 59));
      expect(parser.parse('5 小时前'), DateTime(2026, 6, 8, 7));
      expect(parser.parse('3 天前'), DateTime(2026, 6, 5, 12));
    });

    test('parses yesterday and day before yesterday', () {
      expect(parser.parse('昨天 14:30'), DateTime(2026, 6, 7, 14, 30));
      expect(parser.parse('前天 10:00'), DateTime(2026, 6, 6, 10));
    });

    test('returns null for unknown formats', () {
      expect(parser.parse('not time'), isNull);
      expect(parser.parse(''), isNull);
    });
  });
}
