import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../forum_adapter/models/forum_thread.dart';
import '../../providers/forum_provider.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/topic/topic_list_skeleton.dart';
import 'javbus_thread_page.dart';

class JavBusForumPage extends ConsumerStatefulWidget {
  const JavBusForumPage({
    super.key,
    required this.forumId,
    required this.forumName,
    this.filterTypeId,
  });

  final int forumId;
  final String forumName;
  final int? filterTypeId;

  @override
  ConsumerState<JavBusForumPage> createState() => _JavBusForumPageState();
}

class _JavBusForumPageState extends ConsumerState<JavBusForumPage> {
  final ScrollController _scrollController = ScrollController();
  final List<ForumThread> _threads = [];
  int _currentPage = 1;
  int _totalPages = 1;
  bool _hasNextPage = true;
  bool _isLoadingInitial = true;
  bool _isLoadingMore = false;
  Object? _error;
  StackTrace? _stackTrace;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    Future.microtask(_refreshThreads);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final position = _scrollController.position;
    if (position.extentAfter > 600) return;
    _loadNextPage();
  }

  Future<void> _refreshThreads() async {
    setState(() {
      _isLoadingInitial = true;
      _isLoadingMore = false;
      _error = null;
      _stackTrace = null;
    });
    try {
      final result = await ref
          .read(forumAdapterProvider)
          .getThreads(
            forumId: widget.forumId,
            filterTypeId: widget.filterTypeId,
          );
      if (!mounted) return;
      setState(() {
        _threads
          ..clear()
          ..addAll(result.threads);
        _currentPage = result.currentPage;
        _totalPages = result.totalPages;
        _hasNextPage = result.hasNextPage;
        _isLoadingInitial = false;
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
    setState(() => _isLoadingMore = true);
    try {
      final result = await ref
          .read(forumAdapterProvider)
          .getThreads(
            forumId: widget.forumId,
            filterTypeId: widget.filterTypeId,
            page: _currentPage + 1,
          );
      if (!mounted) return;
      setState(() {
        _threads.addAll(result.threads);
        _currentPage = result.currentPage;
        _totalPages = result.totalPages;
        _hasNextPage = result.hasNextPage;
        _isLoadingMore = false;
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.forumName),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refreshThreads,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final error = _error;
    if (error != null && _threads.isEmpty) {
      return ErrorView(
        error: error,
        stackTrace: _stackTrace,
        title: '帖子列表加载失败',
        onRetry: _refreshThreads,
      );
    }
    if (_isLoadingInitial) {
      return const TopicListSkeleton();
    }
    if (_threads.isEmpty) {
      return const _ForumEmptyState();
    }
    return RefreshIndicator(
      onRefresh: _refreshThreads,
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
        itemCount: _threads.length + 1,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index == _threads.length) {
            return _LoadMoreFooter(
              currentPage: _currentPage,
              totalPages: _totalPages,
              hasNextPage: _hasNextPage,
              isLoading: _isLoadingMore,
              error: _threads.isEmpty ? null : _error,
              onRetry: _loadNextPage,
            );
          }
          return _ThreadCard(thread: _threads[index]);
        },
      ),
    );
  }
}

class _ThreadCard extends StatelessWidget {
  const _ThreadCard({required this.thread});

  final ForumThread thread;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => JavBusThreadPage(
                threadId: thread.threadId,
                initialTitle: thread.title,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      thread.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (thread.isPinned) const _Badge(label: '置顶'),
                  if (thread.isDigest) const _Badge(label: '精华'),
                ],
              ),
              if (thread.excerpt?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 6),
                Text(
                  thread.excerpt!.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _Meta(
                    icon: Icons.person_outline_rounded,
                    label: thread.author,
                  ),
                  if (thread.createdAt != null)
                    _Meta(
                      icon: Icons.schedule_rounded,
                      label: _formatThreadDateTime(thread.createdAt!),
                    ),
                  _Meta(
                    icon: Icons.forum_outlined,
                    label: '${thread.replies} 回复',
                  ),
                  if (thread.hasAttachment)
                    const _Meta(icon: Icons.attach_file_rounded, label: '附件'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});

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
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSecondaryContainer,
          ),
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter({
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
                hasNextPage
                    ? '继续向下滚动加载更多 · $currentPage / $totalPages'
                    : '已加载全部帖子',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
      ),
    );
  }
}

class _ForumEmptyState extends StatelessWidget {
  const _ForumEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Text(
        '暂无帖子',
        style: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

String _formatThreadDateTime(DateTime value) {
  String two(int input) => input.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}
