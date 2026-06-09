import 'forum_attachment.dart';

/// 楼中楼点评
class ForumComment {
  const ForumComment({
    required this.author,
    this.authorId,
    this.avatarUrl,
    required this.content,
    this.createdAt,
  });

  final String author;
  final int? authorId;
  final String? avatarUrl;
  final String content;
  final DateTime? createdAt;
}

class ForumPost {
  const ForumPost({
    required this.postId,
    required this.threadId,
    required this.floorNumber,
    required this.author,
    required this.contentHtml,
    this.authorId,
    this.createdAt,
    this.avatarUrl,
    this.attachments = const [],
    this.isThreadAuthor = false,
    this.comments = const [],
  });

  final int postId;
  final int threadId;
  final int floorNumber;
  final String author;
  final int? authorId;
  final DateTime? createdAt;
  final String? avatarUrl;
  final String contentHtml;
  final List<ForumAttachment> attachments;
  final bool isThreadAuthor;
  final List<ForumComment> comments;
}
