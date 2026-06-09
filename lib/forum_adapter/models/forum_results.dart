import 'forum_forum.dart';
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

class PostListResult {
  const PostListResult({
    required this.posts,
    required this.currentPage,
    required this.totalPages,
    required this.hasNextPage,
    required this.threadTitle,
  });

  final List<ForumPost> posts;
  final int currentPage;
  final int totalPages;
  final bool hasNextPage;
  final String threadTitle;
}
