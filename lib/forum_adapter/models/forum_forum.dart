class ForumForum {
  const ForumForum({
    required this.forumId,
    required this.name,
    this.description,
    this.parentForumId,
    this.filterTypeId,
    this.threadCount = 0,
    this.todayPostCount = 0,
    this.url,
  });

  final int forumId;
  final String name;
  final String? description;
  final int? parentForumId;
  final int? filterTypeId;
  final int threadCount;
  final int todayPostCount;
  final String? url;
}
