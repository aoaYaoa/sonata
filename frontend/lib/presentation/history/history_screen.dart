import 'package:flutter/material.dart';

import 'history_panel.dart';

/// 独立的历史页。
///
/// 播放历史此前只能从「我的 → 历史」弹层里看到，而「历史」这张卡片在
/// 我的页是和收藏/队列/本地并排的四个小方块之一，入口不算明显。
/// 首页「最近播放」右上角给一个「全部」，点进来就是这一页。
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: const Text('播放历史'),
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: scheme.onSurface,
        ),
        iconTheme: IconThemeData(color: scheme.onSurface),
      ),
      body: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
        child: const HistoryPanel(),
      ),
    );
  }
}
