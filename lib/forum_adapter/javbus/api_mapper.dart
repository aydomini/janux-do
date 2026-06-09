import 'utils/url_builder.dart';

class JavBusApiMapper {
  const JavBusApiMapper({this.urlBuilder = const JavBusUrlBuilder()});

  final JavBusUrlBuilder urlBuilder;

  Uri siteHome() {
    return urlBuilder.baseUri.resolve('/');
  }

  Uri forumHome() {
    return urlBuilder.baseUri.resolve('./');
  }

  Uri forumDisplay({required int fid, int? filterTypeId, int page = 1}) {
    final queryParameters = {
      'module': 'forumdisplay',
      'fid': '$fid',
      'page': '$page',
      if (filterTypeId != null) ...{
        'filter': 'typeid',
        'typeid': '$filterTypeId',
      },
    };
    return _mobileApi(queryParameters);
  }

  Uri viewThread({required int tid, int page = 1}) {
    return _mobileApi({'module': 'viewthread', 'tid': '$tid', 'page': '$page'});
  }

  /// 桌面版版块列表 URL（包含完整浏览量和过滤参数）
  Uri desktopForumDisplay({required int fid, int? filterTypeId, int page = 1}) {
    final base = urlBuilder.baseUri.resolve('forum.php');
    return base.replace(queryParameters: {
      'mod': 'forumdisplay',
      'fid': '$fid',
      'page': '$page',
      if (filterTypeId != null) ...{
        'filter': 'typeid',
        'typeid': '$filterTypeId',
      },
    });
  }

  /// 桌面版帖子详情 URL（用于解析楼中楼点评）
  Uri desktopViewThread({required int tid, int page = 1}) {
    final base = urlBuilder.baseUri.resolve('forum.php');
    return base.replace(queryParameters: {
      'mod': 'viewthread',
      'tid': '$tid',
      'page': '$page',
    });
  }

  /// 点评分页 AJAX 接口（第 2 页及以后）
  /// URL: forum.php?mod=misc&action=commentmore&tid={tid}&pid={pid}&page={page}
  Uri commentMore({required int tid, required int pid, int page = 1}) {
    final base = urlBuilder.baseUri.resolve('forum.php');
    return base.replace(queryParameters: {
      'mod': 'misc',
      'action': 'commentmore',
      'tid': '$tid',
      'pid': '$pid',
      'page': '$page',
    });
  }

  Uri profile({required int uid}) {
    final base = urlBuilder.baseUri.resolve('home.php');
    return base.replace(queryParameters: {'mod': 'space', 'uid': '$uid'});
  }

  Uri _mobileApi(Map<String, String> queryParameters) {
    final base = urlBuilder.baseUri.resolve('api/mobile/index.php');
    return base.replace(queryParameters: {'version': '4', ...queryParameters});
  }
}
