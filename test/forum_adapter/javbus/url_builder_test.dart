import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/forum_adapter/javbus/utils/url_builder.dart';

void main() {
  group('JavBusUrlBuilder', () {
    const builder = JavBusUrlBuilder();

    test('resolves paths under forum base URL', () {
      expect(
        builder.resolve('data/attachment/forum/a.jpg'),
        'https://www.javbus.com/forum/data/attachment/forum/a.jpg',
      );
      expect(
        builder.resolve('/forum/data/attachment/forum/a.jpg'),
        'https://www.javbus.com/forum/data/attachment/forum/a.jpg',
      );
      expect(
        builder.resolve('forum.php?mod=viewthread&tid=123'),
        'https://www.javbus.com/forum/forum.php?mod=viewthread&tid=123',
      );
    });

    test('keeps absolute and protocol-relative URLs', () {
      expect(
        builder.resolve('https://cdn.example/a.jpg'),
        'https://cdn.example/a.jpg',
      );
      expect(
        builder.resolve('//cdn.example/a.jpg'),
        'https://cdn.example/a.jpg',
      );
    });

    test('treats host-like image URLs as https URLs', () {
      expect(
        builder.resolve('forum.javcdn.cc/i.imgur.com/Ts9d6xp.jpeg'),
        'https://forum.javcdn.cc/i.imgur.com/Ts9d6xp.jpeg',
      );
      expect(
        builder.resolve('i.imgur.com/Ts9d6xp.jpeg'),
        'https://i.imgur.com/Ts9d6xp.jpeg',
      );
    });

    test('normalizes custom base URL trailing slash', () {
      const custom = JavBusUrlBuilder(baseUrl: 'https://example.test/forum');

      expect(
        custom.resolve('api/mobile/index.php'),
        'https://example.test/forum/api/mobile/index.php',
      );
    });
  });
}
