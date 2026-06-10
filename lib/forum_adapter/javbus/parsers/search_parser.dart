import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../../../forum_adapter/exceptions.dart';
import '../../../forum_adapter/models/forum_results.dart';
import '../../../forum_adapter/models/forum_thread.dart';
import '../utils/time_parser.dart';
import '../utils/url_builder.dart';

/// Discuz 论坛搜索结果解析器
///
/// 解析 search.php?mod=forum 返回的 HTML，提取搜索结果列表与分页。
/// 搜索结果使用 `<li class="pbw">` 结构，与 forumdisplay 的
/// `<div class="thread">` 不同。
class SearchParser {
  SearchParser({
    this.urlBuilder = const JavBusUrlBuilder(),
    DiscuzTimeParser? timeParser,
  }) : timeParser = timeParser ?? DiscuzTimeParser();

  final JavBusUrlBuilder urlBuilder;
  final DiscuzTimeParser timeParser;

  /// 解析搜索结果 HTML
  ///
  /// 返回 [SearchResult] 包含帖子列表、分页信息和搜索统计。
  SearchResult parse(String html, {String? requestUrl}) {
    final document = html_parser.parse(html);
    final threads = <ForumThread>[];
    final seenThreadIds = <int>{};

    for (final item in document.querySelectorAll('li.pbw')) {
      final thread = _parseThreadItem(item);
      if (thread == null) continue;
      if (!seenThreadIds.add(thread.threadId)) continue;
      threads.add(thread);
    }

    if (threads.isEmpty && !_isKnownEmptyPage(document)) {
      final statsText = document.querySelector('.sttl h2 em')?.text.trim();
      // 如果统计信息显示 0 条结果，是正常的空结果
      if (statsText == null || !statsText.contains('0 個')) {
        throw ForumParseException(
          '未找到搜索结果条目',
          parserName: 'SearchParser',
          requestUrl: requestUrl,
          responseSnippet: _snippet(html),
        );
      }
    }

    final pagination = _extractPagination(document);
    final stats = _extractSearchStats(document);
    final searchId = _extractSearchId(document);

    return SearchResult(
      threads: threads,
      currentPage: pagination.currentPage,
      totalPages: pagination.totalPages,
      hasNextPage: pagination.hasNextPage,
      totalResults: stats.total,
      matchedKeyword: stats.keyword,
      searchId: searchId,
    );
  }

  /// 解析单个搜索结果 `<li class="pbw" id="{tid}">`
  ForumThread? _parseThreadItem(Element item) {
    final rawId = item.attributes['id'];
    final threadId = rawId == null ? null : int.tryParse(rawId);
    if (threadId == null) return null;

    // 标题：h3.xs3 中的第一个链接
    final titleAnchor = item.querySelector('h3.xs3 a');
    if (titleAnchor == null) return null;
    final href = titleAnchor.attributes['href'] ?? '';
    // 标题会包含高亮标记 <strong><font color="red">，取纯文本
    final title = titleAnchor.text.trim();
    if (title.isEmpty) return null;

    // 回复/查看统计：p.xg1 → "N 個回復 - N 次查看"
    final statsText = item.querySelector('p.xg1')?.text.trim() ?? '';
    final stats = _parseStatsLine(statsText);

    // 摘要：p.xg1 之后的 <p>（无 class），排除最后一个 <p>（元信息行）
    final allParagraphs = item.querySelectorAll('p');
    String? excerpt;
    if (allParagraphs.length >= 3) {
      // p[0] = xg1 (stats), p[1..n-1] = excerpt, p[last] = meta
      for (var i = 1; i < allParagraphs.length - 1; i++) {
        final candidate = allParagraphs[i];
        // 跳过 stats 行和空段落
        if (candidate.classes.contains('xg1')) continue;
        final text = candidate.text.trim();
        if (text.isNotEmpty) {
          excerpt = text;
          break;
        }
      }
    }

    // 元信息行：最后一个 <p> → 时间、作者、所属版块
    final metaParagraph = allParagraphs.isNotEmpty ? allParagraphs.last : null;
    final createdAt = _extractTime(metaParagraph);
    final author = _extractAuthor(metaParagraph);
    final (forumId, forumName) = _extractForum(metaParagraph);

    return ForumThread(
      threadId: threadId,
      forumId: forumId,
      title: title,
      author: author.name,
      authorId: author.id,
      replies: stats.replies,
      views: stats.views,
      createdAt: createdAt,
      forumName: forumName,
      excerpt: excerpt,
      url: urlBuilder.resolve(href),
    );
  }

