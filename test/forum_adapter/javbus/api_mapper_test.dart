import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/forum_adapter/javbus/api_mapper.dart';

void main() {
  group('JavBusApiMapper', () {
    const mapper = JavBusApiMapper();

    test('builds desktop entry URLs for anonymous forum index access', () {
      final siteHome = mapper.siteHome();
      final forumHome = mapper.forumHome();

      expect(siteHome.toString(), 'https://www.javbus.com/');
      expect(forumHome.toString(), 'https://www.javbus.com/forum/');
    });

    test('builds forum display mobile API URL with fid and page', () {
      final uri = mapper.forumDisplay(fid: 2, page: 3);

      expect(uri.toString(), contains('module=forumdisplay'));
      expect(uri.queryParameters['fid'], '2');
      expect(uri.queryParameters['page'], '3');
    });

    test('builds forum display mobile API URL with typeid filter', () {
      final uri = mapper.forumDisplay(fid: 2, filterTypeId: 8, page: 1);

      expect(uri.queryParameters['module'], 'forumdisplay');
      expect(uri.queryParameters['fid'], '2');
      expect(uri.queryParameters['filter'], 'typeid');
      expect(uri.queryParameters['typeid'], '8');
      expect(uri.queryParameters['page'], '1');
    });

    test('builds view thread mobile API URL with tid and page', () {
      final uri = mapper.viewThread(tid: 123, page: 2);

      expect(uri.toString(), contains('module=viewthread'));
      expect(uri.queryParameters['version'], '4');
      expect(uri.queryParameters['module'], 'viewthread');
      expect(uri.queryParameters['tid'], '123');
      expect(uri.queryParameters['page'], '2');
    });

    test('builds profile URL for future authenticated features', () {
      final uri = mapper.profile(uid: 99);

      expect(uri.path, '/forum/home.php');
      expect(uri.queryParameters['mod'], 'space');
      expect(uri.queryParameters['uid'], '99');
    });
  });
}
