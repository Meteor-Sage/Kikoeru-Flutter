import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../providers/my_reviews_provider.dart';
import '../widgets/enhanced_work_card.dart';
import '../widgets/pagination_bar.dart';
import '../utils/responsive_grid_helper.dart';
import '../widgets/download_fab.dart';
import '../services/download_service.dart';
import '../models/download_task.dart';
import 'downloads_screen.dart';
import 'local_downloads_screen.dart';
import 'subtitle_library_screen.dart';
export '../providers/my_reviews_provider.dart' show MyReviewLayoutType;

class MyScreen extends ConsumerStatefulWidget {
  const MyScreen({super.key});

  @override
  ConsumerState<MyScreen> createState() => _MyScreenState();
}

class _MyScreenState extends ConsumerState<MyScreen>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  late TabController _tabController;

  @override
  bool get wantKeepAlive => true; // 保持状态不被销毁

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // 只在首次加载时获取数据，如果已有数据则不重新加载
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final myState = ref.read(myReviewsProvider);
      if (myState.works.isEmpty) {
        ref.read(myReviewsProvider.notifier).load(refresh: true);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
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
        topLeft: Radius.circular(20),
        bottomLeft: Radius.circular(20),
      );
    } else if (index == total - 1) {
      buttonBorderRadius = const BorderRadius.only(
        topRight: Radius.circular(20),
        bottomRight: Radius.circular(20),
      );
    } else {
      buttonBorderRadius = BorderRadius.zero;
    }

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: buttonBorderRadius,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                  size: 18,
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // 必须调用以保持状态

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '在线标记'),
            Tab(text: '本地下载'),
            Tab(text: '字幕库'),
          ],
        ),
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tabController,
        builder: (context, child) {
          // 在线标记页（索引0）：有下载任务时显示
          if (_tabController.index == 0) {
            return const DownloadFab();
          }
          // 本地下载页（索引1）：始终显示
          if (_tabController.index == 1) {
            return StreamBuilder<List<DownloadTask>>(
              stream: DownloadService.instance.tasksStream,
              builder: (context, snapshot) {
                final activeCount =
                    DownloadService.instance.activeDownloadCount;
                return Badge(
                  isLabelVisible: activeCount > 0,
                  label: Text('$activeCount'),
                  child: FloatingActionButton(
                    onPressed: _navigateToDownloads,
                    tooltip: '下载任务',
                    child: const Icon(Icons.download),
                  ),
                );
              },
            );
          }
          // 其他标签页：不显示
          return const SizedBox.shrink();
        },
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOnlineBookmarksTab(),
          const LocalDownloadsScreen(),
          const SubtitleLibraryScreen(),
        ],
      ),
    );
  }

  Widget _buildOnlineBookmarksTab() {
    final state = ref.watch(myReviewsProvider);
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final horizontalPadding = isLandscape ? 24.0 : 8.0;

    return Column(
      children: [
        // 筛选和布局切换工具栏
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(vertical: 4),
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withOpacity(0.5),
          child: Row(
            children: [
              // 可滚动的筛选按钮
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding, vertical: 4),
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
                          index: i,
                          total: MyReviewFilter.values.length,
                        ),
                    ],
                  ),
                ),
              ),
              // 布局切换按钮
              Padding(
                padding: EdgeInsets.only(right: horizontalPadding - 8),
                child: IconButton(
                  icon: _getLayoutIcon(state.layoutType),
                  iconSize: 22,
                  padding: const EdgeInsets.all(8),
                  constraints:
                      const BoxConstraints(minWidth: 40, minHeight: 40),
                  onPressed: () =>
                      ref.read(myReviewsProvider.notifier).toggleLayoutType(),
                  tooltip: _getLayoutTooltip(state.layoutType),
                ),
              ),
            ],
          ),
        ),
        // 内容区域
        Expanded(
          child: state.error != null
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
        ),
      ],
    );
  }

  Widget _buildBody(MyReviewsState state) {
    // 初始加载状态（没有数据时）
    if (state.isLoading && state.works.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    switch (state.layoutType) {
      case MyReviewLayoutType.bigGrid:
        return _buildGridView(
          state,
          crossAxisCount:
              ResponsiveGridHelper.getBigGridCrossAxisCount(context),
        );
      case MyReviewLayoutType.smallGrid:
        return _buildGridView(
          state,
          crossAxisCount:
              ResponsiveGridHelper.getSmallGridCrossAxisCount(context),
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
            padding: EdgeInsets.fromLTRB(padding, 8, padding, padding),
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

          // 分页控件 - 始终显示
          SliverPadding(
            padding: EdgeInsets.fromLTRB(padding, spacing, padding, 24),
            sliver: SliverToBoxAdapter(
              child: PaginationBar(
                currentPage: state.currentPage,
                totalCount: state.totalCount,
                pageSize: state.pageSize,
                hasMore: state.hasMore,
                isLoading: state.isLoading,
                onPreviousPage: () {
                  ref.read(myReviewsProvider.notifier).previousPage();
                  _scrollToTop();
                },
                onNextPage: () {
                  ref.read(myReviewsProvider.notifier).nextPage();
                  _scrollToTop();
                },
                onGoToPage: (page) {
                  ref.read(myReviewsProvider.notifier).goToPage(page);
                  _scrollToTop();
                },
              ),
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

          // 分页控件 - 始终显示
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
            sliver: SliverToBoxAdapter(
              child: PaginationBar(
                currentPage: state.currentPage,
                totalCount: state.totalCount,
                pageSize: state.pageSize,
                hasMore: state.hasMore,
                isLoading: state.isLoading,
                onPreviousPage: () {
                  ref.read(myReviewsProvider.notifier).previousPage();
                  _scrollToTop();
                },
                onNextPage: () {
                  ref.read(myReviewsProvider.notifier).nextPage();
                  _scrollToTop();
                },
                onGoToPage: (page) {
                  ref.read(myReviewsProvider.notifier).goToPage(page);
                  _scrollToTop();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
