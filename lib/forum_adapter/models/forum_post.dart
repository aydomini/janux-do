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

  factory ForumComment.fromJson(Map<String, dynamic> json) {
    return ForumComment(
      author: json['author'] as String? ?? '',
      authorId: (json['authorId'] as num?)?.toInt(),
      avatarUrl: json['avatarUrl'] as String?,
      content: json['content'] as String? ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'author': author,
      if (authorId != null) 'authorId': authorId,
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
      'content': content,
      if (createdAt != null) 'createdAt': createdAt!.toUtc().toIso8601String(),
    };
  }
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

  factory ForumPost.fromJson(Map<String, dynamic> json) {
    return ForumPost(
      postId: (json['postId'] as num).toInt(),
      threadId: (json['threadId'] as num).toInt(),
      floorNumber: (json['floorNumber'] as num).toInt(),
      author: json['author'] as String? ?? '',
      contentHtml: json['contentHtml'] as String? ?? '',
      authorId: (json['authorId'] as num?)?.toInt(),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
      avatarUrl: json['avatarUrl'] as String?,
      attachments: (json['attachments'] as List<dynamic>?)
              ?.map((e) => ForumAttachment.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      isThreadAuthor: json['isThreadAuthor'] as bool? ?? false,
      comments: (json['comments'] as List<dynamic>?)
              ?.map((e) => ForumComment.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'postId': postId,
      'threadId': threadId,
      'floorNumber': floorNumber,
      'author': author,
      'contentHtml': contentHtml,
      if (authorId != null) 'authorId': authorId,
      if (createdAt != null) 'createdAt': createdAt!.toUtc().toIso8601String(),
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
      'attachments': attachments.map((e) => e.toJson()).toList(),
      'isThreadAuthor': isThreadAuthor,
      'comments': comments.map((e) => e.toJson()).toList(),
    };
  }
}
