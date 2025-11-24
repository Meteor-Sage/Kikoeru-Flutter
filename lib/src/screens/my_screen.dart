import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../providers/my_reviews_provider.dart';
import '../providers/my_tabs_display_provider.dart';
import '../widgets/enhanced_work_card.dart';
import '../widgets/pagination_bar.dart';
import '../utils/responsive_grid_helper.dart';
import '../widgets/download_fab.dart';
import '../services/download_service.dart';
import '../models/download_task.dart';
import 'downloads_screen.dart';
import 'local_downloads_screen.dart';
import 'subtitle_library_screen.dart';
import 'playlists_screen.dart';
import '../widgets/sort_dialog.dart';
import '../models/sort_options.dart';
export '../providers/my_reviews_provider.dart' show MyReviewLayoutType;

import '../widgets/overscroll_next_page_detector.dart';

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

  List<_TabInfo> _buildTabList(MyTabsDisplaySettings settings) {
    final tabs = <_TabInfo>[];

    if (settings.showOnlineMarks) {
      tabs.add(_TabInfo(
        title: '在线标记',
        index: 0,
        widget: _buildOnlineBookmarksTab(),
        showFab: true,
        fabWidget: const DownloadFab(),
      ));
    }

    if (settings.showPlaylists) {
      tabs.add(_TabInfo(
        title: '播放列表',
        index: 1,
        widget: const PlaylistsScreen(),
      ));
    }

    // 已下载始终显示
    tabs.add(_TabInfo(
      title: '已下载',
      index: 2,
      widget: const LocalDownloadsScreen(),
      showFab: true,
      fabWidget: StreamBuilder<List<DownloadTask>>(
        stream: DownloadService.instance.tasksStream,
        builder: (context, snapshot) {
          final activeCount = DownloadService.instance.activeDownloadCount;
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
      ),
    ));

    if (settings.showSubtitleLibrary) {
      tabs.add(_TabInfo(
        title: '字幕库',
        index: 3,
        widget: const SubtitleLibraryScreen(),
      ));
    }

    return tabs;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
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
          onTap: onTap,
          borderRadius: buttonBorderRadius,
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
                    fontSize: 12,
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

  void _showSortDialog() {
    final state = ref.read(myReviewsProvider);
    showDialog(
      context: context,
      builder: (context) => CommonSortDialog(
        title: '排序方式',
        currentOption: state.sortType,
        currentDirection: state.sortOrder,
        availableOptions: const [
          SortOrder.updatedAt,
          SortOrder.release,
          SortOrder.review,
          SortOrder.dlCount,
        ],
        onSort: (option, direction) {
          ref.read(myReviewsProvider.notifier).changeSort(option, direction);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // 必须调用以保持状态

    final tabsSettings = ref.watch(myTabsDisplayProvider);
    final tabs = _buildTabList(tabsSettings);

    // 如果标签数量变化，需要重新创建 TabController
    if (_tabController.length != tabs.length) {
      final oldIndex = _tabController.index;
      _tabController.dispose();
      _tabController = TabController(length: tabs.length, vsync: this);
      // 尝试恢复之前的位置，但不超出新的范围
      if (oldIndex < tabs.length) {
        _tabController.index = oldIndex;
      }
    }

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: tabs.map((tab) => Tab(text: tab.title)).toList(),
        ),
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tabController,
        builder: (context, child) {
          final currentIndex = _tabController.index;
          if (currentIndex >= 0 && currentIndex < tabs.length) {
            final currentTab = tabs[currentIndex];
            if (currentTab.showFab && currentTab.fabWidget != null) {
              return currentTab.fabWidget!;
            }
          }
          return const SizedBox.shrink();
        },
      ),
      body: TabBarView(
        controller: _tabController,
        children: tabs.map((tab) => tab.widget).toList(),
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
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.sort),
                      iconSize: 22,
                      padding: const EdgeInsets.all(8),
                      constraints:
                          const BoxConstraints(minWidth: 40, minHeight: 40),
                      onPressed: _showSortDialog,
                      tooltip: '排序',
                    ),
                    IconButton(
                      icon: _getLayoutIcon(state.layoutType),
                      iconSize: 22,
                      padding: const EdgeInsets.all(8),
                      constraints:
                          const BoxConstraints(minWidth: 40, minHeight: 40),
                      onPressed: () => ref
                          .read(myReviewsProvider.notifier)
                          .toggleLayoutType(),
                      tooltip: _getLayoutTooltip(state.layoutType),
                    ),
                  ],
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
                        state.error!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () =>
                            ref.read(myReviewsProvider.notifier).refresh(),
                        icon: const Icon(Icons.refresh),
                        label: const Text('重试'),
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
      child: OverscrollNextPageDetector(
        hasNextPage: state.hasMore,
        isLoading: state.isLoading,
        onNextPage: () async {
          await ref.read(myReviewsProvider.notifier).nextPage();
          // 等待一帧后滚动到顶部，确保内容已加载
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToTop();
          });
        },
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
      ),
    );
  }

  Widget _buildListView(MyReviewsState state) {
    return RefreshIndicator(
      onRefresh: () async => ref.read(myReviewsProvider.notifier).refresh(),
      child: OverscrollNextPageDetector(
        hasNextPage: state.hasMore,
        isLoading: state.isLoading,
        onNextPage: () async {
          await ref.read(myReviewsProvider.notifier).nextPage();
          // 等待一帧后滚动到顶部，确保内容已加载
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToTop();
          });
        },
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
      ),
    );
  }
}

// Helper class to organize tab information
class _TabInfo {
  final String title;
  final int index;
  final Widget widget;
  final bool showFab;
  final Widget? fabWidget;

  const _TabInfo({
    required this.title,
    required this.index,
    required this.widget,
    this.showFab = false,
    this.fabWidget,
  });
}
