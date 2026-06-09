import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../../../forum_adapter/exceptions.dart';
import '../../../forum_adapter/models/forum_results.dart';
import '../../../forum_adapter/models/forum_thread.dart';
import '../utils/time_parser.dart';
import '../utils/url_builder.dart';

class ForumDisplayParser {
  ForumDisplayParser({
    this.urlBuilder = const JavBusUrlBuilder(),
    DiscuzTimeParser? timeParser,
  }) : timeParser = timeParser ?? DiscuzTimeParser();

  final JavBusUrlBuilder urlBuilder;
  final DiscuzTimeParser timeParser;

  ThreadListResult parse(
    String html, {
    required int forumId,
    String? requestUrl,
  }) {
    final document = html_parser.parse(html);
    final threads = <ForumThread>[];
    final seenThreadIds = <int>{};

    for (final anchor in document.querySelectorAll('a[href]')) {
      final href = anchor.attributes['href'] ?? '';
      final threadId = _extractQueryInt(href, 'tid');
      if (_isThreadIcon(anchor)) continue;
      if (threadId == null || !seenThreadIds.add(threadId)) continue;

      final container = _nearestThreadContainer(anchor);
      final text = container?.text.trim() ?? anchor.text.trim();
      final stats = _extractStats(text);
      final author = _extractAuthor(container);
      final createdAtText = _extractTimeText(container, text);
      final createdAt = timeParser.parse(createdAtText) ?? DateTime.now();
      threads.add(
        ForumThread(
          threadId: threadId,
          forumId: forumId,
          title: anchor.text.trim(),
          author: author.name,
          authorId: author.id,
          replies: stats.replies,
          views: stats.views,
          createdAt: createdAt,
          isPinned: _isPinned(container),
          url: urlBuilder.resolve(href),
        ),
      );
    }

    if (threads.isEmpty && !_isKnownEmptyPage(document)) {
      throw ForumParseException(
        '未找到 Discuz 主题链接',
        parserName: 'ForumDisplayParser',
        requestUrl: requestUrl,
        responseSnippet: _snippet(html),
      );
    }

    final pagination = _extractPagination(document);
    return ThreadListResult(
      threads: threads,
      currentPage: pagination.currentPage,
      totalPages: pagination.totalPages,
      hasNextPage: pagination.hasNextPage,
    );
  }

  static Element? _nearestThreadContainer(Element element) {
    Element? current = element.parent;
    while (current != null && current.localName != 'body') {
      final text = current.text;
      if (current.classes.contains('bm_c') ||
          text.contains('回复') ||
          text.contains('回') ||
          current.classes.contains('thread')) {
        return current;
      }
      current = current.parent;
    }
    return element.parent;
  }

  static String? _textOf(Element? element, String selector) {
    final text = element?.querySelector(selector)?.text.trim();
    return text == null || text.isEmpty ? null : text;
  }

  static String _extractTimeText(Element? container, String fallbackText) {
    final explicit =
        _textOf(container, '.time') ??
        _textOf(container, '.xg1') ??
        _textOf(container, '.by') ??
        _textOf(container, 'cite') ??
        '';
    final source = explicit.isNotEmpty ? explicit : fallbackText;
    return source
        .replaceAll(RegExp(r'回\s*\d+'), '')
        .replaceAll(RegExp(r'回复\s*\d+\s*/\s*查看\s*\d+'), '')
        .trim();
  }

  static bool _isPinned(Element? element) {
    if (element == null) return false;
    return element.classes.contains('pinned') ||
        element.text.contains('置顶') ||
        element.text.contains('置頂') ||
        element.querySelector('img[src*="pin_"]') != null;
  }

  /// 从桌面版 HTML 解析浏览量（tid → views）
  static Map<int, int> parseThreadViews(String html) {
    final document = html_parser.parse(html);
    final results = <int, int>{};
    for (final row in document.querySelectorAll('[id^="normalthread_"]')) {
      final rawId = row.id;
      final tid = int.tryParse(rawId.replaceFirst('normalthread_', ''));
      if (tid == null) continue;
      final viewsElement = row.querySelector('.views');
      final viewsText = viewsElement?.text.trim() ?? '';
      final views = int.tryParse(viewsText);
      if (views != null) results[tid] = views;
    }
    return results;
  }
}

typedef _Stats = ({int replies, int views});
typedef _Author = ({String name, int? id});
typedef _Pagination = ({int currentPage, int totalPages, bool hasNextPage});

_Stats _extractStats(String text) {
  final labeledPairMatch = RegExp(
    r'回复\s*(\d+)\s*/\s*查看\s*(\d+)',
  ).firstMatch(text);
  if (labeledPairMatch != null) {
    return (
      replies: int.parse(labeledPairMatch.group(1)!),
      views: int.parse(labeledPairMatch.group(2)!),
    );
  }
  final mobileReplyMatch = RegExp(
    r'(?:^|\s)回\s*(\d+)|(?:^|\s)回(\d+)',
  ).firstMatch(text);
  return (
    replies: mobileReplyMatch == null
        ? 0
        : int.parse(mobileReplyMatch.group(1) ?? mobileReplyMatch.group(2)!),
    views: 0,
  );
}

_Author _extractAuthor(Element? container) {
  final authorElement =
      container?.querySelector('.author') ??
      container?.querySelector('.xg1 a[href*="uid="]') ??
      container?.querySelector('a[href*="home.php?mod=space"]');
  final name = authorElement?.text.trim() ?? '';
  final id = _extractQueryInt(authorElement?.attributes['href'] ?? '', 'uid');
  return (name: name, id: id);
}

bool _isThreadIcon(Element anchor) {
  return anchor.text.trim().isEmpty ||
      anchor.querySelector('img') != null && anchor.text.trim().isEmpty;
}

_Pagination _extractPagination(Document document) {
  final current =
      int.tryParse(document.querySelector('.pg strong')?.text.trim() ?? '') ??
      1;
  var total = current;
  for (final link in document.querySelectorAll('.pg a')) {
    final page = int.tryParse(link.text.trim());
    if (page != null && page > total) total = page;
  }
  return (
    currentPage: current,
    totalPages: total,
    hasNextPage: document.querySelector('.pg .nxt') != null,
  );
}

int? _extractQueryInt(String href, String key) {
  final uri = Uri.tryParse(href.replaceAll('&amp;', '&'));
  final value =
      uri?.queryParameters[key] ??
      RegExp('(?:[?&]|&amp;)$key=(\\d+)').firstMatch(href)?.group(1);
  return value == null ? null : int.tryParse(value);
}

  /// 从桌面版 HTML 解析浏览量（tid → views）
  static Map<int, int> parseThreadViews(String html) {
    final document = html_parser.parse(html);
    final results = <int, int>{};
    for (final row in document.querySelectorAll('[id^="normalthread_"]')) {
      final rawId = row.id;
      final tid = int.tryParse(rawId.replaceFirst('normalthread_', ''));
      if (tid == null) continue;
      final viewsElement = row.querySelector('.views');
      final viewsText = viewsElement?.text.trim() ?? '';
      final views = int.tryParse(viewsText);
      if (views != null) results[tid] = views;
    }
    return results;
  }
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
