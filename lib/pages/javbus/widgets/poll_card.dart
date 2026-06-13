import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../forum_adapter/models/forum_poll.dart';
import '../../../l10n/s.dart';
import '../javbus_layout.dart';

/// 帖子投票卡片 —— 展示投票选项、进度条、票数和百分比
///
/// 字体与间距对齐「点评」组件（_CommentSection），作为帖子的附属信息区。
class PollCard extends StatelessWidget {
  const PollCard({super.key, required this.poll});

  final ForumPoll poll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: JavBusLayout.textContentMaxWidth,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: theme.brightness == Brightness.dark ? 0.28 : 0.42,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(context),
              if (poll.options.isNotEmpty) const SizedBox(height: 6),
              ...poll.options.map(
                (option) => _PollOptionRow(
                  option: option,
                  totalVoters: poll.totalVoters,
                ),
              ),
              _buildFooter(context),
            ],
          ),
        ),
      ),
    );
  }

  /// 投票头部：类型标签 + 状态标签 + 参与人数
  Widget _buildHeader(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        _StatusChip(
          label: poll.isMultiple ? '多选' : '单选',
          backgroundColor: colorScheme.tertiaryContainer,
          foregroundColor: colorScheme.onTertiaryContainer,
        ),
        if (poll.isClosed) ...[
          const SizedBox(width: 6),
          _StatusChip(
            label: l10n.poll_closed,
            backgroundColor: colorScheme.errorContainer,
            foregroundColor: colorScheme.onErrorContainer,
          ),
        ],
        if (poll.maxChoices != null && poll.isMultiple) ...[
          const SizedBox(width: 6),
          Text(
            '最多选 ${poll.maxChoices} 项',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const Spacer(),
        Text(
          l10n.poll_voters(poll.totalVoters),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// 底部信息：对齐点评时间文字的样式
  Widget _buildFooter(BuildContext context) {
    final theme = Theme.of(context);

    final footerStyle = theme.textTheme.bodyLarge?.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.54),
      height: 1.64,
    );

    if (poll.isClosed) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 15,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.54),
            ),
            const SizedBox(width: 4),
            Text(context.l10n.vote_topicClosed, style: footerStyle),
          ],
        ),
      );
    }

    if (poll.hasVoted) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: [
            Icon(
              Icons.check_circle_outline_rounded,
              size: 15,
              color: theme.colorScheme.primary.withValues(alpha: 0.54),
            ),
            const SizedBox(width: 4),
            Text(context.l10n.vote_voted, style: footerStyle),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

/// 单个投票选项行，对齐点评条目间距和文字规格
class _PollOptionRow extends StatelessWidget {
  const _PollOptionRow({
    required this.option,
    required this.totalVoters,
  });

  final PollOption option;
  final int totalVoters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final barColor = _parseColor(context, option.color);
    final pct = option.percentage ?? 0;

    // 对齐点评内容文字：bodyLarge + height: 1.64
    final optionStyle = theme.textTheme.bodyLarge?.copyWith(height: 1.64);
    // 对齐点评时间文字：bodyLarge + alpha 0.54
    final statStyle = theme.textTheme.bodyLarge?.copyWith(
      color: colorScheme.onSurface.withValues(alpha: 0.54),
      height: 1.64,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 选项文本 + 票数/百分比
          Row(
            children: [
              Expanded(
                child: Text(
                  '${option.index}. ${option.text}',
                  style: optionStyle,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${option.votes} 票  ${pct.toStringAsFixed(1)}%',
                style: statStyle,
              ),
            ],
          ),
          const SizedBox(height: 5),
          // 进度条
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 6,
              child: Row(
                children: [
                  if (pct > 0)
                    Flexible(
                      flex: (pct.clamp(1.5, 100) * 1000).round(),
                      child: Container(color: barColor),
                    ),
                  if (pct < 100)
                    Flexible(
                      flex: ((100 - pct.clamp(0, 100)) * 1000).round(),
                      child: Container(
                        color: colorScheme.surfaceContainerHighest,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 将 HTML 颜色字符串（#RRGGBB）转换为 Color，夜间模式下降饱和提亮度
  static Color _parseColor(BuildContext context, String? hex) {
    final fallback = Theme.of(context).colorScheme.primary;
    if (hex == null || hex.isEmpty) return fallback;
    final cleaned = hex.replaceFirst('#', '');
    final value = int.tryParse('FF$cleaned', radix: 16);
    if (value == null) return fallback;

    final raw = Color(value);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (!isDark) return raw;

    // 夜间模式：降饱和、保底亮度，避免鲜艳色在暗色背景下刺眼
    final hsl = HSLColor.fromColor(raw);
    return hsl
        .withSaturation((hsl.saturation * 0.75).clamp(0.0, 1.0))
        .withLightness(math.max(hsl.lightness, 0.45))
        .toColor();
  }
}

/// 紧凑状态标签，对齐 _AuthorBadge 的 DecoratedBox 模式
class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: foregroundColor,
          ),
        ),
      ),
    );
  }
}
