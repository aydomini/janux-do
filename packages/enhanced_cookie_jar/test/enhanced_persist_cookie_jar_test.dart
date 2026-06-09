import 'dart:io';

import 'package:enhanced_cookie_jar/enhanced_cookie_jar.dart';
import 'package:test/test.dart';

void main() {
  group('EnhancedPersistCookieJar', () {
    late Directory tempDir;
    late EnhancedPersistCookieJar jar;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'enhanced_cookie_jar_test_',
      );
      jar = EnhancedPersistCookieJar(
        store: FileCookieStore(tempDir.path),
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('domain cookie matches subdomain requests', () async {
      await jar.saveFromSetCookieHeaders(
        Uri.parse('https://linux.do'),
        ['cf_clearance=abc; Domain=.linux.do; Path=/; Secure; HttpOnly'],
      );

      final cookies = await jar.loadForRequest(
        Uri.parse('https://connect.linux.do/oauth2/authorize'),
      );

      expect(cookies.map((e) => e.name), contains('cf_clearance'));
    });

    test('host-only cookie only matches exact host', () async {
      await jar.saveFromSetCookieHeaders(
        Uri.parse('https://connect.linux.do/oauth2/authorize'),
        ['auth.session-token=token123; Path=/; Secure; HttpOnly; SameSite=Lax'],
      );

      final exactHostCookies = await jar.loadForRequest(
        Uri.parse('https://connect.linux.do/discourse/sso_callback'),
      );
      final siblingHostCookies = await jar.loadForRequest(
        Uri.parse('https://cdk.linux.do/callback'),
      );

      expect(exactHostCookies.map((e) => e.name), contains('auth.session-token'));
      expect(
        siblingHostCookies.map((e) => e.name),
        isNot(contains('auth.session-token')),
      );
    });

    test('invalid cookie values are encoded when converted to io.Cookie', () async {
      await jar.saveCanonicalCookies(
        Uri.parse('https://linux.do'),
        [
          CanonicalCookie(
            name: 'g_state',
            value: '{"i_l":0,"i_ll":1774544311822}',
            domain: 'linux.do',
            path: '/',
            originUrl: 'https://linux.do',
            hostOnly: false,
          ),
        ],
      );

      final cookies = await jar.loadForRequest(Uri.parse('https://linux.do'));
      final gState = cookies.firstWhere((e) => e.name == 'g_state');

      expect(gState.value, startsWith('~enc~'));
    });

    // =========================================================================
    // storageKey 去重：同 (name, domain, path) 不同 hostOnly 不共存
    // =========================================================================

    group('storageKey 去重', () {
      test('A1.1: hostOnly=false → hostOnly=true 替换，不共存', () async {
        // 先存 domain cookie (hostOnly=false)
        await jar.saveCanonicalCookies(
          Uri.parse('https://linux.do'),
          [
            CanonicalCookie(
              name: '_t',
              value: 'old',
              domain: '.linux.do',
              path: '/',
              hostOnly: false,
              originUrl: 'https://linux.do',
            ),
          ],
        );

        // 再存 host-only cookie (hostOnly=true)
        await jar.saveCanonicalCookies(
          Uri.parse('https://linux.do'),
          [
            CanonicalCookie(
              name: '_t',
              value: 'new',
              domain: 'linux.do',
              path: '/',
              hostOnly: true,
              originUrl: 'https://linux.do',
            ),
          ],
        );

        final all = await jar.readAllCookies();
        final tCookies = all.where((c) => c.name == '_t').toList();
        expect(tCookies.length, 1, reason: '同名 cookie 只保留一份');
        expect(tCookies.first.value, 'new');
        expect(tCookies.first.hostOnly, true);
      });

      test('A1.2: hostOnly=true → hostOnly=false 替换', () async {
        await jar.saveCanonicalCookies(
          Uri.parse('https://linux.do'),
          [
            CanonicalCookie(
              name: '_t',
              value: 'host_only',
              domain: 'linux.do',
              path: '/',
              hostOnly: true,
              originUrl: 'https://linux.do',
            ),
          ],
        );

        await jar.saveCanonicalCookies(
          Uri.parse('https://linux.do'),
          [
            CanonicalCookie(
              name: '_t',
              value: 'domain',
              domain: '.linux.do',
              path: '/',
              hostOnly: false,
              originUrl: 'https://linux.do',
            ),
          ],
        );

        final all = await jar.readAllCookies();
        final tCookies = all.where((c) => c.name == '_t').toList();
        expect(tCookies.length, 1);
        expect(tCookies.first.value, 'domain');
        expect(tCookies.first.hostOnly, false);
      });

      test('A1.3: 不同 domain 不互相覆盖', () async {
        await jar.saveCanonicalCookies(
          Uri.parse('https://linux.do'),
          [
            CanonicalCookie(
              name: '_t',
              value: 'main',
              domain: 'linux.do',
              path: '/',
              hostOnly: true,
              originUrl: 'https://linux.do',
            ),
          ],
        );

        await jar.saveCanonicalCookies(
          Uri.parse('https://cdn.linux.do'),
          [
            CanonicalCookie(
              name: '_t',
              value: 'cdn',
              domain: 'cdn.linux.do',
              path: '/',
              hostOnly: true,
              originUrl: 'https://cdn.linux.do',
            ),
          ],
        );

        final all = await jar.readAllCookies();
        final tCookies = all.where((c) => c.name == '_t').toList();
        expect(tCookies.length, 2, reason: '不同域名各自独立');
      });

      test('A1.4: 不同 path 不互相覆盖', () async {
        await jar.saveCanonicalCookies(
          Uri.parse('https://linux.do'),
          [
            CanonicalCookie(
              name: 'sid',
              value: 'root',
              domain: 'linux.do',
              path: '/',
              originUrl: 'https://linux.do',
            ),
          ],
        );

        await jar.saveCanonicalCookies(
          Uri.parse('https://linux.do/forum'),
          [
            CanonicalCookie(
              name: 'sid',
              value: 'forum',
              domain: 'linux.do',
              path: '/forum',
              originUrl: 'https://linux.do/forum',
            ),
          ],
        );

        final all = await jar.readAllCookies();
        final sidCookies = all.where((c) => c.name == 'sid').toList();
        expect(sidCookies.length, 2);
      });

      test('A1.5: 不同 partitionKey 不互相覆盖（CHIPS）', () async {
        await jar.saveCanonicalCookies(
          Uri.parse('https://linux.do'),
          [
            CanonicalCookie(
              name: '_t',
              value: 'no_pk',
              domain: 'linux.do',
              path: '/',
              partitionKey: null,
              originUrl: 'https://linux.do',
            ),
          ],
        );

        await jar.saveCanonicalCookies(
          Uri.parse('https://linux.do'),
          [
            CanonicalCookie(
              name: '_t',
              value: 'with_pk',
              domain: 'linux.do',
              path: '/',
              partitionKey: 'https://other.com',
              originUrl: 'https://linux.do',
            ),
          ],
        );

        final all = await jar.readAllCookies();
        final tCookies = all.where((c) => c.name == '_t').toList();
        expect(tCookies.length, 2, reason: '不同 partitionKey 各自独立');
      });

      test('A1.6: 完全相同 storageKey 正常覆盖', () async {
        await jar.saveCanonicalCookies(
          Uri.parse('https://linux.do'),
          [
            CanonicalCookie(
              name: '_t',
              value: 'old',
              domain: 'linux.do',
              path: '/',
              hostOnly: true,
              originUrl: 'https://linux.do',
            ),
          ],
        );

        await jar.saveCanonicalCookies(
          Uri.parse('https://linux.do'),
          [
            CanonicalCookie(
              name: '_t',
              value: 'new',
              domain: 'linux.do',
              path: '/',
              hostOnly: true,
              originUrl: 'https://linux.do',
            ),
          ],
        );

        final all = await jar.readAllCookies();
        final tCookies = all.where((c) => c.name == '_t').toList();
        expect(tCookies.length, 1);
        expect(tCookies.first.value, 'new');
      });
    });

    // =========================================================================
    // domain 归一化
    // =========================================================================

    group('domain 归一化', () {
      test('A2.5: .linux.do 和 linux.do 视为同一域名', () async {
        await jar.saveCanonicalCookies(
          Uri.parse('https://linux.do'),
          [
            CanonicalCookie(
              name: '_t',
              value: 'with_dot',
              domain: '.linux.do',
              path: '/',
              hostOnly: false,
              originUrl: 'https://linux.do',
            ),
          ],
        );

        await jar.saveCanonicalCookies(
          Uri.parse('https://linux.do'),
          [
            CanonicalCookie(
              name: '_t',
              value: 'without_dot',
              domain: 'linux.do',
              path: '/',
              hostOnly: true,
              originUrl: 'https://linux.do',
            ),
          ],
        );

        final all = await jar.readAllCookies();
        final tCookies = all.where((c) => c.name == '_t').toList();
        expect(tCookies.length, 1, reason: '归一化后是同一个 storageKey');
        expect(tCookies.first.value, 'without_dot');
      });
    });

    // =========================================================================
    // saveFromResponse: io.Cookie → CanonicalCookie hostOnly 解析
    // =========================================================================

    group('saveFromResponse hostOnly 解析', () {
      test('A4.1: domain=null → hostOnly=true', () async {
        final cookie = Cookie('_t', 'token')..path = '/';
        await jar.saveFromResponse(Uri.parse('https://linux.do'), [cookie]);

        final all = await jar.readAllCookies();
        final t = all.firstWhere((c) => c.name == '_t');
        expect(t.hostOnly, true);
      });

      test('A4.2: domain=".linux.do" → hostOnly=false', () async {
        final cookie = Cookie('_t', 'token')
          ..domain = '.linux.do'
          ..path = '/';
        await jar.saveFromResponse(Uri.parse('https://linux.do'), [cookie]);

        final all = await jar.readAllCookies();
        final t = all.firstWhere((c) => c.name == '_t');
        expect(t.hostOnly, false);
      });

      test('A4.3: domain="linux.do" → hostOnly=false', () async {
        final cookie = Cookie('_t', 'token')
          ..domain = 'linux.do'
          ..path = '/';
        await jar.saveFromResponse(Uri.parse('https://linux.do'), [cookie]);

        final all = await jar.readAllCookies();
        final t = all.firstWhere((c) => c.name == '_t');
        expect(t.hostOnly, false);
      });

      test('A4.4: domain="" → hostOnly=true', () async {
        final cookie = Cookie('_t', 'token')
          ..domain = ''
          ..path = '/';
        await jar.saveFromResponse(Uri.parse('https://linux.do'), [cookie]);

        final all = await jar.readAllCookies();
        final t = all.firstWhere((c) => c.name == '_t');
        expect(t.hostOnly, true);
      });
    });

    // =========================================================================
    // loadForRequest 匹配
    // =========================================================================

    group('loadForRequest 匹配', () {
      test('A3.1: host-only cookie 不匹配子域名', () async {
        await jar.saveFromSetCookieHeaders(
          Uri.parse('https://linux.do'),
          ['_t=token; Path=/; Secure; HttpOnly'],
        );

        final cookies = await jar.loadForRequest(
          Uri.parse('https://cdn.linux.do/image.png'),
        );
        expect(cookies.map((e) => e.name), isNot(contains('_t')));
      });

      test('A3.3: host-only cookie 精确匹配主域名', () async {
        await jar.saveFromSetCookieHeaders(
          Uri.parse('https://linux.do'),
          ['_t=token; Path=/; Secure; HttpOnly'],
        );

        final cookies = await jar.loadForRequest(
          Uri.parse('https://linux.do/latest.json'),
        );
        expect(cookies.map((e) => e.name), contains('_t'));
      });

      test('A3.4: 过期 cookie 不返回', () async {
        final pastDate = DateTime.now().subtract(const Duration(days: 1));
        await jar.saveCanonicalCookies(
          Uri.parse('https://linux.do'),
          [
            CanonicalCookie(
              name: 'expired',
              value: 'old',
              domain: 'linux.do',
              path: '/',
              expiresAt: pastDate,
              originUrl: 'https://linux.do',
            ),
          ],
        );

        final cookies = await jar.loadForRequest(
          Uri.parse('https://linux.do'),
        );
        expect(cookies.map((e) => e.name), isNot(contains('expired')));
      });
    });

    // =========================================================================
    // 持久化
    // =========================================================================

    group('持久化', () {
      test('A5.1: session cookie 不持久化', () async {
        // 无 expires 的 cookie 是 session cookie
        await jar.saveCanonicalCookies(
          Uri.parse('https://linux.do'),
          [
            CanonicalCookie(
              name: 'session',
              value: 'temp',
              domain: 'linux.do',
              path: '/',
              originUrl: 'https://linux.do',
            ),
          ],
        );

        // 创建新 jar 实例（模拟重启），共享同一磁盘路径
        final jar2 = EnhancedPersistCookieJar(
          store: FileCookieStore(tempDir.path),
        );
        final all = await jar2.readAllCookies();
        expect(all.where((c) => c.name == 'session'), isEmpty,
            reason: 'session cookie 不应持久化到磁盘');
      });

      test('A5.2: persistent cookie 持久化', () async {
        await jar.saveCanonicalCookies(
          Uri.parse('https://linux.do'),
          [
            CanonicalCookie(
              name: 'persist',
              value: 'keep',
              domain: 'linux.do',
              path: '/',
              expiresAt: DateTime.now().add(const Duration(days: 30)),
              originUrl: 'https://linux.do',
            ),
          ],
        );

        final jar2 = EnhancedPersistCookieJar(
          store: FileCookieStore(tempDir.path),
        );
        final all = await jar2.readAllCookies();
        expect(all.any((c) => c.name == 'persist' && c.value == 'keep'), true);
      });

      test('A5.3: 文件损坏容错', () async {
        // 写入一个合法 cookie
        await jar.saveCanonicalCookies(
          Uri.parse('https://linux.do'),
          [
            CanonicalCookie(
              name: 'test',
              value: 'ok',
              domain: 'linux.do',
              path: '/',
              expiresAt: DateTime.now().add(const Duration(days: 1)),
              originUrl: 'https://linux.do',
            ),
          ],
        );

        // 手动损坏文件
        final cookieFile = File('${tempDir.path}/cookies.v1.json');
        if (await cookieFile.exists()) {
          await cookieFile.writeAsString('CORRUPTED{{{');
        }

        // 新实例应优雅处理
        final jar2 = EnhancedPersistCookieJar(
          store: FileCookieStore(tempDir.path),
        );
        final all = await jar2.readAllCookies();
        expect(all, isEmpty, reason: '损坏文件返回空列表，不崩溃');
      });
    });

    // =========================================================================
    // 原有测试
    // =========================================================================

    test('redirect oauth cookie stays available for same host', () async {
      await jar.saveFromSetCookieHeaders(
        Uri.parse(
          'https://connect.linux.do/oauth2/authorize?client_id=test',
        ),
        [
          'auth.session-token=oauth-token; Path=/; Secure; HttpOnly; SameSite=Lax',
        ],
      );

      final cookies = await jar.loadForRequest(
        Uri.parse('https://connect.linux.do/oauth2/approve/test'),
      );

      expect(
        cookies.any(
          (cookie) =>
              cookie.name == 'auth.session-token' &&
              cookie.value == 'oauth-token',
        ),
        isTrue,
      );
    });
    test('saveFromResponse domain cookie → loadForRequest 能读到', () async {
      final cookie = Cookie('_t', 'token123')
        ..domain = '.linux.do'
        ..path = '/'
        ..secure = false
        ..httpOnly = false;

      await jar.saveFromResponse(Uri.parse('https://linux.do'), [cookie]);

      final all = await jar.readAllCookies();
      print('All cookies: ${all.map((c) => "name=${c.name}, domain=${c.domain}, normalized=${c.normalizedDomain}, hostOnly=${c.hostOnly}").join("; ")}');

      final loaded = await jar.loadForRequest(Uri.parse('https://linux.do'));
      print('Loaded: ${loaded.map((c) => "name=${c.name}, domain=${c.domain}").join("; ")}');

      expect(loaded.any((c) => c.name == '_t'), true, reason: '_t should be loadable');
    });
  });
}
