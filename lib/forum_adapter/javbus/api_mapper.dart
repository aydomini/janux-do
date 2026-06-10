import '../adapter.dart';
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

  /// 桌面版版块列表 URL（包含完整浏览量和过滤参数 + 排序）
  Uri desktopForumDisplay({
    required int fid,
    int? filterTypeId,
    int page = 1,
    SortMode? sort,
  }) {
    final base = urlBuilder.baseUri.resolve('forum.php');
    return base.replace(queryParameters: {
      'mod': 'forumdisplay',
      'fid': '$fid',
      'page': '$page',
      if (filterTypeId != null) ...{
        'filter': 'typeid',
        'typeid': '$filterTypeId',
      } else ...switch (sort) {
        SortMode.latest => {'filter': 'lastpost', 'orderby': 'lastpost'},
        SortMode.hot => {'filter': 'heat', 'orderby': 'heats'},
        SortMode.trending => {'filter': 'hot'},
        SortMode.digest => {'filter': 'digest', 'digest': '1'},
        _ => <String, String>{},
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
  /// URL: forum.php?mod=misc&action=commentmore&tid={tid}&pid={pid}&page={page}&formhash=XXX
  Uri commentMore({required int tid, required int pid, int page = 1, String? formhash}) {
    final base = urlBuilder.baseUri.resolve('forum.php');
    return base.replace(queryParameters: {
      'mod': 'misc',
      'action': 'commentmore',
      'tid': '$tid',
      'pid': '$pid',
      'page': '$page',
      'inajax': '1',
      // ignore: use_null_aware_elements
      if (formhash != null) 'formhash': formhash,
    });
  }

  Uri profile({required int uid}) {
    final base = urlBuilder.baseUri.resolve('home.php');
    return base.replace(queryParameters: {'mod': 'space', 'uid': '$uid'});
  }

  /// 论坛帖子搜索（快速搜索，匿名可用）
  ///
  /// GET search.php?mod=forum&searchsubmit=yes&srchtxt={keyword}
  /// 首次搜索后 Discuz 分配 searchid，后续翻页使用 [searchForumPage]。
  Uri searchForum({required String keyword}) {
    final base = urlBuilder.baseUri.resolve('search.php');
    return base.replace(queryParameters: {
      'mod': 'forum',
      'searchsubmit': 'yes',
      'srchtxt': keyword,
    });
  }

  /// 搜索结果翻页
  ///
  /// 使用 Discuz 分配的 searchid + 排序参数翻页。
  Uri searchForumPage({
    required int searchId,
    required String keyword,
    int page = 1,
  }) {
    final base = urlBuilder.baseUri.resolve('search.php');
    return base.replace(queryParameters: {
      'mod': 'forum',
      'searchid': '$searchId',
      'orderby': 'lastpost',
      'ascdesc': 'desc',
      'searchsubmit': 'yes',
      'kw': keyword,
      'page': '$page',
    });
  }

  Uri _mobileApi(Map<String, String> queryParameters) {
    final base = urlBuilder.baseUri.resolve('api/mobile/index.php');
    return base.replace(queryParameters: {'version': '4', ...queryParameters});
  }
}
