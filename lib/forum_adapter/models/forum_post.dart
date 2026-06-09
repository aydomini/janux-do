import 'forum_attachment.dart';

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
}