  /// 解析 "N 個回復 - N 次查看"
  static ({int replies, int views}) _parseStatsLine(String text) {
    // "26 個回復 - 15036 次查看"
    final replyMatch = RegExp(r'(\d+)\s*個回復').firstMatch(text);
    final viewMatch = RegExp(r'(\d+)\s*次查看').firstMatch(text);
    return (
      replies: replyMatch == null ? 0 : int.parse(replyMatch.group(1)!),
      views: viewMatch == null ? 0 : int.parse(viewMatch.group(1)!),
    );
  }

  /// 从元信息段落提取发布时间
  ///
  /// 元信息 `<p>` 的第一个 `<span>` 是时间文本，如 "2026-5-2 10:56"
  DateTime? _extractTime(Element? meta) {
    if (meta == null) return null;
    final spans = meta.querySelectorAll('span');
    if (spans.isEmpty) return null;
    // 第一个 span 中的纯文本就是时间
    final timeText = spans.first.text.trim();
    // 去掉可能跟在时间后面的 " - " 等分隔符
    final cleaned = timeText.replaceAll(RegExp(r'\s*[-]\s*$'), '').trim();
    if (cleaned.isEmpty) return null;
    return timeParser.parse(cleaned);
  }

  /// 从元信息段落提取作者
  ///
  /// 作者链接：`<a href="home.php?mod=space&uid=X">`
  _Author _extractAuthor(Element? meta) {
    if (meta == null) return (name: '', id: null);
    final authorLink = meta.querySelector('a[href*="mod=space"]');
    if (authorLink == null) return (name: '', id: null);
    final name = authorLink.text.trim();
    final id = _extractQueryInt(
      authorLink.attributes['href'] ?? '',
      'uid',
    );
    return (name: name, id: id);
  }

  /// 从元信息段落提取所属版块
  ///
  /// 版块链接：`<a href="forum.php?mod=forumdisplay&fid=36" class="xi1">`
  (int forumId, String? forumName) _extractForum(Element? meta) {
    if (meta == null) return (0, null);
    final forumLink = meta.querySelector('a[href*="forumdisplay"]');
    if (forumLink == null) return (0, null);
    final name = forumLink.text.trim();
    final id = _extractQueryInt(
      forumLink.attributes['href'] ?? '',
      'fid',
    );
    return (id ?? 0, name.isEmpty ? null : name);
  }
}

typedef _Author = ({String name, int? id});
typedef _Pagination = ({int currentPage, int totalPages, bool hasNextPage});

/// 搜索结果统计
typedef _SearchStats = ({int total, String? keyword});

_SearchStats _extractSearchStats(Document document) {
  // "找到 「SSIS」 相關內容 60 個"
  final emText = document.querySelector('.sttl h2 em')?.text.trim() ?? '';
  final totalMatch = RegExp(r'(\d+)\s*個').firstMatch(emText);
  final total = totalMatch == null ? 0 : int.parse(totalMatch.group(1)!);
  // "「SSIS」" 中间的关键词
  final kwMatch = RegExp(r'「([^」]+)」').firstMatch(emText);
  return (total: total, keyword: kwMatch?.group(1));
}

/// 从分页链接中提取 Discuz 分配的 searchid
int? _extractSearchId(Document document) {
  final pageLink = document.querySelector('.pg a');
  if (pageLink == null) return null;
  final href = pageLink.attributes['href'] ?? '';
  return _extractQueryInt(href, 'searchid');
}

_Pagination _extractPagination(Document document) {
  final current =
      int.tryParse(document.querySelector('.pg strong')?.text.trim() ?? '') ?? 1;
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
  return text.contains('對不起，沒有找到匹配結果');
}

String _snippet(String text, {int maxLength = 300}) {
  final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.length <= maxLength) return normalized;
  return normalized.substring(0, maxLength);
}
