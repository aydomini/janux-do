import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../../../forum_adapter/exceptions.dart';
import '../../../forum_adapter/models/forum_attachment.dart';
import '../../../forum_adapter/models/forum_post.dart';
import '../../../forum_adapter/models/forum_results.dart';
import '../utils/time_parser.dart';
import '../utils/url_builder.dart';
import 'post_html_cleaner.dart';

class ViewThreadParser {
  ViewThreadParser({
    this.urlBuilder = const JavBusUrlBuilder(),
    DiscuzTimeParser? timeParser,
    this.htmlCleaner = const PostHtmlCleaner(),
  }) : timeParser = timeParser ?? DiscuzTimeParser();

  final JavBusUrlBuilder urlBuilder;
  final DiscuzTimeParser timeParser;
  final PostHtmlCleaner htmlCleaner;

  PostListResult parse(
    String html, {
    required int threadId,
    String? requestUrl,
  }) {
    final document = html_parser.parse(html);
    final apiResult = _parseMobileApiResult(
      document,
      rawHtml: html,
      threadId: threadId,
    );
    if (apiResult != null) return apiResult;

    final posts = <ForumPost>[];
    var floorFallback = 1;

    // JavBus 自定义主题将第一帖（楼主）的作者信息放在 .nthread_info 中
    // 而非 post 容器内，需从页面级区域预提取
    // 用迭代替代 CSS 属性选择器，避免 html 包对 [href*=value] 的兼容性问题
    String threadHeaderAuthorName = '';
    int? threadHeaderAuthorId;
    final nthreadInfo = document.querySelector('.nthread_info');
    if (nthreadInfo != null) {
      // 首选：查找包含 uid= 的链接获取名称 + ID
      for (final link in nthreadInfo.querySelectorAll('a')) {
        final href = link.attributes['href'] ?? '';
        final uid = _extractQueryInt(href, 'uid');
        if (uid != null) {
          threadHeaderAuthorId = uid;
          threadHeaderAuthorName = link.text.trim();
          break;
        }
      }
      // 备选：从 lz 链接的 authorid 参数获取 ID
      threadHeaderAuthorId ??= () {
        for (final link in nthreadInfo.querySelectorAll('a')) {
          final href = link.attributes['href'] ?? '';
          final authorId = _extractQueryInt(href, 'authorid');
          if (authorId != null) return authorId;
        }
        return null;
      }();
    }

    // 从页面 header 预提取的楼主 ID 作为初始值，确保跨页楼主回复也能识别
    int? threadAuthorId = threadHeaderAuthorId;

    for (final scope in _postScopes(document)) {
      final postId = _extractPostId(scope.anchor);
      if (postId == null) continue;
      final container = scope.container;
      final author = _authorElement(container);
      final message = _messageElement(container, postId: postId);
      final rawContentHtml = message?.innerHtml ?? '';
      final contentHtml = htmlCleaner.clean(rawContentHtml);
      final authorId = _extractQueryInt(author?.attributes['href'] ?? '', 'uid');
      final floorNumber = _extractFloor(container) ?? floorFallback;
      // 第一帖（floorNumber == 1）作者来自 .nthread_info（JavBus 自定义主题），
      // .nthread_firstpostbox 容器内不含 .authi，_authorElement 回退可能匹配到正文中的链接。
      // 因此 floor 1 **始终**优先使用 header 提取信息，不依赖 _authorElement 结果。
      final isFloorOne = floorNumber == 1;
      final authorName = isFloorOne && threadHeaderAuthorName.isNotEmpty
          ? threadHeaderAuthorName
          : (author?.text.trim() ?? '');
      final effectiveAuthorId = isFloorOne
          ? (threadHeaderAuthorId ?? authorId)
          : authorId;
      // 若 header 未提取到楼主 ID（非 JavBus 主题），第一帖 authorId 作为兜底
      if (threadAuthorId == null && isFloorOne) {
        threadAuthorId = effectiveAuthorId ?? authorId;
      }
      // isThreadAuthor 简化为纯 ID 比较：楼主 = 1# 的作者 ID。
      // 只要 threadAuthorId 已确定（来自 header 或第一帖），后续楼层和点评
      // 只需 authorId == threadAuthorId 即可稳定匹配，无需 floorNumber 特判。
      posts.add(
        ForumPost(
          postId: postId,
          threadId: threadId,
          floorNumber: floorNumber,
          author: authorName,
          authorId: effectiveAuthorId,
          createdAt: timeParser.parse(_timeText(container)),
          avatarUrl: _extractAvatarUrl(container, urlBuilder)
              ?? urlBuilder.buildAvatarUrl(effectiveAuthorId),
          contentHtml: contentHtml,
          attachments: _extractAttachments(message),
          isThreadAuthor: effectiveAuthorId != null &&
              effectiveAuthorId == threadAuthorId,
        ),
      );
      floorFallback++;
    }

    if (posts.isEmpty && !_isKnownEmptyPage(document)) {
      throw ForumParseException(
        '未找到 Discuz 楼层',
        parserName: 'ViewThreadParser',
        requestUrl: requestUrl,
        responseSnippet: _snippet(html),
      );
    }
    if (posts.isNotEmpty &&
        posts.every((post) => post.contentHtml.trim().isEmpty) &&
        !_isKnownEmptyPage(document)) {
      throw ForumParseException(
        '未解析到任何帖子正文',
        parserName: 'ViewThreadParser',
        requestUrl: requestUrl,
        responseSnippet: _snippet(html),
      );
    }

    final pagination = _extractPagination(document);
    return PostListResult(
      posts: posts,
      currentPage: pagination.currentPage,
      totalPages: pagination.totalPages,
      hasNextPage: pagination.hasNextPage,
      threadTitle: _extractTitle(document),
      threadAuthorId: threadAuthorId,
    );
  }

