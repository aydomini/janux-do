import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../forum_adapter/models/forum_thread.dart';
import '../../providers/forum_provider.dart';
import '../../widgets/common/error_view.dart';
import 'javbus_layout.dart';
import 'javbus_thread_page.dart';
import 'javbus_thread_row.dart';

/// 搜索面板状态缓存
///
/// 由 shell 持有，切换分区后恢复搜索结果和滚动位置。
class SearchPaneCache {
  final List<ForumThread> threads = [];
  int currentPage = 1;
  int totalPages = 1;
  int totalResults = 0;
  bool hasNextPage = false;
  String? lastKeyword;
  int? searchId;
  double scrollOffset = 0;
  bool hasLoaded = false;
}

/// 搜索历史管理
class SearchHistory {
  static const _key = 'search_history';
  static const _maxItems = 10;

  static Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.cast<String>();
    } catch (_) {
      return [];
    }
  }

  static Future<void> add(String keyword) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final history = await load();
    history.remove(trimmed);
    history.insert(0, trimmed);
    if (history.length > _maxItems) {
      history.removeRange(_maxItems, history.length);
    }
    await prefs.setString(_key, jsonEncode(history));
  }

  static Future<void> remove(String keyword) async {
    final prefs = await SharedPreferences.getInstance();
    final history = await load();
    history.remove(keyword.trim());
    await prefs.setString(_key, jsonEncode(history));
  }
}

/// 论坛搜索面板
///
/// 嵌入 shell 右侧面板使用。支持：
/// - 搜索结果缓存（切换分区后恢复状态）
/// - 搜索历史（最近 10 条，SharedPreferences 持久化）
/// - 无限滚动翻页 + 60 秒搜索频率限制
class JavBusSearchPage extends ConsumerStatefulWidget {
  const JavBusSearchPage({
    super.key,
    required this.cache,
    this.onSelectThread,
  });

  final SearchPaneCache cache;

  /// 选中帖子回调（由 shell 提供，在右侧面板内联显示详情而非全屏导航）
  final ValueChanged<ForumThread>? onSelectThread;

  @override
  ConsumerState<JavBusSearchPage> createState() => _JavBusSearchPageState();
}

