import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import '../providers/my_reviews_provider.dart';
import 'add_to_playlist_dialog.dart';
import 'responsive_dialog.dart';

/// 通用的收藏状态编辑对话框组件
///
/// 根据屏幕方向自动选择：
/// - 横屏：显示Dialog（3+3两列布局）
/// - 竖屏：显示BottomSheet（单列列表）
///
/// 返回值：
/// - Map包含：'progress': String?, 'rating': int?
/// - progress为'__REMOVE__'表示移除标记
/// - null 表示取消操作
class ReviewProgressDialog {
  /// 显示收藏状态编辑对话框
  ///
  /// [context] - 上下文
  /// [currentProgress] - 当前的进度状态值
  /// [currentRating] - 当前的评分值(1-5)
  /// [title] - 对话框标题，默认为"标记作品"
  /// [showLoading] - 是否显示加载指示器（用于更新状态时）
  /// [workId] - 作品ID，用于添加到播放列表
  /// [workTitle] - 作品标题，用于添加到播放列表
  static Future<Map<String, dynamic>?> show({
    required BuildContext context,
    String? currentProgress,
    int? currentRating,
    String title = '标记作品',
    bool showLoading = false,
    int? workId,
    String? workTitle,
  }) async {
    final filters = [
      MyReviewFilter.marked,
      MyReviewFilter.listening,
      MyReviewFilter.listened,
      MyReviewFilter.replay,
      MyReviewFilter.postponed,
    ];

    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    String? selectedProgress = currentProgress;
    int? selectedRating = currentRating;

    if (isLandscape) {
      // 横屏模式：使用对话框形式，3+3两列布局
      return showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: !Platform.isIOS, // iOS 上防止点击外部区域意外关闭
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setState) {
              return Dialog(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.6,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 标题栏（含评分）
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
                        child: Row(
                          children: [
                            Text(
                              title,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 16),
                            // 评分星星
                            ...List.generate(5, (index) {
                              final starValue = index + 1;
                              final isSelected = selectedRating != null &&
                                  starValue <= selectedRating!;
                              return IconButton(
                                icon: Icon(
                                  isSelected ? Icons.star : Icons.star_border,
                                  color: isSelected ? Colors.amber : null,
                                  size: 24,
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 32,
                                  minHeight: 32,
                                ),
                                onPressed: () {
                                  setState(() {
                                    selectedRating = selectedRating == starValue
                                        ? null
                                        : starValue;
                                  });
                                },
                                tooltip: '$starValue 星',
                              );
                            }),
                            const Spacer(),
                            if (workId != null && workTitle != null)
                              IconButton(
                                icon: const Icon(Icons.playlist_add),
                                onPressed: () async {
                                  await AddToPlaylistDialog.show(
                                    context: context,
                                    workId: workId,
                                    workTitle: workTitle,
                                  );
                                },
                                tooltip: '添加到播放列表',
                              ),
                            if (showLoading)
                              const Padding(
                                padding: EdgeInsets.only(right: 8),
                                child: SizedBox(
                                  height: 20,
                                  width: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                              tooltip: '关闭',
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      // 内容区域 - 3+3两列布局，支持滚动
                      Flexible(
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // 左列：前3个选项
                                    Expanded(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: filters.take(3).map((filter) {
                                          final isSelected =
                                              selectedProgress == filter.value;
                                          return RadioListTile<String>(
                                            title: Text(filter.label),
                                            value: filter.value!,
                                            groupValue: selectedProgress,
                                            onChanged: (value) {
                                              setState(() {
                                                selectedProgress = value;
                                              });
                                            },
                                            selected: isSelected,
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 8),
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                    const VerticalDivider(width: 1),
                                    // 右列：后2个选项 + 移除按钮
                                    Expanded(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          ...filters.skip(3).map((filter) {
                                            final isSelected =
                                                selectedProgress ==
                                                    filter.value;
                                            return RadioListTile<String>(
                                              title: Text(filter.label),
                                              value: filter.value!,
                                              groupValue: selectedProgress,
                                              onChanged: (value) {
                                                setState(() {
                                                  selectedProgress = value;
                                                });
                                              },
                                              selected: isSelected,
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8),
                                            );
                                          }),
                                          if (currentProgress != null ||
                                              currentRating != null) ...[
                                            const Divider(height: 1),
                                            InkWell(
                                              onTap: () {
                                                Navigator.of(dialogContext)
                                                    .pop({
                                                  'progress': '__REMOVE__',
                                                  'rating': null,
                                                });
                                              },
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 4,
                                                        vertical: 12),
                                                child: Row(
                                                  children: [
                                                    SizedBox(
                                                      width: 40,
                                                      child: Icon(
                                                        Icons.delete_outline,
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .error,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      '移除',
                                                      style: TextStyle(
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .error,
                                                        fontSize: 16,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      // 底部按钮
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                              child: const Text('取消'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: () {
                                Navigator.of(dialogContext).pop({
                                  'progress': selectedProgress,
                                  'rating': selectedRating,
                                });
                              },
                              child: const Text('确定'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    } else {
      // 竖屏模式：使用底部弹窗
      return showResponsiveBottomSheet<Map<String, dynamic>>(
        context: context,
        isDismissible: !Platform.isIOS, // iOS 上防止点击外部区域或下拉意外关闭
        enableDrag: !Platform.isIOS, // iOS 上禁止下拉关闭
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setState) {
              return Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Text(
                            title,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(width: 8),
                          // 评分星星
                          ...List.generate(5, (index) {
                            final starValue = index + 1;
                            final isSelected = selectedRating != null &&
                                starValue <= selectedRating!;
                            return IconButton(
                              icon: Icon(
                                isSelected ? Icons.star : Icons.star_border,
                                color: isSelected ? Colors.amber : null,
                                size: 22,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 28,
                                minHeight: 28,
                              ),
                              onPressed: () {
                                setState(() {
                                  selectedRating = selectedRating == starValue
                                      ? null
                                      : starValue;
                                });
                              },
                              tooltip: '$starValue 星',
                            );
                          }),
                          const Spacer(),
                          if (workId != null && workTitle != null)
                            IconButton(
                              icon: const Icon(Icons.playlist_add),
                              onPressed: () async {
                                await AddToPlaylistDialog.show(
                                  context: context,
                                  workId: workId,
                                  workTitle: workTitle,
                                );
                              },
                              tooltip: '添加到播放列表',
                            ),
                          if (showLoading)
                            const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                        ],
                      ),
                    ),
                    const Divider(),
                    // 进度选项
                    ...filters.map((filter) {
                      final isSelected = selectedProgress == filter.value;
                      return ListTile(
                        leading: Icon(
                          isSelected
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        title: Text(filter.label),
                        selected: isSelected,
                        onTap: () {
                          setState(() {
                            selectedProgress = filter.value;
                          });
                        },
                      );
                    }).toList(),
                    const SizedBox(height: 8),
                    if (currentProgress != null || currentRating != null)
                      ListTile(
                        leading: Icon(
                          Icons.delete_outline,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        title: Text(
                          '移除',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(context, {
                            'progress': '__REMOVE__',
                            'rating': null,
                          });
                        },
                      ),
                    const Divider(),
                    // 底部按钮
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () {
                                Navigator.pop(context); // 取消，不返回任何值
                              },
                              child: const Text('取消'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              onPressed: () {
                                Navigator.pop(context, {
                                  'progress': selectedProgress,
                                  'rating': selectedRating,
                                });
                              },
                              child: const Text('确定'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    }
  }

  /// 获取状态标签
  static String getProgressLabel(String? value) {
    if (value == null) return '标记';
    final found = [
      MyReviewFilter.marked,
      MyReviewFilter.listening,
      MyReviewFilter.listened,
      MyReviewFilter.replay,
      MyReviewFilter.postponed,
    ].firstWhere(
      (f) => f.value == value,
      orElse: () => MyReviewFilter.all,
    );
    return found.label;
  }

  /// 获取状态对应的图标
  static IconData getProgressIcon(String? progress) {
    if (progress == null) return Icons.bookmark_border;

    switch (progress) {
      case 'marked':
        return Icons.bookmark;
      case 'listening':
        return Icons.headphones;
      case 'listened':
        return Icons.check_circle;
      case 'replay':
        return Icons.replay;
      case 'postponed':
        return Icons.schedule;
      default:
        return Icons.bookmark;
    }
  }

  /// @deprecated 使用 getProgressLabel 替代
  static String getLabelForProgress(String? value) => getProgressLabel(value);
}
