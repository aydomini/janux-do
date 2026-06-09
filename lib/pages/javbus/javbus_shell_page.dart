import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jovial_svg/jovial_svg.dart';

import '../../forum_adapter/models/forum_forum.dart';
import '../../forum_adapter/models/forum_thread.dart';
import '../../providers/forum_provider.dart';

import '../../widgets/common/error_view.dart';
import '../../widgets/topic/topic_list_skeleton.dart';
import 'javbus_layout.dart';
import 'javbus_thread_page.dart';

class JavBusShellPage extends ConsumerStatefulWidget {
  const JavBusShellPage({super.key});

  @override
  ConsumerState<JavBusShellPage> createState() => _JavBusShellPageState();
}

class _JavBusShellPageState extends ConsumerState<JavBusShellPage> {
  ForumForum? _selectedForum;
  ForumThread? _selectedThread;
  final Map<String, _ThreadListPaneCache> _threadListCaches = {};
  final Map<int, JavBusThreadContentCache> _threadContentCaches = {};

  void _selectForum(ForumForum forum) {
    if (_selectedForum?.forumId == forum.forumId &&
        _selectedForum?.filterTypeId == forum.filterTypeId) {
      return;
    }
    setState(() {
      _selectedForum = forum;
      _selectedThread = null;
    });
  }

  void _selectThread(ForumThread thread) {
    setState(() => _selectedThread = thread);
  }

  @override
  Widget build(BuildContext context) {
    final forumsAsync = ref.watch(forumListProvider);
    return Scaffold(
      body: forumsAsync.when(
        loading: () => const TopicListSkeleton(),
        error: (error, stackTrace) => ErrorView(
          error: error,
          stackTrace: stackTrace,
          title: 'JANUX DO 加载失败',
          onRetry: () => ref.invalidate(forumListProvider),
        ),
        data: (forums) {
          if (forums.isEmpty) {
            return const _ShellEmptyState(message: '暂无可浏览版块');
          }
          final selectedForum = _selectedForum ?? forums.first;
          final listCache = _threadListCaches.putIfAbsent(
            _forumPaneKey(selectedForum),
            _ThreadListPaneCache.new,
          );
          return LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < JavBusLayout.compactBreakpoint) {
                return _CompactShell(
                  forums: forums,
                  selectedForum: selectedForum,
                  selectedThread: _selectedThread,
                  selectedForumListCache: listCache,
                  threadContentCaches: _threadContentCaches,
                  onSelectForum: _selectForum,
                  onSelectThread: _selectThread,
                  onBackToList: () => setState(() => _selectedThread = null),
                );
              }
              return _DesktopShell(
                forums: forums,
                selectedForum: selectedForum,
                selectedThread: _selectedThread,
                selectedForumListCache: listCache,
                threadContentCaches: _threadContentCaches,
                onSelectForum: _selectForum,
                onSelectThread: _selectThread,
                onBackToList: () => setState(() => _selectedThread = null),
              );
            },
          );
        },
      ),
    );
  }
}

class _DesktopShell extends StatelessWidget {
  const _DesktopShell({
    required this.forums,
    required this.selectedForum,
    required this.selectedThread,
    required this.selectedForumListCache,
    required this.threadContentCaches,
    required this.onSelectForum,
    required this.onSelectThread,
    required this.onBackToList,
  });

