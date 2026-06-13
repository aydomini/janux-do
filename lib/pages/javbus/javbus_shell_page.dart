import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jovial_svg/jovial_svg.dart';

import '../../forum_adapter/adapter.dart';
import '../../forum_adapter/models/forum_forum.dart';
import '../../forum_adapter/models/forum_thread.dart';
import '../../providers/connectivity_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/forum_provider.dart';
import '../../services/forum_cache_service.dart';

import '../../widgets/common/error_view.dart';
import '../../widgets/topic/topic_list_skeleton.dart';
import 'javbus_layout.dart';
import 'javbus_search_page.dart';
import 'javbus_thread_page.dart';
import 'javbus_thread_row.dart';

class JavBusShellPage extends ConsumerStatefulWidget {
  const JavBusShellPage({super.key});

  @override
  ConsumerState<JavBusShellPage> createState() => _JavBusShellPageState();
}

class _JavBusShellPageState extends ConsumerState<JavBusShellPage> {
  ForumForum? _selectedForum;
  ForumThread? _selectedThread;
  bool _isSearchMode = false;
  bool _isFavoritesMode = false;
  /// 进入帖子详情前是否处于收藏模式，返回时用于恢复收藏面板
  bool _wasInFavoritesMode = false;
  /// 进入帖子详情前是否处于搜索模式，返回时用于恢复搜索结果
  bool _wasInSearchMode = false;
  final Map<String, _ThreadListPaneCache> _threadListCaches = {};
  final Map<int, JavBusThreadContentCache> _threadContentCaches = {};
  SearchPaneCache? _searchCache;

  void _selectForum(ForumForum forum) {
    setState(() {
      // 搜索/收藏模式下点击分区总是切换选中（用户明确意图），不执行取消逻辑
      final isSpecialMode = _isSearchMode || _isFavoritesMode;
      if (!isSpecialMode && _sameForum(_selectedForum, forum)) {
        _selectedForum = null;
      } else {
        _selectedForum = forum;
      }
      _selectedThread = null;
      _isSearchMode = false;
      _isFavoritesMode = false;
    });
  }

  void _enterSearchMode() {
    setState(() {
      _isSearchMode = true;
      _isFavoritesMode = false;
      _selectedThread = null;
      _searchCache ??= SearchPaneCache();
    });
  }

  void _exitSearchMode() {
    setState(() => _isSearchMode = false);
  }

  void _enterFavoritesMode() {
    setState(() {
      _isFavoritesMode = true;
      _isSearchMode = false;
      _selectedThread = null;
    });
  }

  void _exitFavoritesMode() {
    setState(() => _isFavoritesMode = false);
  }

  void _toggleSearchMode() {
    if (_isSearchMode) {
      _exitSearchMode();
    } else {
      _enterSearchMode();
    }
  }

  void _toggleFavoritesMode() {
    if (_isFavoritesMode) {
      _exitFavoritesMode();
    } else {
      _enterFavoritesMode();
    }
  }

