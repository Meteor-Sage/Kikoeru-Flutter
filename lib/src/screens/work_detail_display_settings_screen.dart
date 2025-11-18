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
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: Icon(
                    Icons.star,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: const Text('评分信息'),
                  subtitle: const Text('显示作品评分和评价人数'),
                  value: settings.showRating,
                  onChanged: (_) => notifier.toggleRating(),
                ),
                Divider(color: Theme.of(context).colorScheme.outlineVariant),
                SwitchListTile(
                  secondary: Icon(
                    Icons.attach_money,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: const Text('售价信息'),
                  subtitle: const Text('显示作品价格'),
                  value: settings.showPrice,
                  onChanged: (_) => notifier.togglePrice(),
                ),
                Divider(color: Theme.of(context).colorScheme.outlineVariant),
                SwitchListTile(
                  secondary: Icon(
                    Icons.access_time,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: const Text('时长信息'),
                  subtitle: const Text('显示作品时长'),
                  value: settings.showDuration,
                  onChanged: (_) => notifier.toggleDuration(),
                ),
                Divider(color: Theme.of(context).colorScheme.outlineVariant),
                SwitchListTile(
                  secondary: Icon(
                    Icons.shopping_cart,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: const Text('售出信息'),
                  subtitle: const Text('显示作品售出数量'),
                  value: settings.showSales,
                  onChanged: (_) => notifier.toggleSales(),
                ),
                Divider(color: Theme.of(context).colorScheme.outlineVariant),
                SwitchListTile(
                  secondary: Icon(
                    Icons.open_in_new,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: const Text('外部链接信息'),
                  subtitle: const Text('显示DLsite、官网等外部链接'),
                  value: settings.showExternalLinks,
                  onChanged: (_) => notifier.toggleExternalLinks(),
                ),
                Divider(color: Theme.of(context).colorScheme.outlineVariant),
                SwitchListTile(
                  secondary: Icon(
                    Icons.calendar_today,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: const Text('发布日期'),
                  subtitle: const Text('显示作品发布日期'),
                  value: settings.showReleaseDate,
                  onChanged: (_) => notifier.toggleReleaseDate(),
                ),
                Divider(color: Theme.of(context).colorScheme.outlineVariant),
                SwitchListTile(
                  secondary: Icon(
                    Icons.translate,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: const Text('翻译按钮'),
                  subtitle: const Text('显示作品标题的翻译按钮'),
                  value: settings.showTranslateButton,
                  onChanged: (_) => notifier.toggleTranslateButton(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
