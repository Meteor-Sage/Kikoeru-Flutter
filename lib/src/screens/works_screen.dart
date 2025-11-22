import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../providers/works_provider.dart';
import '../widgets/enhanced_work_card.dart';
import '../widgets/sort_dialog.dart';
import '../widgets/pagination_bar.dart';
import '../utils/responsive_grid_helper.dart';
import '../utils/snackbar_util.dart';
import '../widgets/scrollable_appbar.dart';
import '../widgets/download_fab.dart';

class WorksScreen extends ConsumerStatefulWidget {
  const WorksScreen({super.key});

  @override
  ConsumerState<WorksScreen> createState() => _WorksScreenState();
}

class _WorksScreenState extends ConsumerState<WorksScreen>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();

  // 防抖相关（仅用于热门/推荐模式的自动加载）
  Timer? _scrollDebouncer;
  bool _isLoadingMore = false;
  double _lastScrollPosition = 0;

  @override
  bool get wantKeepAlive => true; // 保持状态不被销毁

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // 只在首次加载时获取数据，如果已有数据则不重新加载
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final worksState = ref.read(worksProvider);
      if (worksState.works.isEmpty) {
        ref.read(worksProvider.notifier).loadWorks(refresh: true);
      }
    });
  }

  @override
  void dispose() {
    _scrollDebouncer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // 使用防抖机制,避免频繁调用
    if (!_scrollController.hasClients) return;

    final currentPosition = _scrollController.position.pixels;
    final maxScrollExtent = _scrollController.position.maxScrollExtent;

    // 防止重复触发 - 如果滚动位置变化小于 10 像素则不处理
    if ((currentPosition - _lastScrollPosition).abs() < 10) return;
    _lastScrollPosition = currentPosition;

    final worksState = ref.read(worksProvider);
    final isNearBottom = currentPosition >= maxScrollExtent - 50;

    // 取消之前的防抖计时器
    _scrollDebouncer?.cancel();

    // 热门/推荐模式:自动加载更多（全部模式不需要处理，因为分页控件始终显示）
    if (worksState.displayMode != DisplayMode.all) {
      if (isNearBottom &&
          !worksState.isLoading &&
          worksState.hasMore &&
          !_isLoadingMore) {
        print(
            '[WorksScreen] Triggering load more - currentPage: ${worksState.currentPage}');
        _isLoadingMore = true;

        // 立即执行加载，不使用 Timer
        ref.read(worksProvider.notifier).loadWorks().then((_) {
          if (mounted) {
            setState(() {
              _isLoadingMore = false;
            });
            print('[WorksScreen] Load more completed');
          }
        }).catchError((error) {
          if (mounted) {
            setState(() {
              _isLoadingMore = false;
            });
            print('[WorksScreen] Load more error: $error');
          }
        });
      }
    }
  }

  void _showSortDialog(BuildContext context) {
    final displayMode = ref.read(worksProvider).displayMode;
    final isRecommendMode = displayMode == DisplayMode.popular ||
        displayMode == DisplayMode.recommended;

    if (isRecommendMode) {
      SnackBarUtil.showInfo(
        context,
        displayMode == DisplayMode.popular ? '热门推荐模式不支持排序' : '推荐模式不支持排序',
      );
      return;
    }

    final state = ref.read(worksProvider);
    showDialog(
      context: context,
      barrierDismissible: !Platform.isIOS, // iOS 上防止点击外部区域意外关闭
      builder: (context) => CommonSortDialog(
        currentOption: state.sortOption,
        currentDirection: state.sortDirection,
        onSort: (option, direction) {
          ref.read(worksProvider.notifier).setSortOption(option);
          ref.read(worksProvider.notifier).setSortDirection(direction);
        },
        autoClose: true,
      ),
    );
  }

  Icon _getLayoutIcon(LayoutType layoutType) {
    switch (layoutType) {
      case LayoutType.bigGrid:
        return const Icon(Icons.grid_3x3);
      case LayoutType.smallGrid:
        return const Icon(Icons.view_list);
      case LayoutType.list:
        return const Icon(Icons.view_agenda);
    }
  }

  String _getLayoutTooltip(LayoutType layoutType) {
    switch (layoutType) {
      case LayoutType.bigGrid:
        return '切换到小网格视图';
      case LayoutType.smallGrid:
        return '切换到列表视图';
      case LayoutType.list:
        return '切换到大网格视图';
    }
  }

  void _handleSwipe(DragEndDetails details) {
    if (details.primaryVelocity == null) return;

    final velocity = details.primaryVelocity!;
    final worksState = ref.read(worksProvider);
    final notifier = ref.read(worksProvider.notifier);

    // Sensitivity threshold
    if (velocity.abs() < 500) return;

    if (velocity < 0) {
      // Swipe Left (Next Tab)
      if (worksState.displayMode == DisplayMode.all) {
        notifier.setDisplayMode(DisplayMode.popular);
        _scrollToTop();
      } else if (worksState.displayMode == DisplayMode.popular) {
        notifier.setDisplayMode(DisplayMode.recommended);
        _scrollToTop();
      }
    } else {
      // Swipe Right (Previous Tab)
      if (worksState.displayMode == DisplayMode.recommended) {
        notifier.setDisplayMode(DisplayMode.popular);
        _scrollToTop();
      } else if (worksState.displayMode == DisplayMode.popular) {
        notifier.setDisplayMode(DisplayMode.all);
        _scrollToTop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // 必须调用以保持状态
    final worksState = ref.watch(worksProvider);
    final isRecommendMode = worksState.displayMode == DisplayMode.popular ||
        worksState.displayMode == DisplayMode.recommended;

    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final horizontalPadding = isLandscape ? 24.0 : 8.0;

    return Scaffold(
      floatingActionButton: const DownloadFab(),
      appBar: ScrollableAppBar(
        toolbarHeight: 56,
        flexibleSpace: SafeArea(
          child: Row(
            children: [
              // 第一列：可滚动的模式切换按钮
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding, vertical: 8),
                  child: _buildModeButtons(context, worksState),
                ),
              ),
              // 分隔线
              Container(
                height: 28,
                width: 1,
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withOpacity(0.5),
                margin: const EdgeInsets.symmetric(horizontal: 2),
              ),
              // 第二列：布局切换按钮
              IconButton(
                icon: _getLayoutIcon(worksState.layoutType),
                iconSize: 22,
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: () =>
                    ref.read(worksProvider.notifier).toggleLayoutType(),
                tooltip: _getLayoutTooltip(worksState.layoutType),
              ),
              // 第三列：字幕筛选按钮
              IconButton(
                icon: Icon(
                  worksState.subtitleFilter == 1
                      ? Icons.closed_caption
                      : Icons.closed_caption_disabled,
                  color: worksState.subtitleFilter == 1
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                iconSize: 22,
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: () =>
                    ref.read(worksProvider.notifier).toggleSubtitleFilter(),
                tooltip: worksState.subtitleFilter == 1 ? '显示全部作品' : '仅显示带字幕作品',
              ),
              // 第四列：排序按钮
              Padding(
                padding: EdgeInsets.only(right: horizontalPadding - 6),
                child: IconButton(
                  icon: Icon(
                    Icons.sort,
                    color: isRecommendMode ? Colors.grey : null,
                  ),
                  iconSize: 22,
                  padding: const EdgeInsets.all(6),
                  constraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
                  onPressed:
                      isRecommendMode ? null : () => _showSortDialog(context),
                  tooltip: isRecommendMode ? '推荐模式不支持排序' : '排序',
                ),
              ),
            ],
          ),
        ),
      ),
      body: GestureDetector(
        onHorizontalDragEnd: _handleSwipe,
        child: _buildBody(worksState),
      ),
    );
  }

  /// ===== 构建「全部 / 热门 / 推荐」按钮组 =====
  Widget _buildModeButtons(BuildContext context, WorksState worksState) {
    final notifier = ref.read(worksProvider.notifier);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildModeButton(
          context: context,
          icon: Icons.grid_view,
          label: '全部',
          isSelected: worksState.displayMode == DisplayMode.all,
          index: 0,
          total: 3,
          onTap: () {
            notifier.setDisplayMode(DisplayMode.all);
            _scrollToTop();
          },
        ),
        _buildModeButton(
          context: context,
          icon: Icons.local_fire_department,
          label: '热门',
          isSelected: worksState.displayMode == DisplayMode.popular,
          index: 1,
          total: 3,
          onTap: () {
            notifier.setDisplayMode(DisplayMode.popular);
            _scrollToTop();
          },
        ),
        _buildModeButton(
          context: context,
          icon: Icons.auto_awesome,
          label: '推荐',
          isSelected: worksState.displayMode == DisplayMode.recommended,
          index: 2,
          total: 3,
          onTap: () {
            notifier.setDisplayMode(DisplayMode.recommended);
            _scrollToTop();
          },
        ),
      ],
    );
  }

  /// ===== 单个模式按钮样式封装 =====
  Widget _buildModeButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required int index,
    required int total,
  }) {
    final theme = Theme.of(context);

    // 第一个按钮：左侧圆角，右侧方角
    // 最后一个按钮：左侧方角，右侧圆角
    // 中间按钮：两侧方角
    BorderRadius buttonBorderRadius;
    if (index == 0) {
      buttonBorderRadius = const BorderRadius.only(
        topLeft: Radius.circular(16),
        bottomLeft: Radius.circular(16),
      );
    } else if (index == total - 1) {
      buttonBorderRadius = const BorderRadius.only(
        topRight: Radius.circular(16),
        bottomRight: Radius.circular(16),
      );
    } else {
      buttonBorderRadius = BorderRadius.zero;
    }

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: buttonBorderRadius,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: isSelected
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: buttonBorderRadius,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(WorksState worksState) {
    // 错误状态或空状态 - 统一显示
    if (worksState.works.isEmpty) {
      // 如果有错误，显示错误信息
      if (worksState.error != null) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                '加载失败',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                worksState.error!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => ref.read(worksProvider.notifier).refresh(),
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        );
      }

      // 加载中
      if (worksState.isLoading) {
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('加载中...'),
            ],
          ),
        );
      }

      // 空状态
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.audiotrack,
                size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              '暂无作品',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '请检查网络连接或稍后重试',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(worksProvider.notifier).refresh(),
      child: Stack(
        children: [
          _buildLayoutView(worksState),
          // 全局加载动画 - 在有数据且正在刷新时显示
          if (worksState.isLoading && worksState.works.isNotEmpty)
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

  Widget _buildLayoutView(WorksState worksState) {
    switch (worksState.layoutType) {
      case LayoutType.bigGrid:
        return _buildGridView(
          worksState,
          crossAxisCount:
              ResponsiveGridHelper.getBigGridCrossAxisCount(context),
        );
      case LayoutType.smallGrid:
        return _buildGridView(
          worksState,
          crossAxisCount:
              ResponsiveGridHelper.getSmallGridCrossAxisCount(context),
        );
      case LayoutType.list:
        return _buildListView(worksState);
    }
  }

  Widget _buildGridView(WorksState worksState, {required int crossAxisCount}) {
    final isAllMode = worksState.displayMode == DisplayMode.all;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    // 横屏模式下使用更大的间距，让布局更优雅
    final spacing = isLandscape ? 24.0 : 8.0;
    final padding = isLandscape ? 24.0 : 8.0;

    return CustomScrollView(
      controller: _scrollController,
      cacheExtent: 500, // 增加缓存范围，预加载更多内容
      physics: const AlwaysScrollableScrollPhysics(
        parent: ClampingScrollPhysics(), // 使用更流畅的物理滚动
      ),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.all(padding),
          sliver: SliverMasonryGrid.count(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childCount: worksState.works.length +
                (!isAllMode && worksState.hasMore ? 1 : 0),
            itemBuilder: (context, index) {
              // 热门/推荐模式:在底部显示加载指示器
              if (!isAllMode && index == worksState.works.length) {
                return const SizedBox(
                  height: 100, // 统一加载指示器高度
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final work = worksState.works[index];
              return RepaintBoundary(
                child: EnhancedWorkCard(
                  work: work,
                  crossAxisCount: crossAxisCount,
                ),
              );
            },
          ),
        ),

        // 热门/推荐模式:到底提示
        if (!isAllMode && worksState.isLastPage)
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
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
            ),
          ),

        // 全部模式:分页控件(集成在瀑布流中) - 始终显示
        if (isAllMode)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(padding, spacing, padding, 24),
            sliver: SliverToBoxAdapter(
              child: PaginationBar(
                currentPage: worksState.currentPage,
                totalCount: worksState.totalCount,
                pageSize: worksState.pageSize,
                hasMore: worksState.hasMore,
                isLoading: worksState.isLoading,
                onPreviousPage: () {
                  ref.read(worksProvider.notifier).previousPage();
                  _scrollToTop();
                },
                onNextPage: () {
                  ref.read(worksProvider.notifier).nextPage();
                  _scrollToTop();
                },
                onGoToPage: (page) {
                  ref.read(worksProvider.notifier).goToPage(page);
                  _scrollToTop();
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildListView(WorksState worksState) {
    final isAllMode = worksState.displayMode == DisplayMode.all;

    return CustomScrollView(
      controller: _scrollController,
      cacheExtent: 500, // 增加缓存范围，预加载更多内容
      physics: const AlwaysScrollableScrollPhysics(
        parent: ClampingScrollPhysics(), // 使用更流畅的物理滚动
      ),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(8),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                // 热门/推荐模式:加载指示器
                if (!isAllMode &&
                    index == worksState.works.length &&
                    worksState.hasMore) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                // 热门/推荐模式:到底提示
                if (!isAllMode &&
                    index == worksState.works.length &&
                    worksState.isLastPage) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 24, horizontal: 16),
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
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final work = worksState.works[index];
                return RepaintBoundary(
                  child: EnhancedWorkCard(
                    work: work,
                    crossAxisCount: 1, // 列表视图
                  ),
                );
              },
              childCount: worksState.works.length +
                  (!isAllMode && worksState.hasMore ? 1 : 0) +
                  (!isAllMode && worksState.isLastPage ? 1 : 0),
            ),
          ),
        ),

        // 全部模式:分页控件(集成在列表中) - 始终显示
        if (isAllMode)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 24), // 统一左右padding为8
            sliver: SliverToBoxAdapter(
              child: PaginationBar(
                currentPage: worksState.currentPage,
                totalCount: worksState.totalCount,
                pageSize: worksState.pageSize,
                hasMore: worksState.hasMore,
                isLoading: worksState.isLoading,
                onPreviousPage: () {
                  ref.read(worksProvider.notifier).previousPage();
                  _scrollToTop();
                },
                onNextPage: () {
                  ref.read(worksProvider.notifier).nextPage();
                  _scrollToTop();
                },
                onGoToPage: (page) {
                  ref.read(worksProvider.notifier).goToPage(page);
                  _scrollToTop();
                },
              ),
            ),
          ),
      ],
    );
  }

  // 滚动到顶部
  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }
}