  static String _extractTitle(Document document) {
    final title =
        document.querySelector('#thread_subject')?.text.trim() ??
        document.querySelector('.threadsubject')?.text.trim() ??
        document.querySelector('h1')?.text.trim() ??
        document.querySelector('title')?.text.trim();
    return title ?? '';
  }

  PostListResult? _parseMobileApiResult(
    Document document, {
    required String rawHtml,
    required int threadId,
  }) {
    final postElements = document.querySelectorAll('postlist > post, post');
    if (postElements.isEmpty) return null;
    final rawMessages = _extractRawMobileApiMessages(rawHtml);
    final posts = <ForumPost>[];
    var floorFallback = 1;

    // 从 <thread> 元素提取楼主的 authorId，跨页可靠
    final threadElement = document.querySelector('thread');
    final threadAuthorId = threadElement != null
        ? _childInt(threadElement, 'authorid')
        : null;

    for (var index = 0; index < postElements.length; index++) {
      final postElement = postElements[index];
      final postId = _childInt(postElement, 'pid');
      if (postId == null) continue;
      final authorId = _childInt(postElement, 'authorid');
      final message = index < rawMessages.length
          ? rawMessages[index]
          : _childText(postElement, 'message');
      final contentHtml = htmlCleaner.clean(message);
      posts.add(
        ForumPost(
          postId: postId,
          threadId: _childInt(postElement, 'tid') ?? threadId,
          floorNumber: _childInt(postElement, 'number') ?? floorFallback,
          author: _childText(postElement, 'author').trim(),
          authorId: authorId,
          createdAt: timeParser.parse(_childText(postElement, 'dateline')),
          avatarUrl: _extractMobileApiAvatarUrl(postElement, urlBuilder)
              ?? urlBuilder.buildAvatarUrl(authorId),
          contentHtml: contentHtml,
          attachments: _extractAttachmentsFromHtml(message),
          isThreadAuthor:
              threadAuthorId != null && authorId == threadAuthorId,
        ),
      );
      floorFallback++;
    }

    if (posts.isEmpty) return null;
    return PostListResult(
      posts: posts,
      currentPage: _documentInt(document, 'page') ?? 1,
      totalPages: _documentInt(document, 'totalpage') ?? 1,
      hasNextPage:
          (_documentInt(document, 'page') ?? 1) <
          (_documentInt(document, 'totalpage') ?? 1),
      threadTitle:
          document.querySelector('thread > subject')?.text.trim() ??
          document.querySelector('subject')?.text.trim() ??
          '',
      threadAuthorId: threadAuthorId,
    );
  }

