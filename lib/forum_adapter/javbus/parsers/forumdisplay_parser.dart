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

    // 桌面版：从 normalthread_ / stickthread_ 容器内取 tid 链接
    // 移动版：容器无这些 ID，回退
    var anchors = document.querySelectorAll('[id*="thread_"] a[href*="tid="]');
    if (anchors.isEmpty) {
      anchors = document.querySelectorAll('.thread a[href*="tid="]');
    }
    if (anchors.isEmpty) {
      anchors = document.querySelectorAll('a[href]');
    }
    for (final anchor in anchors) {
      final href = anchor.attributes['href'] ?? '';
      final threadId = _extractQueryInt(href, 'tid');
      if (_isThreadIcon(anchor)) continue;
      if (threadId == null || !seenThreadIds.add(threadId)) continue;

      final container = _closestNormalthread(anchor) ?? _nearestThreadContainer(anchor);
      final text = container?.text.trim() ?? anchor.text.trim();
      final stats = _extractStatsFromContainer(container);
      final author = _extractAuthor(container);
      final createdAtText = _extractTimeText(container, text);
      final createdAt = timeParser.parse(createdAtText) ?? DateTime.now();
      final lastReplyAt = _extractLastReplyTime(container);
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
          lastReplyAt: lastReplyAt,
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

  /// 向上查找 normalthread_ / stickthread_ 祖先元素（真实桌面版 HTML）
  static Element? _closestNormalthread(Element element) {
    Element? current = element;
    while (current != null && current.localName != 'body') {
      final id = current.attributes['id'] ?? '';
      if (id.startsWith('normalthread_') || id.startsWith('stickthread_')) {
        return current;
      }
      current = current.parent;
    }
    return null;
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
        _textOf(container, '.dateline') ??
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

  /// 从 span.time.y 中提取最后回复时间
  ///
  /// 真实 Discuz HTML 格式: <span class="time y">miaoeng @ 3 分钟前</span>
  /// 取 @ 后的时间字符串，交由 [timeParser] 解析。
  DateTime? _extractLastReplyTime(Element? container) {
    if (container == null) return null;

    // 桌面版 JavBus 模板：span.time.y
    final timeYEl = container.querySelector('span.time.y');
    if (timeYEl != null) {
      final raw = timeYEl.text.trim();
      final atIndex = raw.lastIndexOf('@');
      if (atIndex >= 0 && atIndex + 1 < raw.length) {
        final timePart = raw.substring(atIndex + 1).trim();
        if (timePart.isNotEmpty) {
          return timeParser.parse(timePart);
        }
      }
    }

    return null;
  }

  static bool _isPinned(Element? element) {
    if (element == null) return false;
    final id = element.attributes['id'] ?? '';
    return id.startsWith('stickthread_') ||
        element.classes.contains('pinned') ||
        element.text.contains('置顶') ||
        element.text.contains('置頂') ||
        element.querySelector('img[src*="pin_"]') != null;
  }

  /// 从桌面版 HTML 解析浏览量（tid → views）
  /// 同时支持 .thread/.stats 格式和 normalthread_XXX/.views 格式
  static Map<int, int> parseThreadViews(String html) {
    final document = html_parser.parse(html);
    final results = <int, int>{};
    for (final row in document.querySelectorAll('.thread, [id^="normalthread_"]')) {
      final rawId = row.attributes['id'];
      final int? tid;
      if (rawId != null && rawId.startsWith('normalthread_')) {
        // 标准 Discuz 格式：id="normalthread_12345"
        tid = int.tryParse(rawId.replaceFirst('normalthread_', ''));
      } else {
        // JavBus 格式：.thread 内 a[href*="tid="]
        final link = row.querySelector('a[href*="tid="]');
        tid = link == null
            ? null
            : _extractQueryInt(link.attributes['href'] ?? '', 'tid');
      }
      if (tid == null) continue;
      // 从 .views 或 .stats 中提取浏览量
      final viewsElement =
          row.querySelector('.views') ?? row.querySelector('.stats');
      if (viewsElement != null) {
        final viewsText = viewsElement.text.trim();
        // "回复 2 / 查看 30" → 提取查看数量
        final viewsMatch = RegExp(r'查看\s*(\d+)').firstMatch(viewsText);
        final views = viewsMatch != null
            ? int.tryParse(viewsMatch.group(1)!)
            : int.tryParse(viewsText);
        if (views != null) results[tid] = views;
      }
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

/// 从桌面版 .nums 容器解析回复和浏览量
/// <span class="views">62930</span><span class="reply">61</span>
_Stats _extractStatsFromContainer(Element? container) {
  if (container == null) return (replies: 0, views: 0);
  final viewsEl = container.querySelector('.views');
  final replyEl = container.querySelector('.reply');
  final views = viewsEl != null ? int.tryParse(viewsEl.text.trim()) ?? 0 : 0;
  final replies = replyEl != null ? int.tryParse(replyEl.text.trim()) ?? 0 : 0;
  if (views > 0 || replies > 0) return (replies: replies, views: views);
  // 回退到文本解析
  return _extractStats(container.text);
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

bool _isKnownEmptyPage(Document document) {
  final text = document.body?.text ?? document.text ?? '';
  return text.contains('暂无') || text.contains('没有权限') || text.contains('抱歉');
}

String _snippet(String text, {int maxLength = 300}) {
  final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.length <= maxLength) return normalized;
  return normalized.substring(0, maxLength);
}
