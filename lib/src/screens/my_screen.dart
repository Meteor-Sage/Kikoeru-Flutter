import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../providers/my_reviews_provider.dart';
import '../widgets/enhanced_work_card.dart';
import '../widgets/responsive_dialog.dart';
import 'downloads_screen.dart';
export '../providers/my_reviews_provider.dart' show MyReviewLayoutType;

class MyScreen extends ConsumerStatefulWidget {
  const MyScreen({super.key});

  @override
  ConsumerState<MyScreen> createState() => _MyScreenState();
}

class _MyScreenState extends ConsumerState<MyScreen>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _pageController = TextEditingController();
  bool _showPagination = false;
  Timer? _scrollDebouncer;
  double _lastScrollPosition = 0.0;

  @override
  bool get wantKeepAlive => true; // 保持状态不被销毁

  @override
  void initState() {
    super.initState();
    // 只在首次加载时获取数据，如果已有数据则不重新加载
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final myState = ref.read(myReviewsProvider);
      if (myState.works.isEmpty) {
        ref.read(myReviewsProvider.notifier).load(refresh: true);
      }
    });
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final scrollPosition = _scrollController.position.pixels;
    final scrollDelta = (scrollPosition - _lastScrollPosition).abs();

    // 过滤小幅度滚动，减少不必要的处理
    if (scrollDelta < 10) return;

    _lastScrollPosition = scrollPosition;

    // 使用防抖处理滚动事件
    _scrollDebouncer?.cancel();
    _scrollDebouncer = Timer(const Duration(milliseconds: 150), () {
      if (!mounted || !_scrollController.hasClients) return;

      final isNearBottom = _scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200;

      // 显示/隐藏分页控件
      if (isNearBottom != _showPagination) {
        setState(() {
          _showPagination = isNearBottom;
        });
      }
    });
  }

  @override
  void dispose() {
    _scrollDebouncer?.cancel();
    _scrollController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  void _navigateToDownloads() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const DownloadsScreen(),
      ),
    );
  }

  // 分页控制栏
  Widget _buildPaginationBar(MyReviewsState state) {
    final maxPage =
        state.totalCount > 0 ? (state.totalCount / state.pageSize).ceil() : 1;

    // 如果总数小于等于20，显示到底提示
    if (state.totalCount <= 20) {
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
              '已经到底啦~杂库~',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
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
                '第 ${state.currentPage} / $maxPage 页',
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
                  '共 ${state.totalCount} 条',
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
                enabled: state.currentPage > 1 && !state.isLoading,
                onPressed: () {
                  ref.read(myReviewsProvider.notifier).previousPage();
                  _scrollToTop();
                },
              ),
              const SizedBox(width: 8),

              // 跳转输入
              _buildPageJumpButton(state, maxPage),
              const SizedBox(width: 8),

              // 下一页
              _buildPageButton(
                label: '下一页',
                icon: Icons.chevron_right,
                enabled: state.hasMore && !state.isLoading,
                iconOnRight: true,
                onPressed: () {
                  ref.read(myReviewsProvider.notifier).nextPage();
                  _scrollToTop();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 分页按钮
  Widget _buildPageButton({
    required IconData icon,
    required String label,
    required bool enabled,
    required VoidCallback onPressed,
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

  // 页码跳转按钮
  Widget _buildPageJumpButton(MyReviewsState state, int maxPage) {
    return Material(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => _showPageJumpDialog(state, maxPage),
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

  // 显示页码跳转对话框
  void _showPageJumpDialog(MyReviewsState state, int maxPage) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    showDialog(
      context: context,
      barrierDismissible: !Platform.isIOS, // iOS 上防止点击外部区域意外关闭
      builder: (context) {
        final dialog = ResponsiveAlertDialog(
          title: const Text('跳转到指定页'),
          content: TextField(
            controller: _pageController,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(
              labelText: '页码',
              hintText: '输入 1-$maxPage',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.tag),
            ),
            onSubmitted: (value) {
              Navigator.of(context).pop();
              _handlePageJump(value, maxPage);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                _handlePageJump(_pageController.text, maxPage);
              },
              child: const Text('跳转'),
            ),
          ],
        );

        // 横屏时移除底部视图插入（键盘），让对话框保持固定位置
        return isLandscape
            ? MediaQuery.removeViewInsets(
                removeBottom: true,
                context: context,
                child: dialog,
              )
            : dialog;
      },
    );
  }

  // 处理页码跳转
  void _handlePageJump(String value, int maxPage) {
    final page = int.tryParse(value);
    if (page != null && page > 0 && page <= maxPage) {
      ref.read(myReviewsProvider.notifier).goToPage(page);
      _pageController.clear();
      _scrollToTop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('请输入 1-$maxPage 之间的页码'),
          duration: const Duration(seconds: 2),
        ),
      );
      _pageController.clear();
    }
  }

  Icon _getLayoutIcon(MyReviewLayoutType layoutType) {
    switch (layoutType) {
      case MyReviewLayoutType.bigGrid:
        return const Icon(Icons.grid_3x3);
      case MyReviewLayoutType.smallGrid:
        return const Icon(Icons.view_list);
      case MyReviewLayoutType.list:
        return const Icon(Icons.view_agenda);
    }
  }

  String _getLayoutTooltip(MyReviewLayoutType layoutType) {
    switch (layoutType) {
      case MyReviewLayoutType.bigGrid:
        return '切换到小网格视图';
      case MyReviewLayoutType.smallGrid:
        return '切换到列表视图';
      case MyReviewLayoutType.list:
        return '切换到大网格视图';
    }
  }

  IconData _getFilterIcon(MyReviewFilter filter) {
    switch (filter) {
      case MyReviewFilter.all:
        return Icons.all_inclusive;
      case MyReviewFilter.marked:
        return Icons.bookmark;
      case MyReviewFilter.listening:
        return Icons.headphones;
      case MyReviewFilter.listened:
        return Icons.check_circle;
      case MyReviewFilter.replay:
        return Icons.replay;
      case MyReviewFilter.postponed:
        return Icons.schedule;
    }
  }

  Widget _buildFilterButton({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    BorderRadius? borderRadius,
  }) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius ?? BorderRadius.zero,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: borderRadius ?? BorderRadius.zero,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isSelected
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // 必须调用以保持状态
    final state = ref.watch(myReviewsProvider);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 48, // 设置工具栏高度
        flexibleSpace: SafeArea(
          child: Row(
            children: [
              // 第一列：可滚动的筛选按钮
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    children: [
                      for (int i = 0; i < MyReviewFilter.values.length; i++)
                        _buildFilterButton(
                          icon: _getFilterIcon(MyReviewFilter.values[i]),
                          label: MyReviewFilter.values[i].label,
                          isSelected: state.filter == MyReviewFilter.values[i],
                          onTap: () => ref
                              .read(myReviewsProvider.notifier)
                              .changeFilter(MyReviewFilter.values[i]),
                          borderRadius: i == 0
                              ? const BorderRadius.horizontal(
                                  left: Radius.circular(6))
                              : i == MyReviewFilter.values.length - 1
                                  ? const BorderRadius.horizontal(
                                      right: Radius.circular(6))
                                  : null,
                        ),
                    ],
                  ),
                ),
              ),
              // 下载管理按钮
              IconButton(
                icon: const Icon(Icons.download),
                iconSize: 22,
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                onPressed: _navigateToDownloads,
                tooltip: '下载管理',
              ),
              // 第二列：布局切换按钮
              IconButton(
                icon: _getLayoutIcon(state.layoutType),
                iconSize: 22,
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                onPressed: () =>
                    ref.read(myReviewsProvider.notifier).toggleLayoutType(),
                tooltip: _getLayoutTooltip(state.layoutType),
              ),
            ],
          ),
        ),
      ),
      body: state.error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('加载失败: ${state.error}',
                      style: const TextStyle(color: Colors.redAccent)),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () =>
                        ref.read(myReviewsProvider.notifier).refresh(),
                    child: const Text('重试'),
                  ),
                ],
              ),
            )
          : Stack(
              children: [
                _buildBody(state),
                // 全局加载动画 - 在有数据且正在刷新时显示顶部进度条
                if (state.isLoading && state.works.isNotEmpty)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SizedBox(
                      height: 3,
                      child: const LinearProgressIndicator(),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildBody(MyReviewsState state) {
    // 初始加载状态（没有数据时）
    if (state.isLoading && state.works.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    switch (state.layoutType) {
      case MyReviewLayoutType.bigGrid:
        return _buildGridView(
          state,
          crossAxisCount: isLandscape ? 3 : 2,
        );
      case MyReviewLayoutType.smallGrid:
        return _buildGridView(
          state,
          crossAxisCount: isLandscape ? 5 : 3,
        );
      case MyReviewLayoutType.list:
        return _buildListView(state);
    }
  }

  Widget _buildGridView(MyReviewsState state, {required int crossAxisCount}) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    // 横屏模式下使用更大的间距，让布局更优雅
    final spacing = isLandscape ? 24.0 : 8.0;
    final padding = isLandscape ? 24.0 : 8.0;

    return RefreshIndicator(
      onRefresh: () async => ref.read(myReviewsProvider.notifier).refresh(),
      child: CustomScrollView(
        controller: _scrollController,
        cacheExtent: 500,
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.all(padding),
            sliver: SliverMasonryGrid.count(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: spacing,
              crossAxisSpacing: spacing,
              childCount: state.works.length,
              itemBuilder: (context, index) {
                final work = state.works[index];
                return RepaintBoundary(
                  child: EnhancedWorkCard(
                      work: work, crossAxisCount: crossAxisCount),
                );
              },
            ),
          ),

          // 分页控件
          if (_showPagination)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(padding, spacing, padding, 24),
              sliver: SliverToBoxAdapter(
                child: _buildPaginationBar(state),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildListView(MyReviewsState state) {
    return RefreshIndicator(
      onRefresh: () async => ref.read(myReviewsProvider.notifier).refresh(),
      child: CustomScrollView(
        controller: _scrollController,
        cacheExtent: 500,
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(8),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final work = state.works[index];
                  return RepaintBoundary(
                    child: EnhancedWorkCard(work: work, crossAxisCount: 1),
                  );
                },
                childCount: state.works.length,
              ),
            ),
          ),

          // 分页控件
          if (_showPagination)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
              sliver: SliverToBoxAdapter(
                child: _buildPaginationBar(state),
              ),
            ),
        ],
      ),
    );
  }
}
