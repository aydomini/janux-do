import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:html/dom.dart' as dom;

import '../../forum_adapter/javbus/utils/url_builder.dart';
import '../../forum_adapter/models/forum_post.dart';
import '../../forum_adapter/models/forum_results.dart';
import '../../providers/forum_provider.dart';
import '../../services/highlighter_service.dart';
import '../../services/javbus_cache_manager.dart';

import '../../theme/app_semantic_colors.dart';
import '../../theme/app_typography.dart';
import '../../utils/link_launcher.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/loading_spinner.dart';
import 'image_header_service.dart';
import 'javbus_layout.dart';

class JavBusThreadPage extends ConsumerStatefulWidget {
  const JavBusThreadPage({
    super.key,
    required this.threadId,
    required this.initialTitle,
    this.cache,
  });

  final int threadId;
  final String initialTitle;
  final JavBusThreadContentCache? cache;

  @override
  ConsumerState<JavBusThreadPage> createState() => _JavBusThreadPageState();
}

class _JavBusThreadPageState extends ConsumerState<JavBusThreadPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.initialTitle)),
      body: JavBusThreadContent(
        key: ValueKey('javbus-thread-content-${widget.threadId}'),
        threadId: widget.threadId,
        initialTitle: widget.initialTitle,
        cache: widget.cache,
      ),
    );
  }
}

class JavBusThreadContentCache {
  final List<ForumPost> posts = [];
  final Map<int, List<ForumComment>> comments = {};
  int currentPage = 1;
  bool hasNextPage = true;
  bool hasLoaded = false;
  double scrollOffset = 0;
}

class JavBusThreadContent extends ConsumerStatefulWidget {
  const JavBusThreadContent({
    super.key,
    required this.threadId,
    required this.initialTitle,
    this.cache,
  });

  final int threadId;
  final String initialTitle;
  final JavBusThreadContentCache? cache;

  @override
  ConsumerState<JavBusThreadContent> createState() =>
      _JavBusThreadContentState();
}

