import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:equatable/equatable.dart';

import '../models/work.dart';
import '../services/kikoeru_api_service.dart' hide kikoeruApiServiceProvider;
import 'auth_provider.dart';
import '../models/sort_options.dart';

// Display mode - 展示模式
enum DisplayMode {
  all('all', '全部作品'),
  popular('popular', '热门推荐'),
  recommended('recommended', '推荐');

  const DisplayMode(this.value, this.label);
  final String value;
  final String label;
}

// Layout types - 参考原始代码的三种布局
enum LayoutType {
  list, // 列表布局
  smallGrid, // 小网格布局 (3列)
  bigGrid // 大网格布局 (2列)
}

// Works state
class WorksState extends Equatable {
  final List<Work> works;
  final bool isLoading;
  final String? error;
  final int currentPage;
  final int totalCount;
  final bool hasMore;
  final LayoutType layoutType;
  final SortOrder sortOption;
  final SortDirection sortDirection;
  final DisplayMode displayMode;
  final int subtitleFilter; // 0: 全部, 1: 仅带字幕
  final int pageSize; // 每页数量
  final bool isLastPage; // 是否是最后一页(用于热门/推荐的100条限制提示)

  const WorksState({
    this.works = const [],
    this.isLoading = false,
    this.error,
    this.currentPage = 1,
    this.totalCount = 0,
    this.hasMore = true,
    this.layoutType = LayoutType.bigGrid, // 默认大网格布局
    this.sortOption = SortOrder.createDate,
    this.sortDirection = SortDirection.desc,
    this.displayMode = DisplayMode.all, // 默认显示全部作品
    this.subtitleFilter = 0, // 默认显示全部
    this.pageSize = 30, // 全部模式每页30条
    this.isLastPage = false,
  });

  WorksState copyWith({
    List<Work>? works,
    bool? isLoading,
    String? error,
    int? currentPage,
    int? totalCount,
    bool? hasMore,
    LayoutType? layoutType,
    SortOrder? sortOption,
    SortDirection? sortDirection,
    DisplayMode? displayMode,
    int? subtitleFilter,
    int? pageSize,
    bool? isLastPage,
  }) {
    return WorksState(
      works: works ?? this.works,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      currentPage: currentPage ?? this.currentPage,
      totalCount: totalCount ?? this.totalCount,
      hasMore: hasMore ?? this.hasMore,
      layoutType: layoutType ?? this.layoutType,
      sortOption: sortOption ?? this.sortOption,
      sortDirection: sortDirection ?? this.sortDirection,
      displayMode: displayMode ?? this.displayMode,
      subtitleFilter: subtitleFilter ?? this.subtitleFilter,
      pageSize: pageSize ?? this.pageSize,
      isLastPage: isLastPage ?? this.isLastPage,
    );
  }

  @override
  List<Object?> get props => [
        works,
        isLoading,
        error,
        currentPage,
        totalCount,
        hasMore,
        layoutType,
        sortOption,
        sortDirection,
        displayMode,
        subtitleFilter,
        pageSize,
        isLastPage,
      ];
}

// Works notifier
class WorksNotifier extends StateNotifier<WorksState> {
  final KikoeruApiService _apiService;
  final Ref _ref;

  WorksNotifier(this._apiService, this._ref) : super(const WorksState());

