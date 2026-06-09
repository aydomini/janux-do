class ForumAttachment {
  const ForumAttachment({
    this.attachmentId,
    required this.fileName,
    required this.url,
    this.thumbnailUrl,
    this.fileSize,
    this.mimeType,
  });

  final String? attachmentId;
  final String fileName;
  final String url;
  final String? thumbnailUrl;
  final String? fileSize;
  final String? mimeType;
}
