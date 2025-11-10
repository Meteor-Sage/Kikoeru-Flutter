import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/works_provider.dart';
import '../models/sort_options.dart';
import 'responsive_dialog.dart';

class SortDialog extends ConsumerWidget {
  const SortDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final worksState = ref.watch(worksProvider);
    final worksNotifier = ref.read(worksProvider.notifier);
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    // 横屏时使用两列布局
    if (isLandscape) {
      return ResponsiveAlertDialog(
        title: Row(
          children: [
            const Expanded(
              child: Text('排序选项'),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
              tooltip: '关闭',
            ),
          ],
        ),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.5,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左列：排序字段
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(left: 8, bottom: 8),
                      child: Text(
                        '排序字段',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: SortOrder.values.map((option) {
                            return RadioListTile<SortOrder>(
                              title: Text(option.label),
                              value: option,
                              groupValue: worksState.sortOption,
                              onChanged: (value) {
                                if (value != null) {
                                  worksNotifier.setSortOption(value);
                                }
                              },
                              dense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              // 右列：排序方向
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(left: 8, bottom: 8),
                      child: Text(
                        '排序方向',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: SortDirection.values.map((direction) {
                            return RadioListTile<SortDirection>(
                              title: Text(direction.label),
                              value: direction,
                              groupValue: worksState.sortDirection,
                              onChanged: (value) {
                                if (value != null) {
                                  worksNotifier.setSortDirection(value);
                                }
                              },
                              dense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 竖屏时使用单列布局
    return ResponsiveAlertDialog(
      title: const Text('排序选项'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 排序字段选择
            const Text(
              '排序字段',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...SortOrder.values.map((option) {
              return RadioListTile<SortOrder>(
                title: Text(option.label),
                value: option,
                groupValue: worksState.sortOption,
                onChanged: (value) {
                  if (value != null) {
                    worksNotifier.setSortOption(value);
                  }
                },
                dense: true,
              );
            }),
            const Divider(),
            // 排序方向选择
            const Text(
              '排序方向',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...SortDirection.values.map((direction) {
              return RadioListTile<SortDirection>(
                title: Text(direction.label),
                value: direction,
                groupValue: worksState.sortDirection,
                onChanged: (value) {
                  if (value != null) {
                    worksNotifier.setSortDirection(value);
                  }
                },
                dense: true,
              );
            }),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