  Future<void> loadWorks({bool refresh = false, int? targetPage}) async {
    if (state.isLoading) {
      print('[WorksProvider] Already loading, skipping');
      return;
    }

    // 全部模式使用分页,热门/推荐使用滚动加载
    final isAllMode = state.displayMode == DisplayMode.all;
    final page = isAllMode
        ? (targetPage ?? (refresh ? 1 : state.currentPage))
        : (refresh ? 1 : (state.currentPage + 1));

    print(
        '[WorksProvider] Loading works - mode: ${state.displayMode}, page: $page, refresh: $refresh, currentPage: ${state.currentPage}');

    state = state.copyWith(
      isLoading: true,
      error: null,
    );

    try {
      Map<String, dynamic> response;

      // 根据显示模式设置每页数量
      final pageSize = isAllMode ? 30 : 20;

      // 根据显示模式选择不同的API
      if (state.displayMode == DisplayMode.popular) {
        response = await _apiService.getPopularWorks(
          page: page,
          pageSize: pageSize,
          subtitle: state.subtitleFilter,
        );
      } else if (state.displayMode == DisplayMode.recommended) {
        final currentUser = _ref.read(authProvider).currentUser;
        final recommenderUuid = currentUser?.recommenderUuid ??
            '766cc58d-7f1e-4958-9a93-913400f378dc';

        response = await _apiService.getRecommendedWorks(
          recommenderUuid: recommenderUuid,
          page: page,
          pageSize: pageSize,
          subtitle: state.subtitleFilter,
        );
      } else {
        response = await _apiService.getWorks(
          page: page,
          order: state.sortOption.value,
          sort: state.sortDirection.value,
          subtitle: state.subtitleFilter,
        );
      }

      final worksData = response['works'] as List<dynamic>?;
      final pagination = response['pagination'] as Map<String, dynamic>?;

      if (worksData == null) {
        throw Exception('No works data in response');
      }

      final works = worksData
          .map((workJson) => Work.fromJson(workJson as Map<String, dynamic>))
          .toList();

      final totalCount = pagination?['totalCount'] as int? ?? 0;
      final currentPage = pagination?['currentPage'] as int? ?? page;

      bool hasMore;
      bool isLastPage = false;

      if (state.displayMode == DisplayMode.popular ||
          state.displayMode == DisplayMode.recommended) {
        // 热门/推荐模式: 滚动加载,最多100条
        final currentTotal =
            refresh ? works.length : state.works.length + works.length;
        hasMore = works.length >= pageSize &&
            currentTotal < 100 &&
            currentTotal < totalCount;
        isLastPage = !hasMore && works.isNotEmpty;
      } else {
        // 全部模式: 分页
        hasMore = (currentPage * pageSize) < totalCount;
        isLastPage = !hasMore && works.isNotEmpty;
      }

      // 全部模式:替换数据; 热门/推荐:累加数据
      final newWorks =
          isAllMode || refresh ? works : [...state.works, ...works];

      print(
          '[WorksProvider] Loaded ${works.length} works, total: ${newWorks.length}, hasMore: $hasMore, currentPage: $currentPage');

      state = state.copyWith(
        works: newWorks,
        isLoading: false,
        currentPage: currentPage,
        totalCount: totalCount,
        hasMore: hasMore,
        pageSize: pageSize,
        isLastPage: isLastPage,
      );
    } catch (e) {
      print('Failed to load works: $e');

      // 如果是首次加载失败（没有数据），在短暂延迟后自动重试一次
      if (state.works.isEmpty && refresh) {
        print('Initial load failed, will retry in 1 second...');
        state = state.copyWith(
          isLoading: false,
          error: '加载中，请稍候...',
        );

        // 延迟1秒后重试
        await Future.delayed(const Duration(seconds: 1));

        // 只重试一次，通过检查错误信息避免无限重试
        if (!state.error!.contains('重试失败')) {
          print('Retrying initial load...');
          state = state.copyWith(
            isLoading: true,
            error: null,
          );

          try {
            // 重试加载
            await loadWorks(refresh: true);
            return;
          } catch (retryError) {
            print('Retry failed: $retryError');
            state = state.copyWith(
              isLoading: false,
              error: '加载失败，请下拉刷新重试 (重试失败: ${retryError.toString()})',
            );
            return;
          }
        }
      }

      state = state.copyWith(
        isLoading: false,
        error: '加载失败: ${e.toString()}',
      );
    }
  }

  Future<void> refresh() async {
    await loadWorks(refresh: true);
  }

  // 跳转到指定页(仅全部模式)
  Future<void> goToPage(int page) async {
    if (state.displayMode != DisplayMode.all) return;
    if (page < 1) return;

    // 检查页码是否超出范围
    final maxPage = (state.totalCount / state.pageSize).ceil();
    if (page > maxPage && maxPage > 0) return;

    await loadWorks(targetPage: page);
  }

  // 下一页(仅全部模式)
  Future<void> nextPage() async {
    if (state.displayMode != DisplayMode.all) return;
    if (!state.hasMore || state.isLoading) return;
    await loadWorks(targetPage: state.currentPage + 1);
  }

  // 上一页(仅全部模式)
  Future<void> previousPage() async {
    if (state.displayMode != DisplayMode.all) return;
    if (state.currentPage <= 1 || state.isLoading) return;
    await loadWorks(targetPage: state.currentPage - 1);
  }

  void setSortOption(SortOrder option) {
    if (state.sortOption != option) {
      state = state.copyWith(sortOption: option);
      refresh();
    }
  }

  void setSortDirection(SortDirection direction) {
    if (state.sortDirection != direction) {
      state = state.copyWith(sortDirection: direction);
      refresh();
    }
  }

  void toggleSortDirection() {
    final newDirection = state.sortDirection == SortDirection.asc
        ? SortDirection.desc
        : SortDirection.asc;
    setSortDirection(newDirection);
  }

  void setLayoutType(LayoutType layoutType) {
    state = state.copyWith(layoutType: layoutType);
  }

  void toggleLayoutType() {
    late LayoutType newLayoutType;
    switch (state.layoutType) {
      case LayoutType.bigGrid:
        newLayoutType = LayoutType.smallGrid;
        break;
      case LayoutType.smallGrid:
        newLayoutType = LayoutType.list;
        break;
      case LayoutType.list:
        newLayoutType = LayoutType.bigGrid;
        break;
    }
    setLayoutType(newLayoutType);
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  // Switch between all works and popular works
  void setDisplayMode(DisplayMode mode) {
    if (state.displayMode != mode) {
      state = state.copyWith(displayMode: mode);
      refresh();
    }
  }

  // Toggle subtitle filter
  void toggleSubtitleFilter() {
    final newFilter = state.subtitleFilter == 0 ? 1 : 0;
    state = state.copyWith(subtitleFilter: newFilter);
    refresh();
  }
}

// Providers
final worksProvider = StateNotifierProvider<WorksNotifier, WorksState>((ref) {
  final apiService = ref.watch(kikoeruApiServiceProvider);
  return WorksNotifier(apiService, ref);
});