  void _selectThread(ForumThread thread) {
    setState(() {
      _wasInFavoritesMode = _isFavoritesMode;
      _wasInSearchMode = _isSearchMode;
      _selectedThread = thread;
      // 从搜索或收藏模式中选中帖子 → 退出特殊模式，在右侧面板显示详情
      _isSearchMode = false;
      _isFavoritesMode = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 监听网络恢复：macOS 重启后 WiFi 就绪时自动重新加载论坛列表
    ref.listen(isConnectedProvider, (prev, next) {
      final wasDisconnected = prev is AsyncData<bool> && prev.value == false;
      final isNowConnected = next is AsyncData<bool> && next.value == true;
      if (wasDisconnected && isNowConnected) {
        ref.read(forumListProvider.notifier).refresh();
      }
    });

    final forumsAsync = ref.watch(forumListProvider);

    // 收藏模式独立于论坛数据加载状态，即使网络异常也能查看收藏
    if (_isFavoritesMode) {
      return Scaffold(
        body: forumsAsync.when(
          loading: () => _FavoritesShell(
            forums: ForumCacheService.instance.cached,
            isFavoritesMode: true,
            onToggleSearch: _toggleSearchMode,
            onToggleFavorites: _toggleFavoritesMode,
            onExitFavorites: _exitFavoritesMode,
            onSelectForum: _selectForum,
            onSelectThread: _selectThread,
          ),
          error: (_, _) => _FavoritesShell(
            forums: ForumCacheService.instance.cached,
            isFavoritesMode: true,
            onToggleSearch: _toggleSearchMode,
            onToggleFavorites: _toggleFavoritesMode,
            onExitFavorites: _exitFavoritesMode,
            onSelectForum: _selectForum,
            onSelectThread: _selectThread,
          ),
          data: (forums) => _FavoritesShell(
            forums: forums,
            isFavoritesMode: true,
            onToggleSearch: _toggleSearchMode,
            onToggleFavorites: _toggleFavoritesMode,
            onExitFavorites: _exitFavoritesMode,
            onSelectForum: _selectForum,
            onSelectThread: _selectThread,
          ),
        ),
      );
    }

    // 搜索模式：有缓存数据即可显示侧边栏
    if (_isSearchMode) {
      final sidebarForums = forumsAsync.asData?.value ?? ForumCacheService.instance.cached;
      return Scaffold(
        body: Row(
          children: [
            SizedBox(
              width: JavBusLayout.sidebarWidth,
              child: _ForumSidebar(
                forums: sidebarForums,
                selectedForum: _selectedForum,
                isSearchMode: true,
                isFavoritesMode: false,
                onSelectForum: _selectForum,
                onToggleSearch: _toggleSearchMode,
                onToggleFavorites: _toggleFavoritesMode,
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: JavBusSearchPage(cache: _searchCache!, onSelectThread: _selectThread)),
          ],
        ),
      );
    }

    return Scaffold(
      body: forumsAsync.when(
        loading: () {
          // 有缓存：立即显示侧边栏，右侧显示加载中
          final cached = ForumCacheService.instance.cached;
          if (cached.isNotEmpty) {
            return _buildShell(cached);
          }
          return const TopicListSkeleton();
        },
        error: (error, stackTrace) {
          // 有缓存：静默使用缓存，不显示错误
          final cached = ForumCacheService.instance.cached;
          if (cached.isNotEmpty) {
            return _buildShell(cached);
          }
          return ErrorView(
            error: error,
            stackTrace: stackTrace,
            title: 'JANUX DO 加载失败',
            onRetry: () => ref.read(forumListProvider.notifier).refresh(),
          );
        },
        data: (forums) {
          if (forums.isEmpty) {
            return const _ShellEmptyState(message: '暂无可浏览版块');
          }
          return _buildShell(forums);
        },
      ),
    );
  }

  Widget _buildShell(List<ForumForum> forums) {
    final selectedForum = _selectedForum;
    final listCache = selectedForum != null
        ? _threadListCaches.putIfAbsent(
            _forumPaneKey(selectedForum),
            _ThreadListPaneCache.new,
          )
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < JavBusLayout.compactBreakpoint) {
          return _CompactShell(
            forums: forums,
            selectedForum: selectedForum,
            selectedThread: _selectedThread,
            isSearchMode: false,
            isFavoritesMode: false,
            searchCache: _searchCache,
            selectedForumListCache: listCache,
            threadContentCaches: _threadContentCaches,
            onSelectForum: _selectForum,
            onSelectThread: _selectThread,
            onToggleSearch: _toggleSearchMode,
            onToggleFavorites: _toggleFavoritesMode,
            onExitSearch: _exitSearchMode,
            onExitFavorites: _exitFavoritesMode,
            onBackToList: () => setState(() {
            _selectedThread = null;
            if (_wasInFavoritesMode) {
              _isFavoritesMode = true;
              _wasInFavoritesMode = false;
            }
            if (_wasInSearchMode) {
              _isSearchMode = true;
              _wasInSearchMode = false;
            }
          }),
          );
        }
        return _DesktopShell(
          forums: forums,
          selectedForum: selectedForum,
          selectedThread: _selectedThread,
          isSearchMode: false,
          isFavoritesMode: false,
          searchCache: _searchCache,
          selectedForumListCache: listCache,
          threadContentCaches: _threadContentCaches,
          onSelectForum: _selectForum,
          onSelectThread: _selectThread,
          onToggleSearch: _toggleSearchMode,
          onToggleFavorites: _toggleFavoritesMode,
          onExitSearch: _exitSearchMode,
          onExitFavorites: _exitFavoritesMode,
          onBackToList: () => setState(() {
            _selectedThread = null;
            if (_wasInFavoritesMode) {
              _isFavoritesMode = true;
              _wasInFavoritesMode = false;
            }
            if (_wasInSearchMode) {
              _isSearchMode = true;
              _wasInSearchMode = false;
            }
          }),
        );
      },
    );
  }
}