  static int? _extractPostId(Element element) {
    final id = element.id;
    final match = RegExp(r'^(?:pid_?|post_)(\d+)$').firstMatch(id);
    return match == null ? null : int.parse(match.group(1)!);
  }

  static int? _extractFloor(Element element) {
    for (final marker in element.querySelectorAll('em')) {
      final next = marker.nextElementSibling;
      if (next?.localName == 'sup' && next?.text.trim() == '#') {
        final floor = int.tryParse(marker.text.trim());
        if (floor != null) return floor;
      }
    }
    final text =
        element.querySelector('.floor')?.text.trim() ??
        element.querySelector('em.xg1')?.text.trim() ??
        '';
    final match = RegExp(r'(\d+)').firstMatch(text);
    return match == null ? null : int.parse(match.group(1)!);
  }

  static List<_PostScope> _postScopes(Document document) {
    final seenIds = <String>{};
    final scopes = <_PostScope>[];
    for (final element in document.querySelectorAll('[id]')) {
      final postId = _extractPostId(element);
      if (postId == null) continue;
      if (!seenIds.add('$postId')) continue;
      scopes.add(
        _PostScope(anchor: element, container: _postContainer(element)),
      );
    }
    return scopes;
  }

  static Element _postContainer(Element anchor) {
    if (_hasPostContent(anchor)) return anchor;
    final sibling = _nextPostSibling(anchor);
    if (sibling != null) return _mergeElements(anchor, sibling);
    final ancestor = _closestPostAncestor(anchor);
    if (ancestor != null && _hasPostContent(ancestor)) return ancestor;
    final ancestorSibling = ancestor == null
        ? null
        : _nextPostSibling(ancestor);
    if (ancestor != null && ancestorSibling != null) {
      return _mergeElements(ancestor, ancestorSibling);
    }
    return ancestor ?? anchor;
  }

  static Element? _closestPostAncestor(Element element) {
    Element? current = element.parent;
    while (current != null) {
      if (_looksLikePostContainer(current)) {
        // 确保不返回包含多个帖子的页面级容器（如 #postlist），
        // 否则 _authorElement 会在全页范围搜到错误作者
        if (!_isMultiPostContainer(current)) return current;
      }
      current = current.parent;
    }
    return null;
  }

  /// 检查元素是否包含多个帖子（如果是，说明是页面级容器而非单帖容器）
  static bool _isMultiPostContainer(Element element) {
    var count = 0;
    for (final el in element.querySelectorAll('[id]')) {
      if (_extractPostId(el) != null) {
        count++;
        if (count > 1) return true;
      }
    }
    return false;
  }

  static Element? _nextPostSibling(Element element) {
    final parent = element.parent;
    if (parent == null) return null;
    final nodes = parent.nodes;
    final start = nodes.indexOf(element);
    if (start == -1) return null;
    final siblings = <Element>[];
    for (var index = start + 1; index < nodes.length; index++) {
      final node = nodes[index];
      if (node is! Element) continue;
      if (_extractPostId(node) != null) break;
      if (_isPaginationElement(node)) break;
      if (_looksLikePostContainer(node) || siblings.isNotEmpty) {
        siblings.add(node);
      }
    }
    if (siblings.isEmpty) return null;
    if (siblings.length == 1) return siblings.single;
    return html_parser
        .parseFragment(
          '<div>${siblings.map((element) => element.outerHtml).join()}</div>',
        )
        .children
        .first;
  }

  static Element _mergeElements(Element first, Element second) {
    return html_parser
        .parseFragment('<div>${first.outerHtml}${second.outerHtml}</div>')
        .children
        .first;
  }

  static bool _hasPostContent(Element element) {
    return _messageElement(element, postId: _extractPostId(element) ?? -1) !=
        null;
  }

  static bool _looksLikePostContainer(Element element) {
    return element.querySelector('.authi a[href]') != null ||
        element.querySelector('.author[href]') != null ||
        element.querySelector('.post_head a[href]') != null ||
        element.querySelector('.bm_user a[href]') != null ||
        element.querySelector('.message') != null ||
        element.querySelector('.mes') != null ||
        element.querySelector('.postmessage') != null ||
        element.querySelector('[id^="postmessage_"]') != null ||
        element.querySelector('.t_f') != null ||
        element.querySelector('.pcb') != null ||
        element.querySelector('.plc') != null ||
        element.querySelector('.pbody') != null ||
        element.querySelector('.post_msg') != null ||
        element.querySelector('.post_body') != null ||
        element.classes.contains('bm_c') ||
        element.classes.contains('pbody') ||
        element.classes.contains('mes') ||
        element.classes.contains('postmessage') ||
        element.classes.contains('post_head') ||
        element.classes.contains('post_msg') ||
        element.classes.contains('post_body');
  }

