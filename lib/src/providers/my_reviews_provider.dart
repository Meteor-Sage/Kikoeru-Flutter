import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:equatable/equatable.dart';

import '../models/work.dart';
import '../services/kikoeru_api_service.dart' hide kikoeruApiServiceProvider;
import 'auth_provider.dart';

/// 用户 Review/收藏状态的过滤枚举
enum MyReviewFilter {
  all(null, '全部'),
  marked('marked', '想听'),
  listening('listening', '在听'),
  listened('listened', '听过'),
  replay('replay', '重听'),
  postponed('postponed', '搁置');

  final String? value;
  final String label;
  const MyReviewFilter(this.value, this.label);
}

/// 布局类型枚举
enum MyReviewLayoutType {
  bigGrid, // 大网格（2列）
  smallGrid, // 小网格（3列）
  list, // 列表视图
}

class MyReviewsState extends Equatable {
  final List<Work> works;
  final bool isLoading;
  final String? error;
  final int currentPage;
  final int totalCount;
  final bool hasMore;
  final MyReviewFilter filter;
  final int pageSize;
  final MyReviewLayoutType layoutType;

  const MyReviewsState({
    this.works = const [],
    this.isLoading = false,
    this.error,
    this.currentPage = 1,
    this.totalCount = 0,
    this.hasMore = true,
    this.filter = MyReviewFilter.all,
    this.pageSize = 20,
    this.layoutType = MyReviewLayoutType.bigGrid,
  });

  MyReviewsState copyWith({
    List<Work>? works,
    bool? isLoading,
    String? error,
    int? currentPage,
    int? totalCount,
    bool? hasMore,
    MyReviewFilter? filter,
    int? pageSize,
    MyReviewLayoutType? layoutType,
  }) {
    return MyReviewsState(
      works: works ?? this.works,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      currentPage: currentPage ?? this.currentPage,
      totalCount: totalCount ?? this.totalCount,
      hasMore: hasMore ?? this.hasMore,
      filter: filter ?? this.filter,
      pageSize: pageSize ?? this.pageSize,
      layoutType: layoutType ?? this.layoutType,
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
        filter,
        pageSize,
        layoutType,
      ];
}

class MyReviewsNotifier extends StateNotifier<MyReviewsState> {
  final KikoeruApiService _apiService;
  MyReviewsNotifier(this._apiService) : super(const MyReviewsState());

  Future<void> load({bool refresh = false}) async {
    if (state.isLoading) return;
    final page = refresh ? 1 : state.currentPage;

    state = state.copyWith(isLoading: true, error: null, currentPage: page);

    try {
      final result = await _apiService.getMyReviews(
        page: page,
        filter: state.filter.value,
      );

      // 服务器返回结构未知，尝试多种字段名
      final List<dynamic> rawList =
          (result['works'] as List?) ?? // 与 searchWorks 保持一致
              (result['reviews'] as List?) ??
              (result['data'] as List?) ??
              [];

      // 每个条目可能直接是 Work 或包含 work 字段
      final works = rawList.map((item) {
        if (item is Map<String, dynamic>) {
          if (item.containsKey('work')) {
            final workJson = item['work'] as Map<String, dynamic>;
            return Work.fromJson(workJson);
          } else {
            // 直接当作 Work
            return Work.fromJson(item);
          }
        }
        throw Exception('Unexpected review item format');
      }).toList();

      // 获取分页信息
      final pagination = result['pagination'] as Map<String, dynamic>?;
      final totalCount = pagination?['totalCount'] ?? 0;

      // 计算是否有更多页
      final totalPages =
          totalCount > 0 ? (totalCount / state.pageSize).ceil() : 1;
      final hasMore = page < totalPages;

      state = state.copyWith(
        works: works,
        totalCount: totalCount,
        hasMore: hasMore,
        isLoading: false,
        currentPage: page,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  // 跳转到指定页
  Future<void> goToPage(int page) async {
    if (page < 1 || state.isLoading) return;
    await load(refresh: false);
  }

  // 上一页
  Future<void> previousPage() async {
    if (state.currentPage > 1) {
      final prevPage = state.currentPage - 1;
      state = state.copyWith(currentPage: prevPage);
      await load(refresh: false);
    }
  }

  // 下一页
  Future<void> nextPage() async {
    if (state.hasMore) {
      final nextPage = state.currentPage + 1;
      state = state.copyWith(currentPage: nextPage);
      await load(refresh: false);
    }
  }

  void changeFilter(MyReviewFilter filter) {
    state = state.copyWith(filter: filter, currentPage: 1, totalCount: 0);
    load(refresh: true);
  }

  // 切换布局类型
  void toggleLayoutType() {
    final nextLayout = switch (state.layoutType) {
      MyReviewLayoutType.bigGrid => MyReviewLayoutType.smallGrid,
      MyReviewLayoutType.smallGrid => MyReviewLayoutType.list,
      MyReviewLayoutType.list => MyReviewLayoutType.bigGrid,
    };
    state = state.copyWith(layoutType: nextLayout);
  }

  void refresh() => load(refresh: true);
}

final myReviewsProvider =
    StateNotifierProvider<MyReviewsNotifier, MyReviewsState>((ref) {
  final apiService = ref.watch(kikoeruApiServiceProvider);
  return MyReviewsNotifier(apiService);
});
