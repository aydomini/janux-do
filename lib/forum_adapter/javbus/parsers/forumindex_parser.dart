import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../../../forum_adapter/exceptions.dart';
import '../../../forum_adapter/models/forum_forum.dart';
import '../utils/url_builder.dart';

class ForumIndexParser {
  const ForumIndexParser({this.urlBuilder = const JavBusUrlBuilder()});

  final JavBusUrlBuilder urlBuilder;

  List<ForumForum> parse(String html, {String? requestUrl}) {
    final document = html_parser.parse(html);
    final forums = <ForumForum>[];
    final seenForumKeys = <String>{};

    for (final anchor in document.querySelectorAll('a[href]')) {
      final href = anchor.attributes['href'] ?? '';
      final name = anchor.text.trim();
      if (name.isEmpty || !href.contains('forumdisplay')) continue;
      final forumId = _extractQueryInt(href, 'fid');
      if (forumId == null) continue;
      final filterTypeId = _extractFilterTypeId(href);
      final forumKey = '$forumId:${filterTypeId ?? ''}';
      if (!seenForumKeys.add(forumKey)) continue;

      final container = _nearestContainer(anchor);
      final text = container?.text.trim() ?? anchor.text.trim();
      forums.add(
        ForumForum(
          forumId: forumId,
          name: name,
          description: _extractDescription(container, name),
          filterTypeId: filterTypeId,
          threadCount: _extractThreadCount(container, text),
          todayPostCount: _extractTodayPostCount(container, text),
          url: urlBuilder.resolve(href),
        ),
      );
    }

    if (forums.isEmpty && !_isKnownEmptyPage(document)) {
      throw ForumParseException(
        '未找到 Discuz 版块链接',
        parserName: 'ForumIndexParser',
        requestUrl: requestUrl,
        responseSnippet: _snippet(html),
      );
    }
    return forums;
  }

  static Element? _nearestContainer(Element element) {
    Element? current = element.parent;
    Element? fallback;
    while (current != null && current.localName != 'body') {
      if (current.localName == 'tr') {
        return current;
      }
      if (fallback == null &&
          (current.querySelector('p') != null ||
              current.querySelector('.xg2') != null ||
              current.querySelector('.fl_i') != null ||
              current.querySelectorAll('a[href]').length <= 1)) {
        fallback = current;
      }
      current = current.parent;
    }
    return fallback ?? element.parent;
  }

  static String? _extractDescription(Element? container, String title) {
    if (container == null) return null;
    final paragraph =
        container.querySelector('.xg2')?.text.trim() ??
        container.querySelector('p')?.text.trim();
    if (paragraph != null && paragraph.isNotEmpty) return paragraph;
    final text = container.text.replaceFirst(title, '').trim();
    return text.isEmpty ? null : text;
  }
}

int? _extractFilterTypeId(String href) {
  final filter = _extractQueryString(href, 'filter');
  final typeId = _extractQueryInt(href, 'typeid');
  return filter == 'typeid' ? typeId : null;
}

String? _extractQueryString(String href, String key) {
  final normalized = href.replaceAll('&amp;', '&');
  final uri = Uri.tryParse(normalized);
  return uri?.queryParameters[key] ??
      RegExp('(?:[?&]|&amp;)$key=([^&#]+)').firstMatch(href)?.group(1);
}

int? _extractQueryInt(String href, String key) {
  final value = _extractQueryString(href, key);
  return value == null ? null : int.tryParse(value);
}

int _extractThreadCount(Element? container, String text) {
  final titledCount = container
      ?.querySelector('.fl_i .xi2 span[title]')
      ?.attributes['title'];
  final titledValue = _parseCount(titledCount);
  if (titledValue != null) return titledValue;

  final desktopText = container?.querySelector('.fl_i .xi2')?.text.trim();
  final desktopValue = _parseCount(desktopText);
  if (desktopValue != null) return desktopValue;

  return _extractLabeledCount(text, '主题');
}

int _extractTodayPostCount(Element? container, String text) {
  final todayText = container?.querySelector('em[title="今日"]')?.text.trim();
  final todayValue = _parseCount(todayText);
  if (todayValue != null) return todayValue;

  return _extractLabeledCount(text, '今日');
}

int _extractLabeledCount(String text, String label) {
  final match = RegExp('$label\\s*[:：]\\s*(\\d+)').firstMatch(text);
  return match == null ? 0 : int.parse(match.group(1)!);
}

int? _parseCount(String? raw) {
  if (raw == null) return null;
  final normalized = raw
      .replaceAll(',', '')
      .replaceAll('(', '')
      .replaceAll(')', '')
      .trim();
  if (normalized.isEmpty) return null;
  final plainDigits = RegExp(r'\d+').firstMatch(normalized)?.group(0);
  if (plainDigits == null) return null;
  final value = int.parse(plainDigits);
  if (normalized.contains('萬') || normalized.contains('万')) {
    return value * 10000;
  }
  return value;
}

bool _isKnownEmptyPage(Document document) {
  final text = document.body?.text ?? document.text ?? '';
  return text.contains('暂无') || text.contains('没有权限') || text.contains('抱歉');
}

String _snippet(String text, {int maxLength = 300}) {
  final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.length <= maxLength) return normalized;
  return normalized.substring(0, maxLength);
}
