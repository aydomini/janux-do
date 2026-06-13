import 'forum_forum.dart';
import 'forum_poll.dart';
import 'forum_post.dart';
import 'forum_thread.dart';

class ForumListResult {
  const ForumListResult({required this.forums});

  final List<ForumForum> forums;
}

class ThreadListResult {
  const ThreadListResult({
    required this.threads,
    required this.currentPage,
    required this.totalPages,
    required this.hasNextPage,
    this.viewCounts,
  });

  final List<ForumThread> threads;
  final int currentPage;
  final int totalPages;
  final bool hasNextPage;
  final Map<int, int>? viewCounts; // tid → views，来自桌面版 HTML
}

class SearchResult {
  const SearchResult({
    required this.threads,
    required this.currentPage,
    required this.totalPages,
    required this.hasNextPage,
    this.totalResults = 0,
    this.matchedKeyword,
    this.searchId,
  });

  final List<ForumThread> threads;
  final int currentPage;
  final int totalPages;
  final bool hasNextPage;
  final int totalResults;
  final String? matchedKeyword;
  final int? searchId;
}

class PostListResult {
  const PostListResult({
    required this.posts,
    required this.currentPage,
    required this.totalPages,
    required this.hasNextPage,
    required this.threadTitle,
    this.threadAuthorId,
    this.poll,
  });

  final List<ForumPost> posts;
  final int currentPage;
  final int totalPages;
  final bool hasNextPage;
  final String threadTitle;

  /// 楼主 (1#) 的 authorId，用于跨页标签匹配。
  /// 优先从 .nthread_info header 提取，回退到第一帖 authorId。
  final int? threadAuthorId;

  /// 投票数据（仅帖子包含投票时非 null）。
  /// 仅在首页存在，由 `<form id="poll">` 中解析。
  final ForumPoll? poll;
}