class _DesktopShell extends StatelessWidget {
  const _DesktopShell({
    required this.forums,
    required this.selectedForum,
    required this.selectedThread,
    required this.isSearchMode,
    required this.isFavoritesMode,
    required this.searchCache,
    required this.selectedForumListCache,
    required this.threadContentCaches,
    required this.onSelectForum,
    required this.onSelectThread,
    required this.onToggleSearch,
    required this.onToggleFavorites,
    required this.onExitSearch,
    required this.onExitFavorites,
    required this.onBackToList,
  });

  final List<ForumForum> forums;
  final ForumForum? selectedForum;
  final ForumThread? selectedThread;
  final bool isSearchMode;
  final bool isFavoritesMode;
  final SearchPaneCache? searchCache;
  final _ThreadListPaneCache? selectedForumListCache;
  final Map<int, JavBusThreadContentCache> threadContentCaches;
  final ValueChanged<ForumForum> onSelectForum;
  final ValueChanged<ForumThread> onSelectThread;
  final VoidCallback onToggleSearch;
  final VoidCallback onToggleFavorites;
  final VoidCallback onExitSearch;
  final VoidCallback onExitFavorites;
  final VoidCallback onBackToList;

  @override
  Widget build(BuildContext context) {
    // 搜索模式下右侧面板显示搜索页
    final Widget rightPane;
    if (isSearchMode) {
      rightPane = JavBusSearchPage(cache: searchCache!, onSelectThread: onSelectThread);
    } else if (isFavoritesMode) {
      rightPane = _FavoritesPane(onSelectThread: onSelectThread);
    } else if (selectedThread != null) {
      rightPane = _ThreadReaderPane(
        key: ValueKey('reader-${selectedThread!.threadId}'),
        thread: selectedThread!,
        cache: threadContentCaches.putIfAbsent(
          selectedThread!.threadId,
          JavBusThreadContentCache.new,
        ),
        onBackToList: onBackToList,
      );
    } else {
      final forum = selectedForum;
      final cache = selectedForumListCache;
      if (forum != null && cache != null) {
        rightPane = _ThreadListPane(
          key: ValueKey(_forumPaneKey(forum)),
          forum: forum,
          cache: cache,
          onSelectThread: onSelectThread,
        );
      } else {
        rightPane = _EmptyRightPane(forums: forums);
      }
    }

    return Row(
      children: [
        SizedBox(
          width: JavBusLayout.sidebarWidth,
          child: _ForumSidebar(
            forums: forums,
            selectedForum: selectedForum,
            isSearchMode: isSearchMode,
            isFavoritesMode: isFavoritesMode,
            onSelectForum: onSelectForum,
            onToggleSearch: onToggleSearch,
            onToggleFavorites: onToggleFavorites,
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: rightPane),
      ],
    );
  }
}

/// 右侧空白引导页（无分区选中时显示）
class _EmptyRightPane extends StatelessWidget {
  const _EmptyRightPane({required this.forums});

