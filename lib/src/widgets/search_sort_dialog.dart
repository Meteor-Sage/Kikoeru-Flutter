import 'package:flutter/material.dart';
import '../models/sort_options.dart';
import 'responsive_dialog.dart';

class SearchSortDialog extends StatelessWidget {
  final SortOrder currentOption;
  final SortDirection currentDirection;
  final Function(SortOrder, SortDirection) onSort;

  const SearchSortDialog({
    super.key,
    required this.currentOption,
    required this.currentDirection,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    // 横屏时使用两列布局
    if (isLandscape) {
      return ResponsiveAlertDialog(
        title: Row(
          children: [
            const Expanded(
              child: Text('排序'),
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
                              groupValue: currentOption,
                              onChanged: (value) {
                                if (value != null) {
                                  onSort(value, currentDirection);
                                  Navigator.pop(context);
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
                              groupValue: currentDirection,
                              onChanged: (value) {
                                if (value != null) {
                                  onSort(currentOption, value);
                                  Navigator.pop(context);
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
      title: const Text('排序'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 动态生成排序选项
            ...SortOrder.values.map((option) {
              return ListTile(
                title: Text(option.label),
                leading: Radio<SortOrder>(
                  value: option,
                  groupValue: currentOption,
                  onChanged: (value) {
                    if (value != null) {
                      onSort(value, currentDirection);
                      Navigator.pop(context);
                    }
                  },
                ),
              );
            }),
            const Divider(),
            // 动态生成排序方向选项
            ...SortDirection.values.map((direction) {
              return ListTile(
                title: Text(direction.label),
                leading: Radio<SortDirection>(
                  value: direction,
                  groupValue: currentDirection,
                  onChanged: (value) {
                    if (value != null) {
                      onSort(currentOption, value);
                      Navigator.pop(context);
                    }
                  },
                ),
              );
            }),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
