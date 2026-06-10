import 'forum_attachment.dart';

class ForumThread {
  const ForumThread({
    required this.threadId,
    required this.forumId,
    required this.title,
    required this.author,
    this.authorId,
    this.replies = 0,
    this.views = 0,
    this.createdAt,
    this.lastReplyAt,
    this.forumName,
    this.isPinned = false,
    this.isDigest = false,
    this.excerpt,
    this.hasAttachment = false,
    this.attachments = const [],
    this.url,
  });

  final int threadId;
  final int forumId;
  final String title;
  final String author;
  final int? authorId;
  final int replies;
  final int views;
  final DateTime? createdAt;
  final DateTime? lastReplyAt;
  final String? forumName;
  final bool isPinned;
  final bool isDigest;
  final String? excerpt;
  final bool hasAttachment;
  final List<ForumAttachment> attachments;
  final String? url;
}