class _JavBusSearchPageState extends ConsumerState<JavBusSearchPage> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  List<ForumThread> _threads = [];
  int _currentPage = 1;
  int _totalPages = 1;
  int _totalResults = 0;
  bool _hasNextPage = false;
  bool _isSearching = false;
  bool _isLoadingMore = false;
  Object? _error;
  String? _lastKeyword;
  int? _searchId;
  int _cooldownSeconds = 0;

  /// 搜索历史列表
  List<String> _searchHistory = [];

  SearchPaneCache get _cache => widget.cache;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _restoreFromCache();
    _loadHistory();
    if (!_cache.hasLoaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _searchFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    _saveToCache();
    super.dispose();
  }

  void _restoreFromCache() {
    if (!_cache.hasLoaded) return;
    _threads = List.of(_cache.threads);
    _currentPage = _cache.currentPage;
    _totalPages = _cache.totalPages;
    _totalResults = _cache.totalResults;
    _hasNextPage = _cache.hasNextPage;
    _lastKeyword = _cache.lastKeyword;
    _searchId = _cache.searchId;
    if (_lastKeyword != null) {
      _searchController.text = _lastKeyword!;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final maxOffset = _scrollController.position.maxScrollExtent;
      if (maxOffset > 0) {
        _scrollController.jumpTo(
          _cache.scrollOffset.clamp(0, maxOffset),
        );
      }
    });
  }

  void _saveToCache() {
    _cache.threads
      ..clear()
      ..addAll(_threads);
    _cache
      ..currentPage = _currentPage
      ..totalPages = _totalPages
      ..totalResults = _totalResults
      ..hasNextPage = _hasNextPage
      ..lastKeyword = _lastKeyword
      ..searchId = _searchId
      ..hasLoaded = _lastKeyword != null;
    if (_scrollController.hasClients) {
      _cache.scrollOffset = _scrollController.position.pixels;
    }
  }

  Future<void> _loadHistory() async {
    _searchHistory = await SearchHistory.load();
    if (mounted) setState(() {});
  }

  /// 清空搜索结果，回到搜索历史初始状态
  void _clearSearch() {
    _searchController.clear();
    _searchFocus.requestFocus();
    setState(() {
      _threads.clear();
      _currentPage = 1;
      _totalPages = 1;
      _totalResults = 0;
      _hasNextPage = false;
      _error = null;
      _lastKeyword = null;
      _searchId = null;
    });
    // 同步清空缓存，避免切换分区后恢复旧结果
    widget.cache
      ..hasLoaded = false
      ..lastKeyword = null
      ..threads.clear();
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter > 680) return;
    _loadNextPage();
  }

  void _startCooldown() {
    _cooldownSeconds = 60;
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _cooldownSeconds = (_cooldownSeconds - 1).clamp(0, 60));
      return _cooldownSeconds > 0;
    });
  }

  Future<void> _doSearch({String? keyword}) async {
    final kw = (keyword ?? _searchController.text).trim();
    if (kw.isEmpty || _cooldownSeconds > 0) return;

    // 更新搜索框文本（历史项点击时可能不一致）
    if (keyword != null) {
      _searchController.text = kw;
    }

    setState(() {
      _isSearching = true;
      _error = null;
      _threads.clear();
      _currentPage = 1;
      _totalPages = 1;
      _totalResults = 0;
      _hasNextPage = false;
      _lastKeyword = kw;
      _searchId = null;
    });

    try {
      final result = await ref.read(forumAdapterProvider).search(kw);
      if (!mounted) return;
      // 添加到搜索历史
      await SearchHistory.add(kw);
      _searchHistory = await SearchHistory.load();
      setState(() {
        _threads.addAll(result.threads);
        _currentPage = result.currentPage;
        _totalPages = result.totalPages;
        _totalResults = result.totalResults;
        _hasNextPage = result.hasNextPage;
        _searchId = result.searchId;
        _isSearching = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _isSearching = false;
      });
      if (error.toString().contains('60 秒')) {
        _startCooldown();
      }
    }
  }

  Future<void> _loadNextPage() async {
    if (_isSearching || _isLoadingMore || !_hasNextPage) return;
    if (_searchId == null || _lastKeyword == null) return;

    final requestedPage = _currentPage + 1;
    setState(() => _isLoadingMore = true);

    try {
      final result = await ref.read(forumAdapterProvider).search(
        _lastKeyword!,
        searchId: _searchId,
        page: requestedPage,
      );
      if (!mounted) return;
      setState(() {
        _threads.addAll(result.threads);
        _currentPage = result.currentPage < requestedPage
            ? requestedPage
            : result.currentPage;
        _totalPages = result.totalPages;
        _hasNextPage = result.hasNextPage;
        _isLoadingMore = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _isLoadingMore = false;
      });
    }
  }

  void _openThread(ForumThread thread) {
    final onSelectThread = widget.onSelectThread;
    if (onSelectThread != null) {
      // shell 模式：在右侧面板内联显示详情，保留侧边栏
      onSelectThread(thread);
    } else {
      // 独立页面模式（兼容没有 shell 的场景）
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => JavBusThreadPage(
            threadId: thread.threadId,
            initialTitle: thread.title,
            fullThread: thread,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasResults = _threads.isNotEmpty;
    final showEmpty = !_isSearching && _lastKeyword != null && !hasResults;
    final showHistory = !hasResults &&
        !showEmpty &&
        !_isSearching &&
        _searchHistory.isNotEmpty &&
        _searchController.text.isEmpty &&
        _searchFocus.hasFocus;
    final isInitial = !showHistory && !hasResults && !showEmpty && !_isSearching;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            JavBusLayout.listHorizontalPadding,
            24,
            JavBusLayout.listHorizontalPadding,
            16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SearchBar(
                controller: _searchController,
                focusNode: _searchFocus,
                cooldownSeconds: _cooldownSeconds,
                isSearching: _isSearching,
                onSubmit: () => _doSearch(),
                onClear: _clearSearch,
              ),
              if (showHistory)
                Row(
                  children: [
                    Expanded(
                      child: _SearchHistoryDropdown(
                        items: _searchHistory,
                        onTap: (kw) => _doSearch(keyword: kw),
                        onDelete: (kw) async {
                          await SearchHistory.remove(kw);
                          _searchHistory = await SearchHistory.load();
                          if (mounted) setState(() {});
                        },
                      ),
                    ),
                    // 对齐搜索框右侧的间距(14px) + 搜索按钮(40px)
                    const SizedBox(width: 54),
                  ],
                ),
            ],
          ),
        ),
        if (!showHistory && !isInitial) ...[
          const Divider(height: 1),
          if (_totalResults > 0)
            _ResultsStats(
              keyword: _lastKeyword ?? '',
              totalResults: _totalResults,
              currentPage: _currentPage,
              totalPages: _totalPages,
            ),
          Expanded(
            child: _isSearching
                ? const Center(child: CircularProgressIndicator())
                : _error != null && !hasResults
                    ? ErrorView(
                        error: _error!,
                        title: '搜索失败',
                        onRetry: () => _doSearch(),
                      )
                    : showEmpty
                        ? const _EmptySearchResult()
                        : hasResults
                            ? Column(
                                children: [
                                  const ThreadTableHeader(),
                                  const Divider(height: 1),
                                  Expanded(
                                    child: ListView.separated(
                                      controller: _scrollController,
                                      padding: JavBusLayout.listPadding,
                                      itemCount: _threads.length + 1,
                                      separatorBuilder: (_, _) =>
                                          const Divider(height: 1),
                                      itemBuilder: (context, index) {
                                        if (index == _threads.length) {
                                          return _SearchListFooter(
                                            currentPage: _currentPage,
                                            totalPages: _totalPages,
                                            hasNextPage: _hasNextPage,
                                            isLoading: _isLoadingMore,
                                            error: _error,
                                            onRetry: _loadNextPage,
                                          );
                                        }
                                        final thread = _threads[index];
                                        return ThreadRow(
                                          thread: thread,
                                          isSearchResult: true,
                                          views: thread.views,
                                          onTap: () => _openThread(thread),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              )
                            : const SizedBox.shrink(),
          ),
        ],
        if (isInitial) const Expanded(child: SizedBox.shrink()),
      ],
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.cooldownSeconds,
    required this.isSearching,
    required this.onSubmit,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final int cooldownSeconds;
  final bool isSearching;
  final VoidCallback onSubmit;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSearch = !isSearching && cooldownSeconds == 0;

    return Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => onSubmit(),
              decoration: InputDecoration(
                hintText: '搜索论坛帖子…',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        tooltip: '清空搜索结果',
                        onPressed: () {
                          controller.clear();
                          onClear();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          cooldownSeconds > 0
              ? SizedBox(
                  width: 64,
                  child: Text(
                    '${cooldownSeconds}s',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              : isSearching
                  ? const SizedBox(
                      width: 40,
                      height: 40,
                      child: Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton.filled(
                      tooltip: '搜索',
                      onPressed: canSearch ? onSubmit : null,
                      icon: const Icon(Icons.search_rounded),
                    ),
        ],
      );
  }
}

/// 搜索历史下拉建议（紧凑卡片，匹配搜索框宽度）
class _SearchHistoryDropdown extends StatelessWidget {
  const _SearchHistoryDropdown({
    required this.items,
    required this.onTap,
    required this.onDelete,
  });

  final List<String> items;
  final void Function(String keyword) onTap;
  final void Function(String keyword) onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
        elevation: 3,
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(12),
        ),
        color: theme.colorScheme.surface,
        surfaceTintColor: theme.colorScheme.surfaceTint,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(12),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: items.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, indent: 48, color: theme.dividerColor),
              itemBuilder: (context, index) {
                final keyword = items[index];
                return ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: Icon(
                    Icons.history_rounded,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  title: Text(
                    keyword,
                    style: theme.textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close_rounded, size: 16),
                    onPressed: () => onDelete(keyword),
                    tooltip: '删除',
                    visualDensity: VisualDensity.compact,
                  ),
                  onTap: () => onTap(keyword),
                );
              },
            ),
          ),
        ),
      );
  }
}

class _ResultsStats extends StatelessWidget {
  const _ResultsStats({
    required this.keyword,
    required this.totalResults,
    required this.currentPage,
    required this.totalPages,
  });

  final String keyword;
  final int totalResults;
  final int currentPage;
  final int totalPages;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        JavBusLayout.listHorizontalPadding,
        10,
        JavBusLayout.listHorizontalPadding,
        8,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '找到 $totalResults 条与「$keyword」相关的内容',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            '$currentPage / $totalPages',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptySearchResult extends StatelessWidget {
  const _EmptySearchResult();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant.withAlpha(128),
          ),
          const SizedBox(height: 12),
          Text(
            '没有找到匹配结果',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchListFooter extends StatelessWidget {
  const _SearchListFooter({
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
                        : '已加载全部结果',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
      ),
    );
  }
}
