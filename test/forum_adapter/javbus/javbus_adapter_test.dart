import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/forum_adapter/exceptions.dart';
import 'package:fluxdo/forum_adapter/javbus/javbus_adapter.dart';

class _RecordedRequest {
  _RecordedRequest({required this.uri, required this.headers});

  final Uri uri;
  final Map<String, dynamic> headers;
}

class _FixtureAdapter implements HttpClientAdapter {
  _FixtureAdapter(this.responses, {this.failFirstRequest = false});

  final Map<String, String> responses;
  final bool failFirstRequest;
  final requests = <_RecordedRequest>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(
      _RecordedRequest(uri: options.uri, headers: Map.of(options.headers)),
    );
    if (failFirstRequest && requests.length == 1) {
      throw DioException.connectionTimeout(
        timeout: const Duration(seconds: 1),
        requestOptions: options,
      );
    }
    final key =
        options.uri.queryParameters['module'] ??
        options.uri.queryParameters['mod'] ??
        _fixtureKeyForPath(options.uri.path) ??
        options.uri.path;
    final response = responses[key];
    if (response == null) {
      return ResponseBody.fromString('missing fixture for $key', 404);
    }
    return ResponseBody.fromString(
      response,
      200,
      headers: {
        Headers.contentTypeHeader: ['text/html; charset=utf-8'],
        if (key == 'home') 'set-cookie': ['bus_session=abc123; Path=/'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

String? _fixtureKeyForPath(String path) {
  if (path == '/' || path.isEmpty) return 'home';
  if (path == '/forum/' || path == '/forum/forum.php') return 'forum_home';
  return null;
}

String _fixture(String name) {
  return File('test/fixtures/javbus/$name').readAsStringSync();
}

void main() {
  group('JavbusAdapter', () {
    test('getForums requests forum index and parses typed forums', () async {
      final fixtureAdapter = _FixtureAdapter({
        'home': '<html><body>JavBus</body></html>',
        'forum_home': _fixture('forumindex_desktop_full.html'),
      });
      final dio = Dio()..httpClientAdapter = fixtureAdapter;
      final adapter = JavbusAdapter(dio: dio);

      final forums = await adapter.getForums();

      expect(forums, hasLength(9));
      expect(forums.first.forumId, 2);
      expect(forums[3].name, '日本AV');
      expect(forums[3].filterTypeId, 8);
      expect(fixtureAdapter.requests, hasLength(2));
      expect(
        fixtureAdapter.requests.first.uri.toString(),
        'https://www.javbus.com/',
      );
      expect(
        fixtureAdapter.requests.last.uri.toString(),
        'https://www.javbus.com/forum/',
      );
      expect(
        fixtureAdapter.requests.last.headers['User-Agent'],
        contains('Firefox'),
      );
      expect(
        fixtureAdapter.requests.first.headers.containsKey('Referer'),
        isFalse,
      );
      expect(
        fixtureAdapter.requests.last.headers['Referer'],
        'https://www.javbus.com/',
      );
      expect(fixtureAdapter.requests.last.headers['Accept-Language'], contains('zh-CN'));
      expect(
        fixtureAdapter.requests.last.headers['Sec-Fetch-Dest'],
        'document',
      );
      expect(
        fixtureAdapter.requests.last.headers['Upgrade-Insecure-Requests'],
        '1',
      );
      expect(
        fixtureAdapter.requests.last.headers['Cookie'],
        'bus_session=abc123',
      );
    });

    test(
      'getThreads keeps typeid filter when forum entry has category filter',
      () async {
        final fixtureAdapter = _FixtureAdapter({
          'forumdisplay': _fixture('forumdisplay_page_1.html'),
        });
        final dio = Dio()..httpClientAdapter = fixtureAdapter;
        final adapter = JavbusAdapter(dio: dio);

        await adapter.getThreads(forumId: 2, filterTypeId: 8, page: 1);

        final uri = fixtureAdapter.requests.single.uri;
        expect(uri.queryParameters['module'], 'forumdisplay');
        expect(uri.queryParameters['fid'], '2');
        expect(uri.queryParameters['filter'], 'typeid');
        expect(uri.queryParameters['typeid'], '8');
      },
    );

    test('getThreads requests forumdisplay and parses thread result', () async {
      final fixtureAdapter = _FixtureAdapter({
        'forumdisplay': _fixture('forumdisplay_page_1.html'),
      });
      final dio = Dio()..httpClientAdapter = fixtureAdapter;
      final adapter = JavbusAdapter(dio: dio);

      final result = await adapter.getThreads(forumId: 2, page: 1);

      expect(result.threads, hasLength(2));
      expect(result.threads.first.threadId, 1001);
      final uri = fixtureAdapter.requests.single.uri;
      expect(uri.queryParameters['module'], 'forumdisplay');
      expect(uri.queryParameters['fid'], '2');
      expect(uri.queryParameters['page'], '1');
    });

    test('getPosts requests viewthread and parses post result', () async {
      final fixtureAdapter = _FixtureAdapter({
        'viewthread': _fixture('viewthread_single_page.html'),
      });
      final dio = Dio()..httpClientAdapter = fixtureAdapter;
      final adapter = JavbusAdapter(dio: dio);

      final result = await adapter.getPosts(threadId: 1002, page: 1);

      expect(result.threadTitle, '普通主题');
      expect(result.posts, hasLength(2));
      final uri = fixtureAdapter.requests.single.uri;
      expect(uri.queryParameters['module'], 'viewthread');
      expect(uri.queryParameters['tid'], '1002');
      expect(
        fixtureAdapter.requests.single.headers['User-Agent'],
        contains('Mobile'),
      );
    });

    test(
      'throws CloudflareChallengeException when challenge page is returned',
      () async {
        final fixtureAdapter = _FixtureAdapter({
          'home': '<html><body>JavBus</body></html>',
          'forum_home': _fixture('cloudflare_challenge.html'),
        });
        final dio = Dio()..httpClientAdapter = fixtureAdapter;
        final adapter = JavbusAdapter(dio: dio);

        await expectLater(
          adapter.getForums(),
          throwsA(isA<CloudflareChallengeException>()),
        );
      },
    );

    test(
      'throws clear response error when age verification page is returned',
      () async {
        final fixtureAdapter = _FixtureAdapter({
          'home': '<html><body>JavBus</body></html>',
          'forum_home': _fixture('age_verification.html'),
        });
        final dio = Dio()..httpClientAdapter = fixtureAdapter;
        final adapter = JavbusAdapter(dio: dio);

        await expectLater(
          adapter.getForums(),
          throwsA(
            isA<ForumResponseException>().having(
              (error) => error.message,
              'message',
              contains('年龄确认'),
            ),
          ),
        );
      },
    );

    test(
      'retries one transient network failure before parsing response',
      () async {
        final fixtureAdapter = _FixtureAdapter({
          'home': '<html><body>JavBus</body></html>',
          'forum_home': _fixture('forumindex_desktop_full.html'),
        }, failFirstRequest: true);
        final dio = Dio()..httpClientAdapter = fixtureAdapter;
        final adapter = JavbusAdapter(dio: dio);

        final forums = await adapter.getForums();

        expect(forums, hasLength(9));
        expect(fixtureAdapter.requests, hasLength(3));
      },
    );
  });
}
