import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/work_detail_display_provider.dart';
import '../widgets/scrollable_appbar.dart';

class WorkDetailDisplaySettingsScreen extends ConsumerWidget {
  const WorkDetailDisplaySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(workDetailDisplayProvider);
    final notifier = ref.read(workDetailDisplayProvider.notifier);

    return Scaffold(
      appBar: const ScrollableAppBar(
        title: Text(
          '作品详情显示设置',
          style: TextStyle(fontSize: 18),
        ),
      ),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('评分信息'),
            subtitle: const Text('显示作品评分和评价人数'),
            value: settings.showRating,
            onChanged: (_) => notifier.toggleRating(),
          ),
          Divider(color: Theme.of(context).colorScheme.outlineVariant),
          SwitchListTile(
            title: const Text('售价信息'),
            subtitle: const Text('显示作品价格'),
            value: settings.showPrice,
            onChanged: (_) => notifier.togglePrice(),
          ),
          Divider(color: Theme.of(context).colorScheme.outlineVariant),
          SwitchListTile(
            title: const Text('时长信息'),
            subtitle: const Text('显示作品时长'),
            value: settings.showDuration,
            onChanged: (_) => notifier.toggleDuration(),
          ),
          Divider(color: Theme.of(context).colorScheme.outlineVariant),
          SwitchListTile(
            title: const Text('售出信息'),
            subtitle: const Text('显示作品售出数量'),
            value: settings.showSales,
            onChanged: (_) => notifier.toggleSales(),
          ),
          Divider(color: Theme.of(context).colorScheme.outlineVariant),
          SwitchListTile(
            title: const Text('外部链接信息'),
            subtitle: const Text('显示DLsite、官网等外部链接'),
            value: settings.showExternalLinks,
            onChanged: (_) => notifier.toggleExternalLinks(),
          ),
          Divider(color: Theme.of(context).colorScheme.outlineVariant),
          SwitchListTile(
            title: const Text('发布日期'),
            subtitle: const Text('显示作品发布日期'),
            value: settings.showReleaseDate,
            onChanged: (_) => notifier.toggleReleaseDate(),
          ),
          Divider(color: Theme.of(context).colorScheme.outlineVariant),
          SwitchListTile(
            title: const Text('翻译按钮'),
            subtitle: const Text('显示作品标题的翻译按钮'),
            value: settings.showTranslateButton,
            onChanged: (_) => notifier.toggleTranslateButton(),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