  final List<ForumForum> forums;
  final ForumForum selectedForum;
  final ForumThread? selectedThread;
  final _ThreadListPaneCache selectedForumListCache;
  final Map<int, JavBusThreadContentCache> threadContentCaches;
  final ValueChanged<ForumForum> onSelectForum;
  final ValueChanged<ForumThread> onSelectThread;
  final VoidCallback onBackToList;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: JavBusLayout.sidebarWidth,
          child: _ForumSidebar(
            forums: forums,
            selectedForum: selectedForum,
            onSelectForum: onSelectForum,
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: IndexedStack(
            index: selectedThread == null ? 0 : 1,
            children: [
              _ThreadListPane(
                key: ValueKey(_forumPaneKey(selectedForum)),
                forum: selectedForum,
                cache: selectedForumListCache,
                onSelectThread: onSelectThread,
              ),
              if (selectedThread == null)
                const SizedBox.shrink()
              else
                _ThreadReaderPane(
                  key: ValueKey('reader-${selectedThread!.threadId}'),
                  thread: selectedThread!,
                  cache: threadContentCaches.putIfAbsent(
                    selectedThread!.threadId,
                    JavBusThreadContentCache.new,
                  ),
                  onBackToList: onBackToList,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CompactShell extends StatelessWidget {
  const _CompactShell({
    required this.forums,
    required this.selectedForum,
    required this.selectedThread,
    required this.selectedForumListCache,
    required this.threadContentCaches,
    required this.onSelectForum,
    required this.onSelectThread,
    required this.onBackToList,
  });

  final List<ForumForum> forums;
  final ForumForum selectedForum;
  final ForumThread? selectedThread;
  final _ThreadListPaneCache selectedForumListCache;
  final Map<int, JavBusThreadContentCache> threadContentCaches;
  final ValueChanged<ForumForum> onSelectForum;
  final ValueChanged<ForumThread> onSelectThread;
  final VoidCallback onBackToList;

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: selectedThread == null ? 0 : 1,
      children: [
        Column(
          children: [
            SizedBox(
              height: 132,
              child: _CompactForumBar(
                forums: forums,
                selectedForum: selectedForum,
                onSelectForum: onSelectForum,
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _ThreadListPane(
                key: ValueKey(_forumPaneKey(selectedForum)),
                forum: selectedForum,
                cache: selectedForumListCache,
                onSelectThread: onSelectThread,
              ),
            ),
          ],
        ),
        if (selectedThread == null)
          const SizedBox.shrink()
        else
          _ThreadReaderPane(
            key: ValueKey('compact-reader-${selectedThread!.threadId}'),
            thread: selectedThread!,
            cache: threadContentCaches.putIfAbsent(
              selectedThread!.threadId,
              JavBusThreadContentCache.new,
            ),
            onBackToList: onBackToList,
          ),
      ],
    );
  }
}

class _ForumSidebar extends StatelessWidget {
  const _ForumSidebar({
    required this.forums,
    required this.selectedForum,
    required this.onSelectForum,
  });

  final List<ForumForum> forums;
  final ForumForum selectedForum;
  final ValueChanged<ForumForum> onSelectForum;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(color: theme.colorScheme.surface),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 20, 18),
              child: Row(
                children: [
                  ClipOval(
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: ScalableImageWidget.fromSISource(
                        si: ScalableImageSource.fromSvg(
                          DefaultAssetBundle.of(context),
                          'assets/logo.svg',
                        ),
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'JANUX DO',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.fromLTRB(58, 0, 14, 0),
              child: Text(
                '分区',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
                itemCount: forums.length,
                itemBuilder: (context, index) {
                  final forum = forums[index];
                  return _ForumNavItem(
                    forum: forum,
                    selected: _sameForum(forum, selectedForum),
                    onTap: () => onSelectForum(forum),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactForumBar extends StatelessWidget {
  const _CompactForumBar({
    required this.forums,
    required this.selectedForum,
    required this.onSelectForum,
  });

  final List<ForumForum> forums;
  final ForumForum selectedForum;
  final ValueChanged<ForumForum> onSelectForum;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        scrollDirection: Axis.horizontal,
        itemCount: forums.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final forum = forums[index];
          return ChoiceChip(
            label: Text(forum.name),
            selected: _sameForum(forum, selectedForum),
            onSelected: (_) => onSelectForum(forum),
          );
        },
      ),
    );
  }
}

class _ForumNavItem extends StatelessWidget {
  const _ForumNavItem({
    required this.forum,
    required this.selected,
    required this.onTap,
  });

  final ForumForum forum;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = _forumSubtitle(forum);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: selected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.68)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  _forumIcon(forum),
                  size: 20,
                  color: selected
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        forum.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
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

class _ThreadListPane extends ConsumerStatefulWidget {
  const _ThreadListPane({
    super.key,
    required this.forum,
    required this.cache,
    required this.onSelectThread,
  });

  final ForumForum forum;
  final _ThreadListPaneCache cache;
  final ValueChanged<ForumThread> onSelectThread;

  @override
  ConsumerState<_ThreadListPane> createState() => _ThreadListPaneState();
}

class _ThreadListPaneState extends ConsumerState<_ThreadListPane> {
  final ScrollController _scrollController = ScrollController();
  final List<ForumThread> _threads = [];
  int _currentPage = 1;
  int _totalPages = 1;
  bool _hasNextPage = true;
  bool _isLoadingInitial = true;
  bool _isLoadingMore = false;
  Object? _error;
  StackTrace? _stackTrace;
  final Map<int, int> _viewCounts = {};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _restoreFromCache();
    if (_isLoadingInitial) {
      Future.microtask(_refreshThreads);
    } else {
      _restoreScrollOffset();
    }
  }

  @override
  void didUpdateWidget(covariant _ThreadListPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameForum(oldWidget.forum, widget.forum)) {
      _threads.clear();
      _currentPage = 1;
      _totalPages = 1;
      _hasNextPage = true;
      _isLoadingInitial = true;
      _isLoadingMore = false;
      _error = null;
      _stackTrace = null;
      Future.microtask(_refreshThreads);
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
    widget.cache.scrollOffset = position.pixels;
    if (position.extentAfter > 680) return;
    _loadNextPage();
  }

  void _restoreFromCache() {
    if (!widget.cache.hasLoaded) return;
    _threads
      ..clear()
      ..addAll(widget.cache.threads);
    _viewCounts
      ..clear()
      ..addAll(widget.cache.viewCounts);
    _currentPage = widget.cache.currentPage;
    _totalPages = widget.cache.totalPages;
    _hasNextPage = widget.cache.hasNextPage;
    _isLoadingInitial = false;
    _isLoadingMore = false;
    _error = null;
    _stackTrace = null;
  }

  void _restoreScrollOffset() {
    final offset = widget.cache.scrollOffset;
    if (offset <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final maxOffset = _scrollController.position.maxScrollExtent;
      _scrollController.jumpTo(offset.clamp(0, maxOffset));
    });
  }

  void _saveCache() {
    widget.cache.threads
      ..clear()
      ..addAll(_threads);
    widget.cache.viewCounts
      ..clear()
      ..addAll(_viewCounts);
    widget.cache
      ..currentPage = _currentPage
      ..totalPages = _totalPages
      ..hasNextPage = _hasNextPage
      ..hasLoaded = !_isLoadingInitial && _threads.isNotEmpty;
    if (_scrollController.hasClients) {
      widget.cache.scrollOffset = _scrollController.position.pixels;
    }
  }

  Future<void> _refreshThreads() async {
    setState(() {
      _isLoadingInitial = true;
      _isLoadingMore = false;
      _error = null;
      _stackTrace = null;
    });
    try {
      final result = await ref.read(forumAdapterProvider).getThreads(
        forumId: widget.forum.forumId,
        filterTypeId: widget.forum.filterTypeId,
      );
      if (!mounted) return;
      setState(() {
        _threads
          ..clear()
          ..addAll(result.threads);
        _viewCounts
          ..clear()
          ..addAll(result.viewCounts ?? const {});
        _currentPage = result.currentPage;
        _totalPages = result.totalPages;
        _hasNextPage = result.hasNextPage;
        _isLoadingInitial = false;
        widget.cache.scrollOffset = 0;
        _saveCache();
      });
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
    setState(() => _isLoadingMore = true);
    try {
      final result = await ref.read(forumAdapterProvider).getThreads(
        forumId: widget.forum.forumId,
        filterTypeId: widget.forum.filterTypeId,
        page: requestedPage,
      );
      if (!mounted) return;
      setState(() {
        _threads.addAll(result.threads);
        _viewCounts.addAll(result.viewCounts ?? const {});
        _currentPage = result.currentPage < requestedPage
            ? requestedPage
            : result.currentPage;
        _totalPages = result.totalPages;
        _hasNextPage = result.hasNextPage;
        _isLoadingMore = false;
        _error = null;
        _stackTrace = null;
        _saveCache();
      });
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _stackTrace = stackTrace;
        _isLoadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ThreadListHeader(forum: widget.forum, onRefresh: _refreshThreads),
        const Divider(height: 1),
        Expanded(
          child: error != null && _threads.isEmpty
              ? ErrorView(
                  error: error,
                  stackTrace: _stackTrace,
                  title: '帖子列表加载失败',
                  onRetry: _refreshThreads,
                )
              : _isLoadingInitial
              ? const TopicListSkeleton()
              : _threads.isEmpty
              ? const _ShellEmptyState(message: '暂无帖子')
              : Column(
                  children: [
                    const _ThreadTableHeader(),
                    const Divider(height: 1),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _refreshThreads,
                        child: ListView.separated(
                          controller: _scrollController,
                          padding: JavBusLayout.listPadding,
                          itemCount: _threads.length + 1,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            if (index == _threads.length) {
                              return _ThreadListFooter(
                                currentPage: _currentPage,
                                totalPages: _totalPages,
                                hasNextPage: _hasNextPage,
                                isLoading: _isLoadingMore,
                                error: _threads.isEmpty ? null : _error,
                                onRetry: _loadNextPage,
                              );
                            }
                            final thread = _threads[index];
                            return _ThreadRow(
                              thread: thread,
                              onTap: () => widget.onSelectThread(thread),
                              views: _viewCounts[thread.threadId] ?? thread.views,
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _ThreadListPaneCache {
  final List<ForumThread> threads = [];
  final Map<int, int> viewCounts = {};
  int currentPage = 1;
  int totalPages = 1;
  bool hasNextPage = true;
  bool hasLoaded = false;
  double scrollOffset = 0;
}

class _ThreadListHeader extends StatelessWidget {
  const _ThreadListHeader({required this.forum, required this.onRefresh});

  final ForumForum forum;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 22, 24, 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    forum.name,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    forum.description?.trim().isNotEmpty == true
                        ? forum.description!.trim()
                        : '话题',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '刷新',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThreadTableHeader extends StatelessWidget {
  const _ThreadTableHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        JavBusLayout.listHorizontalPadding,
        14,
        JavBusLayout.listHorizontalPadding,
        14,
      ),
      child: Row(
        children: [
          const SizedBox(width: 28),
          Expanded(child: Text('话题', style: labelStyle)),
          const SizedBox(width: 18),
          SizedBox(
            width: JavBusLayout.topicViewsColumnWidth,
            child: Text('浏览', textAlign: TextAlign.center, style: labelStyle),
          ),
          const SizedBox(width: 18),
          SizedBox(
            width: JavBusLayout.topicReplyColumnWidth,
            child: Text('回复', textAlign: TextAlign.center, style: labelStyle),
          ),
          const SizedBox(width: 24),
          SizedBox(
            width: JavBusLayout.topicTimeColumnWidth,
            child: Text('时间', textAlign: TextAlign.center, style: labelStyle),
          ),
        ],
      ),
    );
  }
}

class _ThreadRow extends StatelessWidget {
  const _ThreadRow({
    required this.thread,
    required this.onTap,
    this.views = 0,
  });

  final ForumThread thread;
  final VoidCallback onTap;
  final int views;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 28,
              child: Icon(
                thread.isPinned
                    ? Icons.push_pin_rounded
                    : thread.hasAttachment
                    ? Icons.attach_file_rounded
                    : Icons.chat_bubble_outline_rounded,
                size: 18,
                color: thread.isPinned
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    thread.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      _MutedMeta(
                        icon: Icons.person_outline_rounded,
                        label: thread.author,
                      ),
                      if (thread.isPinned) const _SmallBadge(label: '置顶'),
                      if (thread.isDigest) const _SmallBadge(label: '精华'),
                      if (thread.hasAttachment) const _SmallBadge(label: '附件'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 18),
            SizedBox(
              width: JavBusLayout.topicViewsColumnWidth,
              child: Text(
                _formatCount(views),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 18),
            SizedBox(
              width: JavBusLayout.topicReplyColumnWidth,
              child: Text(
                _formatCount(thread.replies),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 24),
            SizedBox(
              width: JavBusLayout.topicTimeColumnWidth,
              child: Text(
                _formatThreadTime(thread.createdAt),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThreadReaderPane extends StatelessWidget {
  const _ThreadReaderPane({
    super.key,
    required this.thread,
    required this.cache,
    required this.onBackToList,
  });

  final ForumThread thread;
  final JavBusThreadContentCache cache;
  final VoidCallback onBackToList;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 24, 12),
            child: Row(
              children: [
                IconButton(
                  tooltip: '返回话题列表',
                  onPressed: onBackToList,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    thread.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: JavBusThreadContent(
            key: ValueKey('shell-thread-${thread.threadId}'),
            threadId: thread.threadId,
            initialTitle: thread.title,
            cache: cache,
          ),
        ),
      ],
    );
  }
}

class _MutedMeta extends StatelessWidget {
  const _MutedMeta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _SmallBadge extends StatelessWidget {
  const _SmallBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _ThreadListFooter extends StatelessWidget {
  const _ThreadListFooter({
    required this.currentPage,
    required this.totalPages,
    required this.hasNextPage,
    required this.isLoading,
    required this.error,
    required this.onRetry,
  });

  final int currentPage;
  final int totalPages;
  final bool hasNextPage;
  final bool isLoading;
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = this.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
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
                hasNextPage
                    ? '继续向下滚动加载更多 · $currentPage / $totalPages'
                    : '已加载全部帖子',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
      ),
    );
  }
}

class _ShellEmptyState extends StatelessWidget {
  const _ShellEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Text(
        message,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

bool _sameForum(ForumForum a, ForumForum b) {
  return a.forumId == b.forumId && a.filterTypeId == b.filterTypeId;
}

String _forumPaneKey(ForumForum forum) {
  return 'forum-${forum.forumId}-${forum.filterTypeId ?? 'all'}';
}

IconData _forumIcon(ForumForum forum) {
  if (forum.filterTypeId != null) return Icons.sell_outlined;
  return Icons.layers_rounded;
}

String _forumSubtitle(ForumForum forum) {
  final parts = <String>[
    if (forum.threadCount > 0) '${forum.threadCount} 主题',
    if (forum.todayPostCount > 0) '今日 ${forum.todayPostCount}',
  ];
  if (parts.isNotEmpty) return parts.join(' · ');
  return forum.description?.trim() ?? '';
}

String _formatCount(int value) {
  if (value <= 0) return '-';
  if (value >= 10000) return '${(value / 10000).toStringAsFixed(1)}万';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
  return '$value';
}

String _formatThreadTime(DateTime? value) {
  if (value == null) return '';
  final now = DateTime.now();
  final diff = now.difference(value);

  // 1周内使用相对时间
  if (diff.inDays < 7) {
    if (diff.inSeconds < 60) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    return '${diff.inDays}天前';
  }

  // 超过1周显示日期
  String two(int input) => input.toString().padLeft(2, '0');
  return value.year == now.year
      ? '${two(value.month)} 月 ${two(value.day)} 日'
      : '${value.year} 年 ${two(value.month)} 月 ${two(value.day)} 日';
}

