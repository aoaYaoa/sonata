import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../domain/models/music_source.dart';

/// 音源胶囊 + 音源选择面板。
///
/// 这两个控件此前在搜索页和发现页各写了一份（`_SourcePill` / `_SourceSheet`
/// 各两份，将近 200 行几乎逐行相同，只有高度和阴影不同）。标签上一轮已经收进
/// [MusicSource] 了，控件这里当时漏掉了。
///
/// 两种形态：
///  - [SourcePill.elevated] = true，给「浮在搜索框右边」用：44pt 高、带描边和投影；
///  - 默认是扁的，给「AppBar 右上角」用：贴着一块纯色导航栏，加阴影会脏。

/// 弹出音源选择面板。
Future<void> showSourceSheet(
  BuildContext context, {
  required String current,
  required ValueChanged<String> onSelected,
}) {
  return showModalBottomSheet<void>(
    context: context,
    builder:
        (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        ctx,
                      ).colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 8),
                  child: Text(
                    '选择音源',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(ctx).colorScheme.onSurface,
                    ),
                  ),
                ),
                ...MusicSource.ids.map((id) {
                  final selected = id == current;
                  final scheme = Theme.of(ctx).colorScheme;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Material(
                      color:
                          selected
                              ? scheme.primary.withValues(alpha: 0.12)
                              : Colors.transparent,
                      borderRadius: SolaraRadius.tileRadius,
                      child: InkWell(
                        borderRadius: SolaraRadius.tileRadius,
                        onTap: () => onSelected(id),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 13,
                          ),
                          child: Row(
                            children: [
                              Text(
                                MusicSource.shortLabel(id),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight:
                                      selected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                  color:
                                      selected
                                          ? scheme.primary
                                          : scheme.onSurface,
                                ),
                              ),
                              const Spacer(),
                              if (selected)
                                Icon(
                                  Icons.check_rounded,
                                  size: 19,
                                  color: scheme.primary,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
  );
}

class SourcePill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  /// 浮在搜索框旁边（true）还是贴在 AppBar 上（false）。
  final bool elevated;

  const SourcePill({
    super.key,
    required this.label,
    required this.onTap,
    this.elevated = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: elevated ? 44 : null,
        padding:
            elevated
                ? const EdgeInsets.symmetric(horizontal: 12)
                : const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color:
              elevated
                  ? (isDark
                      ? SolaraColors.darkSurfaceHigh.withValues(alpha: 0.92)
                      : Colors.white)
                  : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(elevated ? 16 : 14),
          border:
              elevated
                  ? Border.all(
                    color:
                        isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.black.withValues(alpha: 0.05),
                  )
                  : null,
          boxShadow:
              elevated
                  ? [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.28 : 0.06,
                      ),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ]
                  : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(width: 1),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