  static Element? _authorElement(Element postElement) {
    // 仅在作者信息区域（.authi / .post_head / .bm_user / .pls）内查找，
    // 禁止无前缀全容器搜索。回退到 a[href*="uid="] 会匹配到帖子正文中
    // 的任何用户链接（引用、@提及、收藏按钮等），导致作者名错误。
    // .post_head 是标准 Discuz XHTML Mobile 主题的作者容器。
    return postElement.querySelector('.author[href]') ??
        postElement.querySelector('.authi a[href]') ??
        postElement.querySelector('.post_head a[href]') ??
        postElement.querySelector('.bm_user a[href*="uid="]') ??
        postElement.querySelector('.bm_user a[href*="space&"]') ??
        postElement.querySelector('.pls a[href*="uid="]') ??
        postElement.querySelector('.pls a[href*="space&"]');
  }

  static Element? _messageElement(Element postElement, {required int postId}) {
    return postElement.querySelector('#postmessage_$postId') ??
        postElement.querySelector('.postmessage[id^="postmessage_"]') ??
        postElement.querySelector('.t_f[id^="postmessage_"]') ??
        postElement.querySelector('.t_f') ??
        postElement.querySelector('.message') ??
        postElement.querySelector('.mes') ??
        postElement.querySelector('.post_msg') ??
        postElement.querySelector('.post_body') ??
        postElement.querySelector('.pcb') ??
        postElement.querySelector('.t_fsz') ??
        postElement.querySelector('.plc .pct') ??
        postElement.querySelector('.plc');
  }

  static String _timeText(Element postElement) {
    return postElement.querySelector('.time')?.text.trim() ??
        postElement.querySelector('.authi em')?.text.trim() ??
        postElement.querySelector('[id^="authorposton"]')?.text.trim() ??
        postElement.querySelector('.bm_user em')?.text.trim() ??
        postElement.querySelector('em')?.text.trim() ??
        '';
  }

  static String? _extractAvatarUrl(
    Element postElement,
    JavBusUrlBuilder builder,
  ) {
    // 头像提取限定在作者信息侧边栏（.pls 面板）内，禁止全容器 img 搜索。
    // 第一帖（nthread_firstpostbox）不包含作者信息区域（.pls/.avtm/.authi
    // 均在外部 .nthread_info 中），无范围的后备选择器会在全容器包括正文中搜
    // 索，匹配到帖子正文内包含 "/avatar/" 路径的图片（如引用他人头像），导
    // 致楼主头像显示为其他用户的头像。
    final pls = postElement.querySelector('.pls');
    final image =
        postElement.querySelector('.avatar img[src]') ??
        postElement.querySelector('.avtm img[src]') ??
        pls?.querySelector('img[src*="avatar.php"]') ??
        pls?.querySelector('img[src*="/avatar/"]');
    final src = image?.attributes['src']?.trim();
    if (src == null || src.isEmpty) return null;
    return builder.resolve(src);
  }

  static String? _extractMobileApiAvatarUrl(
    Element postElement,
    JavBusUrlBuilder builder,
  ) {
    final avatar = _firstNonEmptyText(postElement, [
      'avatar',
      'avatarurl',
      'icon',
    ]);
    final value = avatar?.trim();
    if (value == null || value.isEmpty) return null;
    return builder.resolve(value);
  }

