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

  factory ForumAttachment.fromJson(Map<String, dynamic> json) {
    return ForumAttachment(
      attachmentId: json['attachmentId'] as String?,
      fileName: json['fileName'] as String? ?? '',
      url: json['url'] as String? ?? '',
      thumbnailUrl: json['thumbnailUrl'] as String?,
      fileSize: json['fileSize'] as String?,
      mimeType: json['mimeType'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (attachmentId != null) 'attachmentId': attachmentId,
      'fileName': fileName,
      'url': url,
      if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
      if (fileSize != null) 'fileSize': fileSize,
      if (mimeType != null) 'mimeType': mimeType,
    };
  }
}