class _JavBusThreadContentState extends ConsumerState<JavBusThreadContent> {
  final ScrollController _scrollController = ScrollController();
  final List<ForumPost> _posts = [];
  late final JavBusThreadContentCache _cache =
      widget.cache ?? JavBusThreadContentCache();
  int _currentPage = 1;
  bool _hasNextPage = true;
  bool _isLoadingInitial = true;
  bool _isLoadingMore = false;
  Object? _error;
  StackTrace? _stackTrace;
  int? _threadAuthorId;
  Map<int, List<ForumComment>> _comments = {};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _restoreFromCache();
    if (_isLoadingInitial) {
      Future.microtask(_refreshPosts);
    } else {
      _restoreScrollOffset();
    }
  }

  @override
  void dispose() {
    _saveCache();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final position = _scrollController.position;
    _cache.scrollOffset = position.pixels;
    if (position.extentAfter > 600) return;
    _loadNextPage();
  }

  void _restoreFromCache() {
    if (!_cache.hasLoaded) return;
    _posts
      ..clear()
      ..addAll(_cache.posts);
    _comments = Map<int, List<ForumComment>>.from(_cache.comments);
    _currentPage = _cache.currentPage;
    _hasNextPage = _cache.hasNextPage;
    _isLoadingInitial = false;
    _isLoadingMore = false;
    _error = null;
    _stackTrace = null;
  }

  void _restoreScrollOffset() {
    final offset = _cache.scrollOffset;
    if (offset <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final maxOffset = _scrollController.position.maxScrollExtent;
      _scrollController.jumpTo(offset.clamp(0, maxOffset));
    });
  }

  void _saveCache() {
    _cache.posts
      ..clear()
      ..addAll(_posts);
    _cache.comments
      ..clear()
      ..addAll(_comments);
    _cache
      ..currentPage = _currentPage
      ..hasNextPage = _hasNextPage
      ..hasLoaded = !_isLoadingInitial && _posts.isNotEmpty;
    if (_scrollController.hasClients) {
      _cache.scrollOffset = _scrollController.position.pixels;
    }
  }

  Future<void> _refreshPosts() async {
    setState(() {
      _isLoadingInitial = true;
      _isLoadingMore = false;
      _error = null;
      _stackTrace = null;
    });
    try {
      final result = await ref
          .read(forumAdapterProvider)
          .getPosts(threadId: widget.threadId);
      if (!mounted) return;
      setState(() {
        _posts
          ..clear()
          ..addAll(result.posts);
        _trackThreadAuthor();
        ImageHeaderService.instance.refresh();
        _currentPage = result.currentPage;
        _hasNextPage = result.hasNextPage;
        _isLoadingInitial = false;
        _cache.scrollOffset = 0;
        _saveCache();
      });
      _loadComments(1);
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _stackTrace = stackTrace;
        _isLoadingInitial = false;
      });
    }
  }

  Future<void> _loadNextPage() async {
    if (_isLoadingInitial || _isLoadingMore || !_hasNextPage) return;
    final requestedPage = _currentPage + 1;
    setState(() {
      _isLoadingMore = true;
      _error = null;
      _stackTrace = null;
    });
    try {
      final result = await ref
          .read(forumAdapterProvider)
          .getPosts(threadId: widget.threadId, page: requestedPage);
      if (!mounted) return;
      setState(() {
        final addedPostCount = _mergePosts(result.posts);
        _trackThreadAuthor();
        ImageHeaderService.instance.refresh();
        _currentPage = result.currentPage < requestedPage
            ? requestedPage
            : result.currentPage;
        _hasNextPage = result.hasNextPage && addedPostCount > 0;
        _isLoadingMore = false;
        _error = null;
        _stackTrace = null;
        _saveCache();
      });
      _loadComments(requestedPage);
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _stackTrace = stackTrace;
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _loadComments(int page) async {
    try {
      final comments = await ref
          .read(forumAdapterProvider)
          .getComments(widget.threadId, page: page);
      if (!mounted) return;
      setState(() => _comments.addAll(comments));
    } catch (_) {}
  }

  void _trackThreadAuthor() {
    if (_threadAuthorId != null) return;
    for (final post in _posts) {
      if (post.authorId != null &&
          (post.floorNumber == 1 || post.isThreadAuthor)) {
        _threadAuthorId = post.authorId;
        return;
      }
    }
  }

  bool _isPostByThreadAuthor(ForumPost post) {
    return _threadAuthorId != null && post.authorId == _threadAuthorId;
  }

  int _mergePosts(List<ForumPost> incoming) {
    final existingPostIds = _posts.map((post) => post.postId).toSet();
    var addedPostCount = 0;
    for (final post in incoming) {
      if (existingPostIds.add(post.postId)) {
        _posts.add(post);
        addedPostCount++;
      }
    }
    return addedPostCount;
  }

  @override
  Widget build(BuildContext context) {
    return _buildBody();
  }

  Widget _buildBody() {
    final error = _error;
    if (error != null && _posts.isEmpty) {
      return ErrorView(
        error: error,
        stackTrace: _stackTrace,
        title: '主题内容加载失败',
        onRetry: _refreshPosts,
      );
    }
    if (_isLoadingInitial) {
      return const Center(child: LoadingSpinner(size: 40));
    }
    if (_posts.isEmpty) {
      return const Center(child: Text('暂无楼层内容'));
    }
    return RefreshIndicator(
      onRefresh: _refreshPosts,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return ListView.separated(
            controller: _scrollController,
            padding: JavBusLayout.threadPadding,
            itemCount: _posts.length + 1,
            separatorBuilder: (context, index) {
              if (index >= _posts.length - 1) {
                return const SizedBox(height: 10);
              }
              return Align(
                alignment: Alignment.center,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: JavBusLayout.contentMaxWidth,
                  ),
                  child: const Divider(height: 28),
                ),
              );
            },
            itemBuilder: (context, index) {
              if (index == _posts.length) {
                return _LoadMoreFooter(
                  hasNextPage: _hasNextPage,
                  isLoading: _isLoadingMore,
                  error: _posts.isEmpty ? null : _error,
                  onRetry: _loadNextPage,
                );
              }
              final postIndex = index;
              final post = _posts[postIndex];
              final displayFloorNumber = post.floorNumber < postIndex + 1
                  ? postIndex + 1
                  : post.floorNumber;
              final postComments = _comments[post.postId] ?? const <ForumComment>[];
              return _PostCard(
                post: post,
                displayFloorNumber: displayFloorNumber,
                isThreadAuthor: _isPostByThreadAuthor(post),
                comments: postComments,
              );
            },
          );
        },
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({
    required this.post,
    required this.displayFloorNumber,
    required this.isThreadAuthor,
    this.comments = const [],
  });

  final ForumPost post;
  final int displayFloorNumber;
  final bool isThreadAuthor;
  final List<ForumComment> comments;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final avatarUrl = post.avatarUrl;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: _PostAvatar(avatarUrl: avatarUrl),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: JavBusLayout.textContentMaxWidth,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            post.author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (isThreadAuthor) ...[
                          const SizedBox(width: 8),
                          const _AuthorBadge(label: '楼主'),
                        ],
                      ],
                    ),
                    const SizedBox(height: 14),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        return SelectionArea(
                          child: HtmlWidget(
                            post.contentHtml,
                            renderMode: RenderMode.column,
                            textStyle: theme.textTheme.bodyLarge?.copyWith(
                              fontSize: AppTypography.readingBodyFontSize,
                              height: AppTypography.readingBodyHeight,
                            ),
                            customStylesBuilder: (element) =>
                                _buildJavBusHtmlStyles(theme, element),
                            customWidgetBuilder: (element) =>
                                _buildJavBusHtmlWidget(
                                  context,
                                  element,
                                  constraints.maxWidth,
                                ),
                            onTapUrl: (url) {
                              launchInExternalBrowser(url);
                              return true;
                            },
                          ),
                        );
                      },
                    ),
                    if (post.attachments.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final attachment in post.attachments)
                            OutlinedButton.icon(
                              onPressed: () =>
                                  launchInExternalBrowser(attachment.url),
                              icon: const Icon(
                                Icons.attach_file_rounded,
                                size: 18,
                              ),
                              label: Text(attachment.fileName),
                            ),
                        ],
                      ),
                    ],
                    if (comments.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _CommentSection(comments: comments),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 18),
        SizedBox(
          width: JavBusLayout.postMetaColumnWidth,
                child: _PostMetaColumn(
                  floorNumber: displayFloorNumber,
                  createdAt: post.createdAt,
                ),
              ),
            ],
          ),
        ),
    );
  }
}

