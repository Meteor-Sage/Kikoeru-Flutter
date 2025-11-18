import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/playlist.dart';
import '../models/work.dart';
import '../services/kikoeru_api_service.dart' hide kikoeruApiServiceProvider;
import 'auth_provider.dart' show kikoeruApiServiceProvider;

/// 播放列表详情状态
class PlaylistDetailState {
  final Playlist? metadata;
  final List<Work> works;
  final bool isLoading;
  final String? error;
  final int currentPage;
  final int pageSize;
  final int totalCount;
  final bool hasMore;

  const PlaylistDetailState({
    this.metadata,
    this.works = const [],
    this.isLoading = false,
    this.error,
    this.currentPage = 1,
    this.pageSize = 12,
    this.totalCount = 0,
    this.hasMore = false,
  });

  PlaylistDetailState copyWith({
    Playlist? metadata,
    List<Work>? works,
    bool? isLoading,
    String? error,
    int? currentPage,
    int? pageSize,
    int? totalCount,
    bool? hasMore,
  }) {
    return PlaylistDetailState(
      metadata: metadata ?? this.metadata,
      works: works ?? this.works,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      currentPage: currentPage ?? this.currentPage,
      pageSize: pageSize ?? this.pageSize,
      totalCount: totalCount ?? this.totalCount,
      hasMore: hasMore ?? this.hasMore,
    );
  }
}

/// 播放列表详情 Notifier
class PlaylistDetailNotifier extends StateNotifier<PlaylistDetailState> {
  final KikoeruApiService _apiService;
  final String playlistId;

  PlaylistDetailNotifier(this._apiService, this.playlistId)
      : super(const PlaylistDetailState());

  /// 加载播放列表元数据和作品
  Future<void> load({bool refresh = false}) async {
    if (state.isLoading) return;

    if (refresh) {
      state = state.copyWith(
        isLoading: true,
        error: null,
        currentPage: 1,
      );
    } else {
      state = state.copyWith(isLoading: true, error: null);
    }

    try {
      // 并行加载元数据和作品列表
      final results = await Future.wait([
        _apiService.getPlaylistMetadata(playlistId),
        _apiService.getPlaylistWorks(
          playlistId: playlistId,
          page: state.currentPage,
          pageSize: state.pageSize,
        ),
      ]);

      final metadataJson = results[0];
      final worksResponse = results[1];

      final metadata = Playlist.fromJson(metadataJson);
      final worksList = (worksResponse['works'] as List)
          .map((json) => Work.fromJson(json))
          .toList();

      final pagination = worksResponse['pagination'] as Map<String, dynamic>;
      final totalCount = pagination['totalCount'] as int;
      final hasMore = worksList.length >= state.pageSize &&
          state.currentPage * state.pageSize < totalCount;

      state = state.copyWith(
        metadata: metadata,
        works: worksList,
        isLoading: false,
        totalCount: totalCount,
        hasMore: hasMore,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// 跳转到指定页
  Future<void> goToPage(int page) async {
    if (page < 1 || state.isLoading) return;

    state = state.copyWith(
      currentPage: page,
      isLoading: true,
      error: null,
    );

    try {
      final response = await _apiService.getPlaylistWorks(
        playlistId: playlistId,
        page: page,
        pageSize: state.pageSize,
      );

      final worksList = (response['works'] as List)
          .map((json) => Work.fromJson(json))
          .toList();

      final pagination = response['pagination'] as Map<String, dynamic>;
      final totalCount = pagination['totalCount'] as int;
      final hasMore = worksList.length >= state.pageSize &&
          page * state.pageSize < totalCount;

      state = state.copyWith(
        works: worksList,
        isLoading: false,
        currentPage: page,
        totalCount: totalCount,
        hasMore: hasMore,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// 上一页
  Future<void> previousPage() async {
    if (state.currentPage > 1) {
      await goToPage(state.currentPage - 1);
    }
  }

  /// 下一页
  Future<void> nextPage() async {
    if (state.hasMore) {
      await goToPage(state.currentPage + 1);
    }
  }

  /// 刷新
  Future<void> refresh() async {
    await load(refresh: true);
  }

  /// 删除当前播放列表
  /// 根据播放列表的所有者和类型自动选择合适的删除API
  Future<void> deletePlaylist(String currentUserName) async {
    if (state.metadata == null) {
      throw Exception('播放列表信息未加载');
    }

    final playlist = state.metadata!;
    final isOwner = playlist.userName == currentUserName;

    try {
      if (isOwner) {
        // 如果是系统播放列表，不允许删除
        if (playlist.isSystemPlaylist) {
          throw Exception('系统播放列表不能删除');
        }
        // 使用删除API删除自己创建的播放列表
        await _apiService.deletePlaylist(playlist.id);
      } else {
        // 使用取消收藏API删除别人的播放列表
        await _apiService.removeLikePlaylist(playlist.id);
      }
    } catch (e) {
      rethrow;
    }
  }

  /// 编辑播放列表元数据
  Future<void> updateMetadata({
    required String name,
    required int privacy,
    required String description,
  }) async {
    if (state.metadata == null) return;

    state = state.copyWith(isLoading: true, error: null);

    try {
      final response = await _apiService.editPlaylistMetadata(
        id: state.metadata!.id,
        name: name,
        privacy: privacy,
        description: description,
      );

      // 更新元数据
      final updatedMetadata = Playlist.fromJson(response);
      state = state.copyWith(
        metadata: updatedMetadata,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: '编辑播放列表失败: ${e.toString()}',
      );
      rethrow;
    }
  }

  /// 添加作品到播放列表
  Future<void> addWorks(List<String> workIds) async {
    if (state.metadata == null) return;

    try {
      await _apiService.addWorksToPlaylist(
        playlistId: state.metadata!.id,
        works: workIds,
      );

      // 刷新列表以显示新添加的作品
      await refresh();
    } catch (e) {
      rethrow;
    }
  }

  /// 从播放列表移除作品
  Future<void> removeWork(int workId) async {
    if (state.metadata == null) return;

    try {
      await _apiService.removeWorksFromPlaylist(
        playlistId: state.metadata!.id,
        works: [workId],
      );

      // 刷新列表以更新显示
      await refresh();
    } catch (e) {
      rethrow;
    }
  }
}

/// 播放列表详情 Provider Family
final playlistDetailProvider = StateNotifierProvider.family<
    PlaylistDetailNotifier, PlaylistDetailState, String>(
  (ref, playlistId) {
    final apiService = ref.watch(kikoeruApiServiceProvider);
    return PlaylistDetailNotifier(apiService, playlistId);
  },
);
