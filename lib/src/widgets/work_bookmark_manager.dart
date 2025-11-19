import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../providers/my_reviews_provider.dart';
import '../utils/snackbar_util.dart';
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
  /// 返回包含进度和评分的Map（如果有变化）
  Future<Map<String, dynamic>?> showMarkDialog({
    required int workId,
    required String? currentProgress,
    required int? currentRating,
    required Function(String? newProgress, int? newRating) onChanged,
    String? workTitle,
  }) async {
    final result = await ReviewProgressDialog.show(
      context: context,
      currentProgress: currentProgress,
      currentRating: currentRating,
      title: '标记作品',
      workId: workId,
      workTitle: workTitle,
    );

    if (result != null && context.mounted) {
      try {
        final apiService = ref.read(kikoeruApiServiceProvider);

        if (result['progress'] == '__REMOVE__') {
          // 删除标记
          await apiService.deleteReview(workId);

          if (context.mounted) {
            SnackBarUtil.showSuccess(context, '已移除标记');
          }

          // 更新状态
          onChanged(null, null);

          // 刷新我的评论列表
          ref.read(myReviewsProvider.notifier).load(refresh: true);

          return {'progress': null, 'rating': null};
        } else {
          // 更新标记（包括进度和评分）
          await apiService.updateReviewProgress(
            workId,
            progress: result['progress'],
            rating: result['rating'],
          );

          // 构建提示消息
          final newProgress = result['progress'];
          final newRating = result['rating'];
          String message;

          if (newProgress != null && newRating != null) {
            // 同时设置了进度和评分
            final filterLabel =
                ReviewProgressDialog.getProgressLabel(newProgress);
            message = '已设置为：$filterLabel，评分：$newRating 星';
          } else if (newProgress != null) {
            // 只设置了进度
            final filterLabel =
                ReviewProgressDialog.getProgressLabel(newProgress);
            message = '已设置为：$filterLabel';
          } else if (newRating != null) {
            // 只设置了评分
            message = '评分已设置为：$newRating 星';
          } else {
            // 都没设置（理论上不应该到这里）
            message = '已更新';
          }

          if (context.mounted) {
            SnackBarUtil.showSuccess(context, message);
          }

          // 更新状态
          onChanged(result['progress'], result['rating']);

          // 刷新我的评论列表
          ref.read(myReviewsProvider.notifier).load(refresh: true);

          return result;
        }
      } catch (e) {
        if (context.mounted) {
          SnackBarUtil.showError(context, '操作失败: $e');
        }
      }
    }

    return null;
  }
}
