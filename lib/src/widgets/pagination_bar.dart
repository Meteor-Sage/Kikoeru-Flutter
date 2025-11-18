import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/snackbar_util.dart';

/// 通用分页控制栏组件
class PaginationBar extends StatefulWidget {
  /// 当前页码（从1开始）
  final int currentPage;

  /// 每页大小
  final int pageSize;

  /// 总条目数
  final int totalCount;

  /// 是否有更多数据
  final bool hasMore;

  /// 是否正在加载
  final bool isLoading;

  /// 上一页回调
  final VoidCallback? onPreviousPage;

  /// 下一页回调
  final VoidCallback? onNextPage;

  /// 跳转到指定页回调
  final void Function(int page)? onGoToPage;

  /// 滚动到顶部回调（可选）
  final VoidCallback? onScrollToTop;

  /// 到底提示文字
  final String? endMessage;

  const PaginationBar({
    super.key,
    required this.currentPage,
    required this.pageSize,
    required this.totalCount,
    required this.hasMore,
    required this.isLoading,
    this.onPreviousPage,
    this.onNextPage,
    this.onGoToPage,
    this.onScrollToTop,
    this.endMessage,
  });

  @override
  State<PaginationBar> createState() => _PaginationBarState();
}

class _PaginationBarState extends State<PaginationBar> {
  final TextEditingController _pageController = TextEditingController();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  int get _maxPage =>
      widget.totalCount > 0 ? (widget.totalCount / widget.pageSize).ceil() : 1;

  /// 构建到底提示
  Widget _buildEndMessage() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Text(
            widget.endMessage ?? '已经到底啦~杂库~',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建分页按钮
  Widget _buildPageButton({
    required IconData icon,
    required String label,
    required bool enabled,
    required VoidCallback? onPressed,
    bool iconOnRight = false,
  }) {
    final iconWidget = Icon(
      icon,
      size: 18,
      color: enabled
          ? Theme.of(context).colorScheme.onPrimaryContainer
          : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
    );

    final textWidget = Text(
      label,
      style: TextStyle(
        fontSize: 13,
        color: enabled
            ? Theme.of(context).colorScheme.onPrimaryContainer
            : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
      ),
    );

    return Material(
      color: enabled
          ? Theme.of(context).colorScheme.primaryContainer
          : Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: iconOnRight
                ? [textWidget, const SizedBox(width: 4), iconWidget]
                : [iconWidget, const SizedBox(width: 4), textWidget],
          ),
        ),
      ),
    );
  }

  /// 构建页码跳转按钮
  Widget _buildPageJumpButton() {
    return Material(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => _showPageJumpDialog(),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.edit_location_alt,
                size: 18,
                color: Theme.of(context).colorScheme.onSecondaryContainer,
              ),
              const SizedBox(width: 4),
              Text(
                '跳转',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 显示页码跳转对话框
  void _showPageJumpDialog() {
    _pageController.text = widget.currentPage.toString();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('跳转到指定页'),
        content: TextField(
          controller: _pageController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: '页码 (1-$_maxPage)',
            border: const OutlineInputBorder(),
            hintText: '请输入页码',
          ),
          autofocus: true,
          onSubmitted: (_) => _handleJump(context),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => _handleJump(context),
            child: const Text('跳转'),
          ),
        ],
      ),
    );
  }

  /// 处理跳转
  void _handleJump(BuildContext dialogContext) {
    final pageStr = _pageController.text.trim();
    if (pageStr.isEmpty) {
      SnackBarUtil.showWarning(context, '请输入页码');
      return;
    }

    final targetPage = int.tryParse(pageStr);
    if (targetPage == null || targetPage < 1 || targetPage > _maxPage) {
      SnackBarUtil.showWarning(context, '请输入有效页码 (1-$_maxPage)');
      return;
    }

    if (targetPage == widget.currentPage) {
      Navigator.pop(dialogContext);
      return;
    }

    Navigator.pop(dialogContext);
    widget.onGoToPage?.call(targetPage);
    widget.onScrollToTop?.call();
  }

  @override
  Widget build(BuildContext context) {
    // 如果总数小于等于一页的大小，显示到底提示
    if (widget.totalCount <= widget.pageSize) {
      return _buildEndMessage();
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 页码和总数信息
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '第 ${widget.currentPage} / $_maxPage 页',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '共 ${widget.totalCount} 条',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 按钮组
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 上一页
              _buildPageButton(
                icon: Icons.chevron_left,
                label: '上一页',
                enabled: widget.currentPage > 1 && !widget.isLoading,
                onPressed: widget.onPreviousPage,
              ),
              const SizedBox(width: 8),

              // 跳转输入
              _buildPageJumpButton(),
              const SizedBox(width: 8),

              // 下一页
              _buildPageButton(
                label: '下一页',
                icon: Icons.chevron_right,
                enabled: widget.hasMore && !widget.isLoading,
                iconOnRight: true,
                onPressed: widget.onNextPage,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
