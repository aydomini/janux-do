/// Discuz 投票选项
class PollOption {
  const PollOption({
    required this.index,
    required this.text,
    required this.votes,
    this.percentage,
    this.color,
  });

  /// 选项序号（从 1 开始）
  final int index;

  /// 选项文字
  final String text;

  /// 该选项获得的票数
  final int votes;

  /// 该选项得票百分比（例如 9.48）
  final double? percentage;

  /// 进度条颜色（如 #E92725）
  final String? color;

  factory PollOption.fromJson(Map<String, dynamic> json) {
    return PollOption(
      index: (json['index'] as num).toInt(),
      text: json['text'] as String? ?? '',
      votes: (json['votes'] as num).toInt(),
      percentage: (json['percentage'] as num?)?.toDouble(),
      color: json['color'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'index': index,
      'text': text,
      'votes': votes,
      if (percentage != null) 'percentage': percentage,
      if (color != null) 'color': color,
    };
  }
}

/// Discuz 论坛投票（帖子内嵌投票）
///
/// 仅在第一页首帖的 .pcbs 区域中出现，由 `<form id="poll">` 承载。
/// 解析来源：桌面版 viewthread HTML。
class ForumPoll {
  const ForumPoll({
    this.isMultiple = false,
    this.maxChoices,
    this.totalVoters = 0,
    this.isClosed = false,
    this.hasVoted = false,
    required this.options,
  });

  /// 是否为多选投票
  final bool isMultiple;

  /// 最大可选项目数（仅多选时有意义，如"最多可选 15 项"）
  final int? maxChoices;

  /// 参与投票总人数
  final int totalVoters;

  /// 投票是否已结束
  final bool isClosed;

  /// 当前用户是否已投票（由页面标记推断）
  final bool hasVoted;

  /// 投票选项列表
  final List<PollOption> options;

  factory ForumPoll.fromJson(Map<String, dynamic> json) {
    return ForumPoll(
      isMultiple: json['isMultiple'] as bool? ?? false,
      maxChoices: (json['maxChoices'] as num?)?.toInt(),
      totalVoters: (json['totalVoters'] as num?)?.toInt() ?? 0,
      isClosed: json['isClosed'] as bool? ?? false,
      hasVoted: json['hasVoted'] as bool? ?? false,
      options: (json['options'] as List<dynamic>)
          .map((e) => PollOption.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'isMultiple': isMultiple,
      if (maxChoices != null) 'maxChoices': maxChoices,
      'totalVoters': totalVoters,
      'isClosed': isClosed,
      'hasVoted': hasVoted,
      'options': options.map((e) => e.toJson()).toList(),
    };
  }
}