  final List<ForumForum> forums;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.forum_outlined,
            size: 56,
            color: theme.colorScheme.onSurfaceVariant.withAlpha(80),
          ),
          const SizedBox(height: 20),
          Text(
            '选择左侧分区浏览帖子',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '或使用搜索、收藏功能',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactShell extends StatelessWidget {
  const _CompactShell({
    required this.forums,
    required this.selectedForum,
    required this.selectedThread,
    required this.isSearchMode,
    required this.isFavoritesMode,
    required this.searchCache,
    required this.selectedForumListCache,
    required this.threadContentCaches,
    required this.onSelectForum,
    required this.onSelectThread,
    required this.onToggleSearch,
    required this.onToggleFavorites,
    required this.onExitSearch,
    required this.onExitFavorites,
    required this.onBackToList,
  });

  final List<ForumForum> forums;
  final ForumForum? selectedForum;
  final ForumThread? selectedThread;
  final bool isSearchMode;
  final bool isFavoritesMode;
  final SearchPaneCache? searchCache;
  final _ThreadListPaneCache? selectedForumListCache;
  final Map<int, JavBusThreadContentCache> threadContentCaches;
  final ValueChanged<ForumForum> onSelectForum;
  final ValueChanged<ForumThread> onSelectThread;
  final VoidCallback onToggleSearch;
  final VoidCallback onToggleFavorites;
  final VoidCallback onExitSearch;
  final VoidCallback onExitFavorites;
  final VoidCallback onBackToList;

  @override
  Widget build(BuildContext context) {
    if (isSearchMode) {
      return Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 16, 2),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '返回版块列表',
                    onPressed: onExitSearch,
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(child: JavBusSearchPage(cache: searchCache!, onSelectThread: onSelectThread)),
        ],
      );
    }
    if (isFavoritesMode) {
      return Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 16, 2),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '返回版块列表',
                    onPressed: onExitFavorites,
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _FavoritesPane(onSelectThread: onSelectThread)),
        ],
      );
    }
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
                isSearchMode: false,
                isFavoritesMode: false,
                onSelectForum: onSelectForum,
                onToggleSearch: onToggleSearch,
                onToggleFavorites: onToggleFavorites,
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: () {
                final forum = selectedForum;
                final cache = selectedForumListCache;
                if (forum != null && cache != null) {
                  return _ThreadListPane(
                    key: ValueKey(_forumPaneKey(forum)),
                    forum: forum,
                    cache: cache,
                    onSelectThread: onSelectThread,
                  );
                }
                return _EmptyRightPane(forums: forums);
              }(),
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
    required this.isSearchMode,
    required this.isFavoritesMode,
    required this.onSelectForum,
    required this.onToggleSearch,
    required this.onToggleFavorites,
  });

  final List<ForumForum> forums;
  final ForumForum? selectedForum;
  final bool isSearchMode;
  final bool isFavoritesMode;
  final ValueChanged<ForumForum> onSelectForum;
  final VoidCallback onToggleSearch;
  final VoidCallback onToggleFavorites;

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
              padding: const EdgeInsets.fromLTRB(20, 24, 12, 18),
              child: Row(
                children: [
                  ClipOval(
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: ScalableImageWidget.fromSISource(
                        si: ScalableImageSource.fromSvg(
                          DefaultAssetBundle.of(context),
                          'assets/logo.svg',
                        ),
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
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
                  _SidebarIconButton(
                    icon: Icons.search_rounded,
                    selected: isSearchMode,
                    onTap: onToggleSearch,
                    tooltip: '搜索帖子',
                  ),
                  const SizedBox(width: 2),
                  _SidebarIconButton(
                    icon: Icons.star_rounded,
                    selected: isFavoritesMode,
                    onTap: onToggleFavorites,
                    tooltip: '我的收藏',
                  ),
                ],
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
                    selected: !isSearchMode &&
                        !isFavoritesMode &&
                        _sameForum(forum, selectedForum),
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
    required this.isSearchMode,
    required this.isFavoritesMode,
    required this.onSelectForum,
    required this.onToggleSearch,
    required this.onToggleFavorites,
  });

  final List<ForumForum> forums;
  final ForumForum? selectedForum;
  final bool isSearchMode;
  final bool isFavoritesMode;
  final ValueChanged<ForumForum> onSelectForum;
  final VoidCallback onToggleSearch;
  final VoidCallback onToggleFavorites;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        scrollDirection: Axis.horizontal,
        itemCount: forums.length + 2, // +1 搜索 +1 收藏
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == forums.length) {
            return ChoiceChip(
              label: const Text('搜索'),
              selected: isSearchMode,
              onSelected: (_) => onToggleSearch(),
            );
          }
          if (index == forums.length + 1) {
            return ChoiceChip(
              label: const Text('收藏'),
              selected: isFavoritesMode,
              onSelected: (_) => onToggleFavorites(),
            );
          }
          final forum = forums[index];
          return ChoiceChip(
            label: Text(forum.name),
            selected: !isSearchMode && !isFavoritesMode &&
                _sameForum(forum, selectedForum),
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

/// 侧边栏顶部图标按钮（搜索 / 收藏）
///
/// 选中时显示主色调背景，hover 时显示浅背景。
class _SidebarIconButton extends StatelessWidget {
  const _SidebarIconButton({
    required this.icon,
    required this.selected,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: selected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.68)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              icon,
              size: 20,
              color: selected
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// 收藏帖子列表面板
///
/// 复用 ThreadRow 显示收藏的帖子，点击进入详情页。
/// 列表页不显示返回按钮（与论坛主题列表页一致），
/// 返回按钮仅出现在从收藏列表点进去的帖子详情页。
class _FavoritesPane extends ConsumerWidget {
  const _FavoritesPane({this.onSelectThread});

  final ValueChanged<ForumThread>? onSelectThread;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
            child: Text(
              favorites.isEmpty ? '我的收藏' : '我的收藏 (${favorites.length})',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        if (favorites.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.star_outline_rounded,
                    size: 48,
                    color: theme.colorScheme.onSurfaceVariant.withAlpha(128),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '暂无收藏',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '浏览帖子时点击右上角星标即可收藏',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: Column(
              children: [
                const ThreadTableHeader(),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    padding: JavBusLayout.listPadding,
                    itemCount: favorites.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final thread = favorites[index];
                      return ThreadRow(
                        thread: thread,
                        views: thread.views,
                        onTap: () => _openFavoriteThread(context, thread),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  void _openFavoriteThread(BuildContext context, ForumThread thread) {
    final onSelectThread = this.onSelectThread;
    if (onSelectThread != null) {
      // shell 模式：在右侧面板内联显示详情，保留侧边栏
      onSelectThread(thread);
    } else {
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
}

/// 收藏模式 Shell（论坛数据未加载或网络异常时使用）
class _FavoritesShell extends StatelessWidget {
  const _FavoritesShell({
    required this.forums,
    required this.isFavoritesMode,
    required this.onToggleSearch,
    required this.onToggleFavorites,
    required this.onExitFavorites,
    required this.onSelectForum,
    this.onSelectThread,
  });

  final List<ForumForum> forums;
  final bool isFavoritesMode;
  final VoidCallback onToggleSearch;
  final VoidCallback onToggleFavorites;
  final VoidCallback onExitFavorites;
  final ValueChanged<ForumForum> onSelectForum;
  final ValueChanged<ForumThread>? onSelectThread;

  @override
  Widget build(BuildContext context) {
    // 紧凑模式下显示收藏面板（带顶部返回按钮）
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < JavBusLayout.compactBreakpoint) {
          return Column(
            children: [
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 2, 16, 2),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: '返回版块列表',
                        onPressed: onExitFavorites,
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(child: _FavoritesPane(onSelectThread: onSelectThread)),
            ],
          );
        }
        return Row(
          children: [
            SizedBox(
              width: JavBusLayout.sidebarWidth,
              child: _ForumSidebar(
                forums: forums,
                selectedForum: forums.isNotEmpty ? forums.first : const ForumForum(forumId: 0, name: ''),
                isSearchMode: false,
                isFavoritesMode: isFavoritesMode,
                onSelectForum: onSelectForum,
                onToggleSearch: onToggleSearch,
                onToggleFavorites: onToggleFavorites,
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: _FavoritesPane(onSelectThread: onSelectThread)),
          ],
        );
      },
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
  SortMode? _sortMode = SortMode.latest;

  void _selectSort(SortMode? mode) {
    if (_sortMode == mode) return;
    setState(() {
      _sortMode = mode;
      _threads.clear();
      _currentPage = 1;
      _totalPages = 1;
      _hasNextPage = true;
      _isLoadingInitial = true;
      _error = null;
    });
    Future.microtask(_refreshThreads);
  }

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
    _sortMode = widget.cache.sortMode;
    _isLoadingInitial = false;
    _isLoadingMore = false;
    _error = null;
    _stackTrace = null;
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
      ..sortMode = _sortMode
      ..hasLoaded = !_isLoadingInitial && _threads.isNotEmpty;
    if (_scrollController.hasClients) {
      widget.cache.scrollOffset = _scrollController.position.pixels;
    }
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
        sort: _sortMode,
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
        sort: _sortMode,
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
        _SortBar(selectedSort: _sortMode, onSelectSort: _selectSort),
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
                    const ThreadTableHeader(),
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
                            return ThreadRow(
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
  SortMode? sortMode;
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

class _SortBar extends StatelessWidget {
  const _SortBar({required this.selectedSort, required this.onSelectSort});

  final SortMode? selectedSort;
  final void Function(SortMode?) onSelectSort;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const items = [
      (SortMode.latest, '最新'),
      (SortMode.hot, '熱門'),
      (SortMode.trending, '熱帖'),
      (SortMode.digest, '精華'),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        JavBusLayout.listHorizontalPadding,
        0,
        JavBusLayout.listHorizontalPadding,
        0,
      ),
      child: Row(
        children: [
          const SizedBox(width: 28),      // icon
          const SizedBox(width: 18),
          const Expanded(child: SizedBox()), // 话题占位
          const SizedBox(width: 18),       // gap
          // 4 个按钮均匀分布在浏览→时间的总区域内（396px）
          SizedBox(
            width: JavBusLayout.topicViewsColumnWidth * 3 + 18 * 2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final (mode, label) in items)
                  Material(
                    color: mode == selectedSort
                        ? theme.colorScheme.primaryContainer
                            .withValues(alpha: 0.68)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => onSelectSort(mode),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              label,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: mode == selectedSort
                                    ? theme.colorScheme.onPrimaryContainer
                                    : theme.colorScheme.onSurfaceVariant,
                                fontWeight: mode == selectedSort
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                              ),
                            ),
                            const SizedBox(height: 2),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              height: 2,
                              width: mode == selectedSort ? 20 : 0,
                              decoration: BoxDecoration(
                                color: mode == selectedSort
                                    ? theme.colorScheme.onPrimaryContainer
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(1),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
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
                Consumer(
                  builder: (context, ref, _) {
                    final isFav = ref.watch(
                      isFavoritedProvider(thread.threadId),
                    );
                    return IconButton(
                      tooltip: isFav ? '取消收藏' : '收藏帖子',
                      onPressed: () =>
                          ref.read(favoritesProvider.notifier).toggle(thread),
                      icon: Icon(
                        isFav
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        color: isFav ? Colors.amber : null,
                      ),
                    );
                  },
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

bool _sameForum(ForumForum? a, ForumForum? b) {
  if (a == null || b == null) return false;
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


