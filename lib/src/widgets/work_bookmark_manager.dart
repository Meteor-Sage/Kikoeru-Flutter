import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../providers/my_reviews_provider.dart';
import 'review_progress_dialog.dart';

/// 作品标记管理器 - 封装标记状态的逻辑和UI
/// 可被多个页面复用，确保状态和刷新机制一致
class WorkBookmarkManager {
  final WidgetRef ref;
  final BuildContext context;

  WorkBookmarkManager({
    required this.ref,
    required this.context,
  });

  /// 显示标记对话框并处理更新
  /// 返回更新后的进度值（如果有变化）
  Future<String?> showMarkDialog({
    required int workId,
    required String? currentProgress,
    required Function(String? newProgress) onProgressChanged,
  }) async {
    final result = await ReviewProgressDialog.show(
      context: context,
      currentProgress: currentProgress,
      title: '标记作品',
    );

    if (result != null && context.mounted) {
      try {
        final apiService = ref.read(kikoeruApiServiceProvider);

        if (result == '__REMOVE__') {
          // 删除标记
          await apiService.deleteReview(workId);

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('已移除标记'),
                duration: Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }

          // 更新状态
          onProgressChanged(null);

          // 刷新我的评论列表
          ref.read(myReviewsProvider.notifier).load(refresh: true);

          return null;
        } else {
          // 更新标记
          await apiService.updateReviewProgress(
            workId,
            progress: result,
          );

          // 获取标记的显示名称
          final filterLabel = MyReviewFilter.values
              .firstWhere(
                (f) => f.value == result,
                orElse: () => MyReviewFilter.all,
              )
              .label;

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('已设置为：$filterLabel'),
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }

          // 更新状态
          onProgressChanged(result);

          // 刷新我的评论列表
          ref.read(myReviewsProvider.notifier).load(refresh: true);

          return result;
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('操作失败: $e'),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }

    return null;
  }

  /// 获取状态标签文本
  static String getProgressLabel(String? progress) {
    if (progress == null) return '标记';

    final filter = [
      MyReviewFilter.marked,
      MyReviewFilter.listening,
      MyReviewFilter.listened,
      MyReviewFilter.replay,
      MyReviewFilter.postponed,
    ].firstWhere(
      (f) => f.value == progress,
      orElse: () => MyReviewFilter.all,
    );

    return filter.label;
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
}
