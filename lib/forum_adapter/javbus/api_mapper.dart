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

  Uri profile({required int uid}) {
    final base = urlBuilder.baseUri.resolve('home.php');
    return base.replace(queryParameters: {'mod': 'space', 'uid': '$uid'});
  }

  Uri _mobileApi(Map<String, String> queryParameters) {
    final base = urlBuilder.baseUri.resolve('api/mobile/index.php');
    return base.replace(queryParameters: {'version': '4', ...queryParameters});
  }
}
