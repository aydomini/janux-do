import 'package:flutter/material.dart';

import '../../forum_adapter/models/forum_thread.dart';
import 'javbus_layout.dart';

/// 主题列表表头（浏览/回复/时间列）
///
/// 主题列表和搜索结果页面共用。
class ThreadTableHeader extends StatelessWidget {
  const ThreadTableHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        JavBusLayout.listHorizontalPadding,
        14,
        JavBusLayout.listHorizontalPadding,
        14,
      ),
      child: Row(
        children: [
          const SizedBox(width: 28),
          const SizedBox(width: 18),
          Expanded(child: Text('话题', style: labelStyle)),
          const SizedBox(width: 18),
          SizedBox(
            width: JavBusLayout.topicViewsColumnWidth,
            child: Text('浏览', textAlign: TextAlign.center, style: labelStyle),
          ),
          const SizedBox(width: 18),
          SizedBox(
            width: JavBusLayout.topicReplyColumnWidth,
            child: Text('回复', textAlign: TextAlign.center, style: labelStyle),
          ),
          const SizedBox(width: 18),
          SizedBox(
            width: JavBusLayout.topicTimeColumnWidth,
            child: Text('时间', textAlign: TextAlign.center, style: labelStyle),
          ),
        ],
      ),
    );
  }
}

/// 主题行组件
///
/// 支持两种模式：
/// - 普通模式：主题列表行（标题 + 作者/徽章/创建日期）
/// - 搜索模式：搜索结果行（标题 + 摘要 + 版块/作者）
class ThreadRow extends StatelessWidget {
  const ThreadRow({
    super.key,
    required this.thread,
    required this.onTap,
    this.views = 0,
    this.isSearchResult = false,
  });

  final ForumThread thread;
  final VoidCallback onTap;
  final int views;
  final bool isSearchResult;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 28,
              child: Icon(
                isSearchResult
                    ? Icons.search_rounded
                    : thread.isPinned
                    ? Icons.push_pin_rounded
                    : thread.hasAttachment
                    ? Icons.attach_file_rounded
                    : Icons.chat_bubble_outline_rounded,
                size: 18,
                color: thread.isPinned && !isSearchResult
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 240),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      thread.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (isSearchResult && thread.excerpt != null) ...[
                      const SizedBox(height: 5),
                      Text(
                        thread.excerpt!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.45,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    if (isSearchResult)
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          if (thread.forumName != null)
                            _MutedMeta(
                              icon: Icons.folder_outlined,
                              label: thread.forumName!,
                            ),
                          _MutedMeta(
                            icon: Icons.person_outline_rounded,
                            label: thread.author,
                          ),
                        ],
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          _MutedMeta(
                            icon: Icons.person_outline_rounded,
                            label: thread.author,
                          ),
                          if (thread.isPinned) const _SmallBadge(label: '置顶'),
                          if (thread.isDigest) const _SmallBadge(label: '精华'),
                          if (thread.hasAttachment)
                            const _SmallBadge(label: '附件'),
                          if (thread.createdAt != null)
                            _MutedMeta(
                              icon: Icons.calendar_today_outlined,
                              label: _formatCreatedDate(thread.createdAt!),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 18),
            SizedBox(
              width: JavBusLayout.topicViewsColumnWidth,
              child: Text(
                formatCount(views),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 18),
            SizedBox(
              width: JavBusLayout.topicReplyColumnWidth,
              child: Text(
                formatCount(thread.replies),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 18),
            SizedBox(
              width: JavBusLayout.topicTimeColumnWidth,
              child: Text(
                formatThreadTime(
                  isSearchResult
                      ? thread.createdAt
                      : (thread.lastReplyAt ?? thread.createdAt),
                ),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MutedMeta extends StatelessWidget {
  const _MutedMeta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _SmallBadge extends StatelessWidget {
  const _SmallBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// 数字格式化：10000+ 显示为 "1.0万"，1000+ 显示为 "1.0k"
String formatCount(int value) {
  if (value <= 0) return '-';
  if (value >= 10000) return '${(value / 10000).toStringAsFixed(1)}万';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
  return '$value';
}

/// 时间格式化：7 天内用相对时间，超过用日历日期
String formatThreadTime(DateTime? value) {
  if (value == null) return '';
  final now = DateTime.now();
  final diff = now.difference(value);

  if (diff.inDays < 7) {
    if (diff.inSeconds < 60) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    return '${diff.inDays}天前';
  }

  String two(int input) => input.toString().padLeft(2, '0');
  return value.year == now.year
      ? '${two(value.month)} 月 ${two(value.day)} 日'
      : '${two(value.year % 100)} 年 ${two(value.month)} 月 ${two(value.day)} 日';
}

/// 创建日期格式化（始终显示完整日历日期）
String _formatCreatedDate(DateTime value) {
  String two(int input) => input.toString().padLeft(2, '0');
  return '${two(value.year % 100)} 年 ${two(value.month)} 月 ${two(value.day)} 日';
}