  static String? _firstNonEmptyText(Element element, List<String> selectors) {
    for (final selector in selectors) {
      final text = _childText(element, selector).trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  List<ForumAttachment> _extractAttachments(Element? message) {
    if (message == null) return const [];
    return _extractAttachmentsFromHtml(message.innerHtml);
  }

  List<ForumAttachment> _extractAttachmentsFromHtml(String html) {
    final message = html_parser.parseFragment(html);
    final attachments = <ForumAttachment>[];
    final seenUrls = <String>{};
    for (final link in message.querySelectorAll('a[href]')) {
      final href = link.attributes['href']?.trim();
      if (href == null || href.isEmpty) continue;
      final normalizedHref = href.replaceAll('&amp;', '&');
      final uri = Uri.tryParse(normalizedHref);
      final isAttachment =
          uri?.queryParameters['mod'] == 'attachment' ||
          uri?.queryParameters.containsKey('aid') == true;
      if (!isAttachment) continue;
      final url = urlBuilder.resolve(normalizedHref);
      if (!seenUrls.add(url)) continue;
      attachments.add(
        ForumAttachment(
          attachmentId: uri?.queryParameters['aid'],
          fileName: link.text.trim().isEmpty ? '附件' : link.text.trim(),
          url: url,
        ),
      );
    }
    return attachments;
  }

  /// 从桌面版 HTML 中解析楼中楼点评（pstl 块），按帖子 pid 分组
  /// [knownPid] 用于 commentmore AJAX 响应：该响应不含 comment_XXX 外层容器，
  /// 无法通过父级推断 pid，此时用此参数作为回退。
  static Map<int, List<ForumComment>> parseComments(
    String html, {
    int? knownPid,
  }) {
    final document = html_parser.parse(html);
    final results = <int, List<ForumComment>>{};
    final pstlBlocks = document.querySelectorAll('.pstl');
    for (final block in pstlBlocks) {
      final pid = _findPstlParentPid(block) ?? knownPid;
      if (pid == null) continue;
      final psta = block.querySelector('.psta');
      final psti = block.querySelector('.psti');

      // 作者提取：多级备选
      final authorLink = _findCommentAuthorLink(psta, block);
      final authorName = authorLink?.text.trim() ?? '';
      final authorId = _extractQueryInt(
        authorLink?.attributes['href'] ?? '',
        'uid',
      );
      final avatarImg = psta?.querySelector('img[src]');
      final avatarUrl = avatarImg?.attributes['src']?.trim();

      // 时间提取：多级备选，优先从元素 title 属性取完整时间戳
      final timeSpan = _findCommentTimeElement(psti, block);
      var createdAt = _extractCommentTime(timeSpan);
      timeSpan?.remove();

      // 移除作者区域避免污染内容文本
      psta?.remove();
      authorLink?.remove();

      var content = (psti?.text ?? block.text).trim()
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      // 时间未通过元素提取到时，从文本正则提取并剥离
      if (createdAt == null) {
        final textMatch = _extractTimeFromText(content);
        if (textMatch != null) {
          createdAt = textMatch.dateTime;
          content = content.replaceFirst(textMatch.matchedText, '').trim();
        }
      }

      if (authorName.isEmpty && content.isEmpty) continue;
      results.putIfAbsent(pid, () => []).add(
        ForumComment(
          author: authorName,
          authorId: authorId,
          avatarUrl: avatarUrl?.isNotEmpty == true ? avatarUrl : null,
          content: content,
          createdAt: createdAt,
        ),
      );
    }
    return results;
  }

  /// 从 viewthread 桌面版 HTML 中提取点评分页信息
  /// 返回 `Map<pid, 总页数>`，仅包含有超过 1 页的帖子
  /// 反向查找：从 .pgs 出发，向上/向前找到最近的 comment_XXX
  static Map<int, int> parseCommentPagination(String html) {
    final document = html_parser.parse(html);
    final results = <int, int>{};
    for (final pgBar in document.querySelectorAll('.pgs')) {
      final pg = pgBar.querySelector('.pg');
      if (pg == null) continue;
      // 提取最大页码
      var maxPage = 1;
      for (final link in pg.querySelectorAll('a')) {
        final onclick = link.attributes['onclick'] ?? '';
        final pageMatch = RegExp(r'[&?]page=(\d+)').firstMatch(onclick);
        if (pageMatch != null) {
          final page = int.parse(pageMatch.group(1)!);
          if (page > maxPage) maxPage = page;
        }
      }
      if (maxPage <= 1) continue;
      // 反向查找最近的 comment_XXX：先查子节点，再向前兄弟，最后向上
      final pid = _findNearestCommentPid(pgBar);
      if (pid != null) results[pid] = maxPage;
    }
    return results;
  }

  /// 从 .pgs 元素出发，反向查找最近的 comment_XXXXXX 的 pid
  static int? _findNearestCommentPid(Element pgBar) {
    // 1) 检查自身及祖先（.pgs 可能在 comment_XXX 内部）
    Element? cursor = pgBar;
    while (cursor != null && cursor.localName != 'body') {
      final m = RegExp(r'^comment_(\d+)$').firstMatch(
        cursor.attributes['id'] ?? '',
      );
      if (m != null) return int.tryParse(m.group(1)!);
      cursor = cursor.parent;
    }
    // 2) 向前遍历兄弟节点
    Element? prev = pgBar.previousElementSibling;
    while (prev != null) {
      final id = prev.attributes['id'] ?? '';
      final m = RegExp(r'^comment_(\d+)$').firstMatch(id);
      if (m != null) return int.tryParse(m.group(1)!);
      final sub = prev.querySelector('[id^="comment_"]');
      if (sub != null) {
        final sm = RegExp(r'^comment_(\d+)$').firstMatch(
          sub.attributes['id'] ?? '',
        );
        if (sm != null) return int.tryParse(sm.group(1)!);
      }
      prev = prev.previousElementSibling;
    }
    // 3) 向上查父节点的前兄弟
    Element? parent = pgBar.parent;
    while (parent != null && parent.localName != 'body') {
      final prevSib = parent.previousElementSibling;
      if (prevSib != null) {
        final m = RegExp(r'^comment_(\d+)$').firstMatch(
          prevSib.attributes['id'] ?? '',
        );
        if (m != null) return int.tryParse(m.group(1)!);
        final sub = prevSib.querySelector('[id^="comment_"]');
        if (sub != null) {
          final sm = RegExp(r'^comment_(\d+)$').firstMatch(
            sub.attributes['id'] ?? '',
          );
          if (sm != null) return int.tryParse(sm.group(1)!);
        }
      }
      parent = parent.parent;
    }
    return null;
  }

  /// 多级备选查找点评作者链接
  /// 优先匹配 Discuz 用户名链接（xi2/xw1 class），避免选到头像外链
  static Element? _findCommentAuthorLink(
    Element? psta,
    Element block,
  ) {
    // 优先找 Discuz 用户名链接（class="xi2 xw1"）
    final named = psta?.querySelector('a.xi2') ??
        psta?.querySelector('a.xw1') ??
        block.querySelector('.psta a.xi2') ??
        block.querySelector('.psta a.xw1');
    if (named != null) return named;

    // 回退到 uid 链接，跳过无文本的（通常是头像链接）
    final uidLinks = psta?.querySelectorAll('a[href*="uid="]') ?? [];
    for (final link in uidLinks) {
      if (link.text.trim().isNotEmpty) return link;
    }
    return psta?.querySelector('a[href*="space&"]') ??
        psta?.querySelector('a[href]') ??
        block.querySelector('a[href*="uid="]') ??
        block.querySelector('a[href*="space&"]');
  }

  /// 多级备选查找点评时间元素
  static Element? _findCommentTimeElement(
    Element? psti,
    Element block,
  ) {
    return psti?.querySelector('.xg1') ??
        psti?.querySelector('em') ??
        psti?.querySelector('span') ??
        block.querySelector('.xg1') ??
        block.querySelector('em') ??
        block.querySelector('span');
  }

  /// 从时间元素中提取 DateTime
  /// 优先级：title 属性（绝对时间戳，含递归子元素查找） > 元素文本（绝对时间） > 相对时间
  static DateTime? _extractCommentTime(Element? timeSpan) {
    if (timeSpan == null) return null;

    // 递归查找 title 属性（Discuz 可能在子 <span> 中存放时间戳）
    // 例如 <span class="xg1">發表於 <span title="2026-6-9 13:17">4 小時前</span></span>
    final title = _findTitleInTree(timeSpan);
    if (title != null) {
      final fromTitle = _parseAbsoluteTime(title);
      if (fromTitle != null) return fromTitle;
    }

    // 规范化文本：将 &nbsp; /   替换为普通空格，Dart \s 不匹配
    final raw = timeSpan.text
        .replaceAll(' ', ' ')
        .replaceAll('&nbsp;', ' ')
        .trim();

    // 尝试绝对时间
    final absolute = _parseAbsoluteTime(raw);
    if (absolute != null) return absolute;

    // 尝试相对时间：X 天前 / X 小时前 / X 分钟前 / 刚刚 / 前天
    return _parseRelativeTime(raw);
  }

  /// 递归搜索元素树中的 title 属性
  static String? _findTitleInTree(Element element) {
    final t = element.attributes['title']?.trim();
    if (t != null && t.isNotEmpty) return t;
    for (final child in element.children) {
      final found = _findTitleInTree(child);
      if (found != null) return found;
    }
    return null;
  }

  /// 解析绝对时间字符串，支持格式：
  /// - 2025-6-9 14:30（不补零）
  /// - 2025-06-09 14:30（补零）
  /// - 2025年6月9日 16:45（中文）
  static DateTime? _parseAbsoluteTime(String raw) {
    final m = RegExp(
      r'(\d{4})[-\/](\d{1,2})[-\/](\d{1,2})\s+(\d{1,2}):(\d{2})',
    ).firstMatch(raw);
    if (m != null) {
      return DateTime(
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
        int.parse(m.group(4)!),
        int.parse(m.group(5)!),
      );
    }
    final cm = RegExp(
      r'(\d{4})\s*年\s*(\d{1,2})\s*月\s*(\d{1,2})\s*日\s*(\d{1,2}):(\d{2})',
    ).firstMatch(raw);
    if (cm != null) {
      return DateTime(
        int.parse(cm.group(1)!),
        int.parse(cm.group(2)!),
        int.parse(cm.group(3)!),
        int.parse(cm.group(4)!),
        int.parse(cm.group(5)!),
      );
    }
    return null;
  }

  /// 解析相对时间字符串，支持格式：
  /// - X 天前
  /// - X 小时前 / X 小時前
  /// - X 分钟前 / X 分鐘前
  /// - 刚刚 / 剛剛 / 秒前
  /// - 前天 HH:MM
  static DateTime? _parseRelativeTime(String raw) {
    final daysMatch = RegExp(r'(\d+)\s*天前').firstMatch(raw);
    if (daysMatch != null) {
      return DateTime.now().subtract(
        Duration(days: int.parse(daysMatch.group(1)!)),
      );
    }
    final hoursMatch = RegExp(r'(\d+)\s*(?:小时|小時)前').firstMatch(raw);
    if (hoursMatch != null) {
      return DateTime.now().subtract(
        Duration(hours: int.parse(hoursMatch.group(1)!)),
      );
    }
    final minsMatch = RegExp(r'(\d+)\s*(?:分钟|分鐘)前').firstMatch(raw);
    if (minsMatch != null) {
      return DateTime.now().subtract(
        Duration(minutes: int.parse(minsMatch.group(1)!)),
      );
    }
    // 前天 HH:MM
    final dayBeforeMatch = RegExp(r'前天\s*(\d{1,2}):(\d{2})').firstMatch(raw);
    if (dayBeforeMatch != null) {
      final d = DateTime.now().subtract(const Duration(days: 2));
      return DateTime(
        d.year, d.month, d.day,
        int.parse(dayBeforeMatch.group(1)!),
        int.parse(dayBeforeMatch.group(2)!),
      );
    }
    if (raw.contains('刚刚') || raw.contains('剛剛') || raw.contains('秒前')) {
      return DateTime.now();
    }
    return null;
  }

  /// 从纯文本中提取时间并返回匹配的 DateTime 和原始文本
  /// 用于时间不在独立元素中，而与内容混在一起的场景
  static ({DateTime dateTime, String matchedText})? _extractTimeFromText(
    String text,
  ) {
    final fullMatch = RegExp(
      r'(\d{4})[-\/](\d{1,2})[-\/](\d{1,2})\s+(\d{1,2}):(\d{2})',
    ).firstMatch(text);
    if (fullMatch != null) {
      return (
        dateTime: DateTime(
          int.parse(fullMatch.group(1)!),
          int.parse(fullMatch.group(2)!),
          int.parse(fullMatch.group(3)!),
          int.parse(fullMatch.group(4)!),
          int.parse(fullMatch.group(5)!),
        ),
        matchedText: fullMatch.group(0)!,
      );
    }
    final shortMatch = RegExp(
      r'(\d{1,2})[-\/](\d{1,2})\s+(\d{1,2}):(\d{2})',
    ).firstMatch(text);
    if (shortMatch != null) {
      return (
        dateTime: DateTime(
          DateTime.now().year,
          int.parse(shortMatch.group(1)!),
          int.parse(shortMatch.group(2)!),
          int.parse(shortMatch.group(3)!),
          int.parse(shortMatch.group(4)!),
        ),
        matchedText: shortMatch.group(0)!,
      );
    }
    final chineseMatch = RegExp(
      r'(\d{4})\s*年\s*(\d{1,2})\s*月\s*(\d{1,2})\s*日\s*(\d{1,2}):(\d{2})',
    ).firstMatch(text);
    if (chineseMatch != null) {
      return (
        dateTime: DateTime(
          int.parse(chineseMatch.group(1)!),
          int.parse(chineseMatch.group(2)!),
          int.parse(chineseMatch.group(3)!),
          int.parse(chineseMatch.group(4)!),
          int.parse(chineseMatch.group(5)!),
        ),
        matchedText: chineseMatch.group(0)!,
      );
    }
    return null;
  }

  static int? _findPstlParentPid(Element element) {
    Element? current = element.parent;
    while (current != null) {
      // pidXXXX 格式（标准 Discuz 楼层 ID）
      final idAttr =
          current.attributes['id'] ??
          current.querySelector('[id^="pid"]')?.attributes['id'];
      if (idAttr != null) {
        final pidMatch = RegExp(r'^pid(\d+)$').firstMatch(idAttr);
        if (pidMatch != null) return int.tryParse(pidMatch.group(1)!);
      }
      // comment_XXXXXX 格式（Discuz X 点评容器 ID）
      final commentIdAttr = current.attributes['id'] ?? '';
      final commentMatch = RegExp(r'^comment_(\d+)$').firstMatch(commentIdAttr);
      if (commentMatch != null) return int.tryParse(commentMatch.group(1)!);
      // a[id^="pid"] 格式
      final pidLink = current.querySelector('a[id^="pid"]');
      if (pidLink != null) {
        final href = pidLink.attributes['id'] ?? '';
        final pidMatch = RegExp(r'^pid(\d+)$').firstMatch(href);
        if (pidMatch != null) return int.tryParse(pidMatch.group(1)!);
      }
      current = current.parent;
    }
    return null;
  }
}

typedef _Pagination = ({int currentPage, int totalPages, bool hasNextPage});

_Pagination _extractPagination(Document document) {
  final current =
      int.tryParse(document.querySelector('.pg strong')?.text.trim() ?? '') ??
      1;
  var total = current;
  for (final link in document.querySelectorAll('.pg a')) {
    final page = int.tryParse(
      RegExp(r'(\d+)').firstMatch(link.text.trim())?.group(1) ?? '',
    );
    if (page != null && page > total) total = page;
  }
  for (final element in document.querySelectorAll('.pg [title]')) {
    final page = int.tryParse(
      RegExp(
            r'共\s*(\d+)\s*頁',
          ).firstMatch(element.attributes['title'] ?? '')?.group(1) ??
          '',
    );
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

String _childText(Element element, String selector) {
  return element.querySelector(selector)?.text.trim() ?? '';
}

int? _childInt(Element element, String selector) {
  return int.tryParse(_childText(element, selector));
}

int? _documentInt(Document document, String selector) {
  return int.tryParse(document.querySelector(selector)?.text.trim() ?? '');
}

List<String> _extractRawMobileApiMessages(String html) {
  final messages = <String>[];
  final pattern = RegExp(
    r'<message\b[^>]*>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?</message>',
    caseSensitive: false,
    dotAll: true,
  );
  for (final match in pattern.allMatches(html)) {
    messages.add(match.group(1)?.trim() ?? '');
  }
  return messages;
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

bool _isPaginationElement(Element element) {
  return element.classes.contains('pg') ||
      element.classes.contains('page') ||
      element.querySelector('.pg') != null;
}

class _PostScope {
  const _PostScope({required this.anchor, required this.container});

  final Element anchor;
  final Element container;
}