class _PostMetaColumn extends StatelessWidget {
  const _PostMetaColumn({required this.floorNumber, required this.createdAt});

  final int floorNumber;
  final DateTime? createdAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: ValueKey('javbus-post-meta-$floorNumber'),
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '#$floorNumber',
          textAlign: TextAlign.right,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (createdAt != null) ...[
          const SizedBox(height: 6),
          Text(
            _formatPostMetaTime(createdAt!),
            textAlign: TextAlign.right,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _AuthorBadge extends StatelessWidget {
  const _AuthorBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSecondaryContainer,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

String _formatPostMetaTime(DateTime value) {
  final now = DateTime.now();
  String two(int input) => input.toString().padLeft(2, '0');
  final dateStr = value.year == now.year
      ? '${two(value.month)} 月 ${two(value.day)} 日'
      : '${value.year} 年 ${two(value.month)} 月 ${two(value.day)} 日';
  return '$dateStr\n${two(value.hour)}:${two(value.minute)}';
}

String _formatCommentTime(DateTime value) {
  final now = DateTime.now();
  String two(int input) => input.toString().padLeft(2, '0');
  final dateStr = value.year == now.year
      ? '${two(value.month)} 月 ${two(value.day)} 日'
      : '${value.year} 年 ${two(value.month)} 月 ${two(value.day)} 日';
  return '$dateStr ${two(value.hour)}:${two(value.minute)}';
}

Widget? _buildJavBusHtmlWidget(
  BuildContext context,
  dom.Element element,
  double contentWidth,
) {
  if (element.localName == 'pre') {
    final codeElement = element.querySelector('code') ?? element;
    return JavBusCodeBlock(
      code: _extractCodeText(codeElement),
      language: _extractCodeLanguage(codeElement),
      maxWidth: contentWidth,
    );
  }
  if (element.localName == 'blockquote') {
    return JavBusQuoteBlock(html: element.innerHtml, maxWidth: contentWidth);
  }
  if (element.localName == 'img') {
    final src = element.attributes['src']?.trim();
    if (src == null || src.isEmpty) return null;
    final url = _resolvePostResourceUrl(src);
    if (_isInlineEmojiImage(element, url)) {
      return InlineCustomWidget(
        alignment: PlaceholderAlignment.middle,
        child: JavBusInlineEmojiImage(url: url),
      );
    }
    return JavBusPostImage(
      url: url,
      maxWidth: contentWidth,
      onOpen: () => _showJavBusImagePreview(context, url),
    );
  }
  if (element.localName != 'video') return null;
  final src =
      element.attributes['src']?.trim() ??
      element.querySelector('source[src]')?.attributes['src']?.trim();
  if (src == null || src.isEmpty) return null;
  final url = _resolvePostResourceUrl(src);
  return JavBusPostVideoPreview(
    url: url,
    maxWidth: contentWidth,
    onOpen: () => launchInExternalBrowser(url),
  );
}

void _showJavBusImagePreview(BuildContext context, String url) {
  final semanticColors = Theme.of(context).appSemanticColors;
  showDialog<void>(
    context: context,
    barrierColor: semanticColors.imagePreviewScrim.withValues(alpha: 0.82),
    builder: (context) => JavBusImagePreviewDialog(url: url),
  );
}

Map<String, String>? _buildJavBusHtmlStyles(
  ThemeData theme,
  dom.Element element,
) {
  final localName = element.localName;
  if (localName == 'p') {
    return {'margin': '0 0 12px'};
  }
  if (localName == 'a') {
    return {
      'color': _cssColor(theme.colorScheme.primary),
      'text-decoration': 'none',
      'font-weight': '600',
    };
  }
  if (localName == 'strong' || localName == 'b') {
    return {'font-weight': '700'};
  }
  if (localName == 'ul' || localName == 'ol') {
    return {'margin': '8px 0 12px', 'padding-left': '22px'};
  }
  if (localName == 'li') {
    return {'margin': '4px 0'};
  }
  if (localName == 'code' && element.parent?.localName != 'pre') {
    return {
      'font-family':
          'ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace',
      'font-size': '0.92em',
      'font-weight': '500',
      'background-color': _cssColor(
        theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
      ),
      'color': _cssColor(theme.colorScheme.onSurface),
    };
  }
  return null;
}

String _resolvePostResourceUrl(String rawUrl) {
  return const JavBusUrlBuilder().resolve(rawUrl);
}

String _extractCodeText(dom.Element codeElement) {
  final text = codeElement.text;
  if (text.endsWith('\n')) {
    return text.substring(0, text.length - 1);
  }
  return text;
}

String? _extractCodeLanguage(dom.Element codeElement) {
  final className = codeElement.className.trim();
  if (className.isEmpty) return null;
  final languageMatch = RegExp(
    r'(?:^|\s)(?:language|lang)-([A-Za-z0-9_+#.-]+)(?:\s|$)',
  ).firstMatch(className);
  if (languageMatch != null) {
    return _normalizeJavBusCodeLanguage(languageMatch.group(1));
  }
  for (final classPart in className.split(RegExp(r'\s+'))) {
    final normalized = _normalizeJavBusCodeLanguage(classPart);
    if (normalized != null) return normalized;
  }
  return null;
}

String? _normalizeJavBusCodeLanguage(String? value) {
  final language = value?.trim().toLowerCase();
  if (language == null || language.isEmpty) return null;
  return switch (language) {
    'js' => 'javascript',
    'ts' => 'typescript',
    'py' => 'python',
    'rb' => 'ruby',
    'yml' => 'yaml',
    'sh' || 'shell' => 'bash',
    'objc' || 'obj-c' => 'objectivec',
    'c++' => 'cpp',
    'c#' => 'csharp',
    'plain' || 'text' || 'txt' => 'plaintext',
    _ => language,
  };
}

String _cssColor(Color color) {
  final value = color.toARGB32() & 0x00ffffff;
  return '#${value.toRadixString(16).padLeft(6, '0')}';
}

class JavBusCodeBlock extends StatefulWidget {
  const JavBusCodeBlock({
    super.key,
    required this.code,
    required this.language,
    required this.maxWidth,
  });

  final String code;
  final String? language;
  final double maxWidth;

  @override
  State<JavBusCodeBlock> createState() => _JavBusCodeBlockState();
}

class _JavBusCodeBlockState extends State<JavBusCodeBlock> {
  List<HighlightToken>? _tokens;

  @override
  void initState() {
    super.initState();
    _loadHighlight();
  }

  @override
  void didUpdateWidget(covariant JavBusCodeBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code != widget.code ||
        oldWidget.language != widget.language) {
      _tokens = null;
      _loadHighlight();
    }
  }

  Future<void> _loadHighlight() async {
    try {
      final tokens = await HighlighterService.instance.highlightAsync(
        widget.code,
        language: widget.language,
      );
      if (!mounted) return;
      setState(() => _tokens = tokens);
    } catch (_) {
      if (!mounted) return;
      setState(() => _tokens = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseStyle = HighlighterService.instance.firaCodeStyle.copyWith(
      fontSize: 14,
      height: 1.58,
      color: theme.colorScheme.onSurface,
    );
    final tokens = _tokens;
    final codeSpan = tokens != null && tokens.isNotEmpty
        ? HighlighterService.instance.tokensToSpan(
            tokens,
            isDark: isDark,
            baseStyle: baseStyle,
          )
        : TextSpan(text: widget.code, style: baseStyle);
    final languageLabel = widget.language?.toUpperCase();
    return Padding(
      key: const ValueKey('javbus-code-block'),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.maxWidth),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: isDark ? 0.46 : 0.64,
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.72),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (languageLabel != null) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  child: SelectionContainer.disabled(
                    child: Text(
                      languageLabel,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                Divider(
                  height: 14,
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.6,
                  ),
                ),
              ],
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.fromLTRB(
                  14,
                  languageLabel == null ? 12 : 2,
                  14,
                  12,
                ),
                child: SelectableText.rich(codeSpan),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class JavBusQuoteBlock extends StatelessWidget {
  const JavBusQuoteBlock({
    super.key,
    required this.html,
    required this.maxWidth,
  });

  final String html;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: const ValueKey('javbus-quote-block'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.34 : 0.52,
            ),
            border: Border(
              left: BorderSide(color: theme.colorScheme.outline, width: 4),
            ),
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(6),
              bottomRight: Radius.circular(6),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: HtmlWidget(
              html,
              renderMode: RenderMode.column,
              textStyle: theme.textTheme.bodyLarge?.copyWith(
                height: 1.64,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              customStylesBuilder: (element) =>
                  _buildJavBusHtmlStyles(theme, element),
              customWidgetBuilder: (element) {
                if (element.localName == 'img') {
                  final src = element.attributes['src']?.trim();
                  if (src == null || src.isEmpty) return null;
                  final url = _resolvePostResourceUrl(src);
                  if (_isInlineEmojiImage(element, url)) {
                    return InlineCustomWidget(
                      alignment: PlaceholderAlignment.middle,
                      child: JavBusInlineEmojiImage(url: url),
                    );
                  }
                }
                return null;
              },
              onTapUrl: (url) {
                launchInExternalBrowser(url);
                return true;
              },
            ),
          ),
        ),
      ),
    );
  }
}

class JavBusPostImage extends StatelessWidget {
  const JavBusPostImage({
    super.key,
    required this.url,
    required this.maxWidth,
    required this.onOpen,
  });

  final String url;
  final double maxWidth;
  final VoidCallback onOpen;

  /// 图片请求头（含 cookie 缓存，由 ImageHeaderService 统一管理）
  static Map<String, String> get httpHeaders => ImageHeaderService.instance.headers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final previewWidth = _previewWidth(maxWidth);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: previewWidth),
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: previewWidth,
              height: _postMediaPreviewHeight,
              color: theme.colorScheme.surfaceContainerHighest,
              child: CachedNetworkImage(
                imageUrl: url,
                httpHeaders: ImageHeaderService.instance.headers,
                cacheManager: JavBusPostImageCacheManager(),
                fit: BoxFit.contain,
                placeholder: (context, url) => Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                ),
                errorWidget: (context, url, error) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.broken_image_outlined,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '图片加载失败，点击打开原图',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class JavBusImagePreviewDialog extends StatelessWidget {
  const JavBusImagePreviewDialog({super.key, required this.url});

  final String url;

  static Map<String, String> get httpHeaders => ImageHeaderService.instance.headers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semanticColors = theme.appSemanticColors;
    return Dialog.fullscreen(
      backgroundColor: semanticColors.imagePreviewBackground,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 5,
                child: Center(
                  child: CachedNetworkImage(
                    imageUrl: url,
                    httpHeaders: httpHeaders,
                    cacheManager: JavBusPostImageCacheManager(),
                    fit: BoxFit.contain,
                    placeholder: (context, url) =>
                        const SizedBox.shrink(),
                    errorWidget: (context, url, error) => Center(
                      child: Text(
                        '原图加载失败',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: semanticColors.imagePreviewForeground
                              .withValues(alpha: 0.72),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 16,
            right: 16,
            child: SafeArea(
              child: IconButton.filledTonal(
                tooltip: '关闭图片预览',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class JavBusInlineEmojiImage extends StatelessWidget {
  const JavBusInlineEmojiImage({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: url,
      httpHeaders: ImageHeaderService.instance.headers,
      cacheManager: JavBusEmojiCacheManager(),
      width: _inlineEmojiSize,
      height: _inlineEmojiSize,
      fit: BoxFit.contain,
      errorWidget: (context, url, error) =>
          const SizedBox(width: _inlineEmojiSize, height: _inlineEmojiSize),
    );
  }
}

class JavBusPostVideoPreview extends StatelessWidget {
  const JavBusPostVideoPreview({
    super.key,
    required this.url,
    required this.maxWidth,
    required this.onOpen,
  });

  final String url;
  final double maxWidth;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final previewWidth = _previewWidth(maxWidth);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: previewWidth),
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: previewWidth,
            height: _postMediaPreviewHeight,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.play_circle_outline_rounded,
                  size: 54,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 10),
                Text(
                  '视频资源，点击打开',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

double _previewWidth(double maxWidth) {
  return maxWidth.clamp(
    JavBusLayout.mediaPreviewMinWidth,
    JavBusLayout.mediaPreviewMaxWidth,
  );
}

const _postMediaPreviewHeight = JavBusLayout.mediaPreviewHeight;
const _inlineEmojiSize = JavBusLayout.inlineEmojiSize;

bool _isInlineEmojiImage(dom.Element element, String resolvedUrl) {
  final classes = element.classes.join(' ').toLowerCase();
  final rawSrc = element.attributes['src']?.toLowerCase() ?? '';
  final alt = element.attributes['alt']?.toLowerCase() ?? '';
  final combined = '$classes $rawSrc ${resolvedUrl.toLowerCase()} $alt';
  if (element.attributes.containsKey('smilieid') ||
      combined.contains('smiley') ||
      combined.contains('emoji') ||
      combined.contains('/face/') ||
      combined.contains('/faces/') ||
      combined.contains('/emoticon')) {
    return true;
  }

  final width = double.tryParse(element.attributes['width'] ?? '');
  final height = double.tryParse(element.attributes['height'] ?? '');
  if (width == null || height == null) return false;
  return width <= 48 && height <= 48;
}

class _PostAvatar extends StatelessWidget {
  const _PostAvatar({required this.avatarUrl});

  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const double size = 56;
    final url = avatarUrl;

    if (url == null || url.isEmpty) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: theme.colorScheme.primaryContainer,
        child: const Icon(Icons.person_outline_rounded, size: 28),
      );
    }

    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: url,
          httpHeaders: ImageHeaderService.instance.headers,
          cacheManager: JavBusAvatarCacheManager(),
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            color: theme.colorScheme.primaryContainer,
          ),
          errorWidget: (context, url, error) => CircleAvatar(
            radius: size / 2,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Icon(
              Icons.person_outline_rounded,
              size: 28,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
      ),
    );
  }
}

class _CommentSection extends StatefulWidget {
  const _CommentSection({required this.comments});

  final List<ForumComment> comments;

  @override
  State<_CommentSection> createState() => _CommentSectionState();
}

class _CommentSectionState extends State<_CommentSection> {
  static const int _previewCount = 10;
  bool _expanded = false;

  List<ForumComment> get _visible {
    final all = widget.comments;
    if (all.length <= _previewCount || _expanded) return all;
    return all.take(_previewCount).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final all = widget.comments;
    final visible = _visible;
    final hasMore = all.length > _previewCount;

    final baseStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurface,
      height: 1.45,
    );

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: theme.brightness == Brightness.dark ? 0.28 : 0.42,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '点评 (${all.length})',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              ...visible.map((comment) => Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: _CommentAvatar(avatarUrl: comment.avatarUrl),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  comment.author,
                                  style: baseStyle?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              if (comment.createdAt != null)
                                Text(
                                  _formatCommentTime(comment.createdAt!),
                                  style: baseStyle?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant.
                                        withValues(alpha: 0.72),
                                  ),
                                ),
                            ],
                          ),
                          Text(
                            comment.content,
                            style: baseStyle,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
              if (hasMore)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: GestureDetector(
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Text(
                      _expanded
                          ? '收起'
                          : '展开剩余 ${all.length - _previewCount} 条点评',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 点评小头像（18px，对齐 14px 文字行高）
class _CommentAvatar extends StatelessWidget {
  const _CommentAvatar({required this.avatarUrl});

  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const double size = 18;

    if (avatarUrl == null || avatarUrl!.isEmpty) {
      return Icon(
        Icons.person_outline_rounded,
        size: size,
        color: theme.colorScheme.onSurfaceVariant,
      );
    }

    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: avatarUrl!,
        httpHeaders: ImageHeaderService.instance.headers,
        cacheManager: JavBusAvatarCacheManager(),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => Icon(
          Icons.person_outline_rounded,
          size: size,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter({
    required this.hasNextPage,
    required this.isLoading,
    required this.error,
    required this.onRetry,
  });

  final bool hasNextPage;
  final bool isLoading;
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = this.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: isLoading
            ? const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : error != null
            ? OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('继续加载失败，重试'),
              )
            : Text(
                hasNextPage ? '向下滚动加载更多回复' : '没有更多回复',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
      ),
    );
  }
}
