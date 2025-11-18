import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/playlist_detail_provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/enhanced_work_card.dart';
import '../widgets/pagination_bar.dart';

class PlaylistDetailScreen extends ConsumerStatefulWidget {
  final String playlistId;
  final String? playlistName;

  const PlaylistDetailScreen({
    super.key,
    required this.playlistId,
    this.playlistName,
  });

  @override
  ConsumerState<PlaylistDetailScreen> createState() =>
      _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends ConsumerState<PlaylistDetailScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // 首次加载数据
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(playlistDetailProvider(widget.playlistId).notifier).load();
    });
  }

  @override
  void dispose() {
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

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      final date = DateTime.parse(dateStr);
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
          '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateStr;
    }
  }

  /// 显示删除播放列表确认对话框
  Future<void> _showDeleteConfirmDialog() async {
    final state = ref.read(playlistDetailProvider(widget.playlistId));
    final playlist = state.metadata;
    if (playlist == null) return;

    final authState = ref.read(authProvider);
    final currentUserName = authState.currentUser?.name ?? '';
    final isOwner = playlist.userName == currentUserName;

    // 系统播放列表不能删除
    if (playlist.isSystemPlaylist && isOwner) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('系统播放列表不能删除'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isOwner ? '删除播放列表' : '取消收藏播放列表'),
        content: Text(
          isOwner
              ? '删除后不可恢复，收藏本列表的人将无法再访问。确定要删除吗？'
              : '确定要取消收藏"${playlist.displayName}"吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(isOwner ? '删除' : '取消收藏'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deletePlaylist();
    }
  }

  /// 删除播放列表
  Future<void> _deletePlaylist() async {
    final authState = ref.read(authProvider);
    final currentUserName = authState.currentUser?.name ?? '';

    try {
      // 显示加载提示
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('正在删除...'),
            ],
          ),
          duration: Duration(seconds: 30),
        ),
      );

      await ref
          .read(playlistDetailProvider(widget.playlistId).notifier)
          .deletePlaylist(currentUserName);

      if (!mounted) return;

      // 隐藏加载提示
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      // 显示成功提示并返回上一页
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('删除成功'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );

      // 延迟一点返回，让用户看到成功提示
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      Navigator.of(context).pop(true); // 返回 true 表示已删除
    } catch (e) {
      if (!mounted) return;

      // 隐藏加载提示
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      // 显示错误提示
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('删除失败: ${e.toString()}'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).colorScheme.error,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playlistDetailProvider(widget.playlistId));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.playlistName ?? '播放列表'),
        actions: [
          // 删除按钮（仅在元数据加载完成后显示）
          if (state.metadata != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _showDeleteConfirmDialog,
              tooltip: '删除',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref
                  .read(playlistDetailProvider(widget.playlistId).notifier)
                  .refresh();
            },
            tooltip: '刷新',
          ),
        ],
      ),
      body: _buildBody(state),
    );
  }

  Widget _buildBody(PlaylistDetailState state) {
    // 错误状态
    if (state.error != null && state.metadata == null) {
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
              state.error!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => ref
                  .read(playlistDetailProvider(widget.playlistId).notifier)
                  .refresh(),
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }

    // 加载中且无数据
    if (state.isLoading && state.metadata == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    // 空状态
    if (state.works.isEmpty && !state.isLoading) {
      return RefreshIndicator(
        onRefresh: () async => ref
            .read(playlistDetailProvider(widget.playlistId).notifier)
            .refresh(),
        child: CustomScrollView(
          slivers: [
            if (state.metadata != null) _buildMetadataSection(state.metadata!),
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.music_note,
                      size: 64,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '暂无作品',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '此播放列表还没有添加任何作品',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => ref
          .read(playlistDetailProvider(widget.playlistId).notifier)
          .refresh(),
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        slivers: [
          // 元数据信息
          if (state.metadata != null) _buildMetadataSection(state.metadata!),

          // 作品列表
          SliverPadding(
            padding: const EdgeInsets.all(8),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final work = state.works[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: EnhancedWorkCard(
                      work: work,
                      onTap: () {
                        // TODO: 导航到作品详情页
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('点击了作品: ${work.title}'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                    ),
                  );
                },
                childCount: state.works.length,
              ),
            ),
          ),

          // 分页控件
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
                  ref
                      .read(playlistDetailProvider(widget.playlistId).notifier)
                      .previousPage();
                  _scrollToTop();
                },
                onNextPage: () {
                  ref
                      .read(playlistDetailProvider(widget.playlistId).notifier)
                      .nextPage();
                  _scrollToTop();
                },
                onGoToPage: (page) {
                  ref
                      .read(playlistDetailProvider(widget.playlistId).notifier)
                      .goToPage(page);
                  _scrollToTop();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetadataSection(metadata) {
    // 获取更新时间，如果没有则使用创建时间
    final displayDate = metadata.updatedAt.isNotEmpty &&
            metadata.updatedAt != metadata.createdAt
        ? _formatDate(metadata.updatedAt)
        : _formatDate(metadata.createdAt);

    final dateLabel = metadata.updatedAt.isNotEmpty &&
            metadata.updatedAt != metadata.createdAt
        ? '最近更新'
        : '创建时间';

    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            Text(
              metadata.displayName,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),

            // 作者
            Row(
              children: [
                Icon(
                  Icons.person_outline,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  metadata.userName,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 4),

            // 时间
            if (displayDate.isNotEmpty)
              Row(
                children: [
                  Icon(
                    Icons.access_time,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$dateLabel: $displayDate',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),

            // 描述（如果有）
            if (metadata.description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                metadata.description,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],

            // 统计信息
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              children: [
                _buildStatChip(
                  context,
                  Icons.music_note,
                  '${metadata.worksCount} 作品',
                ),
                if (metadata.playbackCount > 0)
                  _buildStatChip(
                    context,
                    Icons.play_circle_outline,
                    '${metadata.playbackCount} 播放',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(BuildContext context, IconData icon, String label) {
    return Chip(
      avatar: Icon(
        icon,
        size: 16,
        color: Theme.of(context).colorScheme.primary,
      ),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}
