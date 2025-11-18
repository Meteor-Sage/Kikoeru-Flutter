import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/playlist_detail_provider.dart';
import '../providers/auth_provider.dart';
import '../models/work.dart';
import '../widgets/pagination_bar.dart';
import '../widgets/scrollable_appbar.dart';
import '../utils/snackbar_util.dart';
import '../screens/work_detail_screen.dart';

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
      SnackBarUtil.showError(context, '系统播放列表不能删除');
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
      SnackBarUtil.showLoading(context, '正在删除...');

      await ref
          .read(playlistDetailProvider(widget.playlistId).notifier)
          .deletePlaylist(currentUserName);

      if (!mounted) return;

      // 隐藏加载提示
      SnackBarUtil.hide(context);

      // 显示成功提示并返回上一页
      SnackBarUtil.showSuccess(context, '删除成功');

      // 延迟一点返回，让用户看到成功提示
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      Navigator.of(context).pop(true); // 返回 true 表示已删除
    } catch (e) {
      if (!mounted) return;

      // 隐藏加载提示
      SnackBarUtil.hide(context);

      // 显示错误提示
      SnackBarUtil.showError(context, '删除失败: ${e.toString()}');
    }
  }

  /// 显示编辑对话框
  void _showEditDialog(metadata) {
    // 检查权限：只有作者才能编辑
    final authState = ref.read(authProvider);
    final currentUserName = authState.currentUser?.name ?? '';
    final isOwner = metadata.userName == currentUserName;

    if (!isOwner) {
      SnackBarUtil.showError(context, '只有播放列表作者才能编辑');
      return;
    }

    final nameController = TextEditingController(text: metadata.displayName);
    final descriptionController =
        TextEditingController(text: metadata.description);
    int selectedPrivacy = metadata.privacy;

    showDialog(
      context: context,
      builder: (dialogContext) {
        final isLandscape =
            MediaQuery.of(dialogContext).orientation == Orientation.landscape;
        final screenWidth = MediaQuery.of(dialogContext).size.width;
        final dialogWidth = isLandscape ? screenWidth * 0.6 : screenWidth * 0.9;

        return StatefulBuilder(
          builder: (context, setDialogState) => Dialog(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: dialogWidth.clamp(300.0, 600.0),
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 标题栏
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                      child: Row(
                        children: [
                          Text(
                            '编辑播放列表',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                    ),

                    // 内容区域
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 名称输入
                          TextField(
                            controller: nameController,
                            decoration: const InputDecoration(
                              labelText: '播放列表名称',
                              hintText: '请输入名称',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.title),
                            ),
                            autofocus: true,
                            maxLength: 50,
                          ),
                          const SizedBox(height: 16),

                          // 隐私设置
                          DropdownButtonFormField<int>(
                            value: selectedPrivacy,
                            decoration: InputDecoration(
                              labelText: '隐私设置',
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.lock_outline),
                              helperText: _getPrivacyDescription(selectedPrivacy),
                              helperMaxLines: 2,
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 0,
                                child: Text('私享'),
                              ),
                              DropdownMenuItem(
                                value: 1,
                                child: Text('不公开'),
                              ),
                              DropdownMenuItem(
                                value: 2,
                                child: Text('公开'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setDialogState(() {
                                  selectedPrivacy = value;
                                });
                              }
                            },
                          ),
                          const SizedBox(height: 16),

                          // 描述输入
                          TextField(
                            controller: descriptionController,
                            decoration: const InputDecoration(
                              labelText: '描述（可选）',
                              hintText: '添加一些描述信息',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.description),
                            ),
                            maxLines: 1,
                            maxLength: 200,
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),

                    // 操作按钮
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('取消'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () {
                              final name = nameController.text.trim();
                              if (name.isEmpty) {
                                SnackBarUtil.showWarning(
                                    context, '播放列表名称不能为空');
                                return;
                              }
                              Navigator.of(context).pop();
                              _updateMetadata(
                                name: name,
                                privacy: selectedPrivacy,
                                description: descriptionController.text.trim(),
                              );
                            },
                            child: const Text('保存'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 获取隐私设置描述
  String _getPrivacyDescription(int privacy) {
    switch (privacy) {
      case 0:
        return '只有您可以观看';
      case 1:
        return '知道链接的人才能观看';
      case 2:
        return '任何人都可以观看';
      default:
        return '';
    }
  }

  /// 显示添加作品对话框
  void _showAddWorksDialog() {
    final textController = TextEditingController();
    List<String> parsedWorkIds = [];

    showDialog(
      context: context,
      builder: (dialogContext) {
        final isLandscape =
            MediaQuery.of(dialogContext).orientation == Orientation.landscape;
        final screenWidth = MediaQuery.of(dialogContext).size.width;
        final dialogWidth = isLandscape ? screenWidth * 0.6 : screenWidth * 0.9;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: dialogWidth.clamp(300.0, 600.0),
                  maxHeight: MediaQuery.of(context).size.height * 0.85,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 标题栏
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                        child: Row(
                          children: [
                            Text(
                              '添加作品',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                      ),

                      // 内容区域
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 提示文本
                            Text(
                              '输入包含作品号的文本，自动识别RJ号',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                            const SizedBox(height: 12),

                            // 输入框
                            TextField(
                              controller: textController,
                              decoration: const InputDecoration(
                                labelText: '作品号',
                                hintText: '例如：RJ123456\nrj233333',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.music_note),
                              ),
                              maxLines: 5,
                              autofocus: true,
                              onChanged: (text) {
                                // 实时解析RJ号
                                final parsed = _parseWorkIds(text);
                                setDialogState(() {
                                  parsedWorkIds = parsed;
                                });
                              },
                            ),
                            const SizedBox(height: 8),

                            // 显示解析结果
                            if (parsedWorkIds.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primaryContainer
                                      .withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withOpacity(0.5),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.check_circle_outline,
                                          size: 16,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '识别到 ${parsedWorkIds.length} 个作品号',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary,
                                                fontWeight: FontWeight.bold,
                                              ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: parsedWorkIds.map((id) {
                                        return Chip(
                                          label: Text(
                                            id,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                          visualDensity:
                                              VisualDensity.compact,
                                          backgroundColor: Theme.of(context)
                                              .colorScheme
                                              .primaryContainer,
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      // 操作按钮
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('取消'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: parsedWorkIds.isEmpty
                                  ? null
                                  : () {
                                      Navigator.of(context).pop();
                                      _addWorks(parsedWorkIds);
                                    },
                              child: Text(parsedWorkIds.isEmpty
                                  ? '添加'
                                  : '添加 ${parsedWorkIds.length} 个'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 解析文本中的RJ号
  List<String> _parseWorkIds(String text) {
    if (text.isEmpty) return [];

    // 使用正则表达式提取所有RJ开头的作品号（不区分大小写）
    final rjPattern = RegExp(r'RJ\d+', caseSensitive: false);
    final matches = rjPattern.allMatches(text.toUpperCase());

    // 去重并返回
    return matches.map((m) => m.group(0)!).toSet().toList();
  }

  /// 添加作品到播放列表
  Future<void> _addWorks(List<String> workIds) async {
    if (workIds.isEmpty) {
      SnackBarUtil.showWarning(context, '未找到有效的作品号（RJ开头）');
      return;
    }

    try {
      // 显示加载提示
      if (!mounted) return;
      SnackBarUtil.showLoading(context, '正在添加 ${workIds.length} 个作品...');

      await ref
          .read(playlistDetailProvider(widget.playlistId).notifier)
          .addWorks(workIds);

      if (!mounted) return;

      // 隐藏加载提示
      SnackBarUtil.hide(context);

      // 显示成功提示
      SnackBarUtil.showSuccess(context, '成功添加 ${workIds.length} 个作品');
    } catch (e) {
      if (!mounted) return;

      // 隐藏加载提示
      SnackBarUtil.hide(context);

      // 显示错误提示
      SnackBarUtil.showError(context, '添加失败: ${e.toString()}');
    }
  }

  /// 显示移除作品确认对话框
  Future<void> _showRemoveWorkConfirmDialog(Work work) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('移除作品'),
        content: Text('确定要从播放列表中移除「${work.title}」吗？'),
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
            child: const Text('移除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _removeWork(work.id);
    }
  }

  /// 移除作品
  Future<void> _removeWork(int workId) async {
    try {
      // 显示加载提示
      if (!mounted) return;
      SnackBarUtil.showLoading(context, '正在移除...');

      await ref
          .read(playlistDetailProvider(widget.playlistId).notifier)
          .removeWork(workId);

      if (!mounted) return;

      // 隐藏加载提示
      SnackBarUtil.hide(context);

      // 显示成功提示
      SnackBarUtil.showSuccess(context, '移除成功');
    } catch (e) {
      if (!mounted) return;

      // 隐藏加载提示
      SnackBarUtil.hide(context);

      // 显示错误提示
      SnackBarUtil.showError(context, '移除失败: ${e.toString()}');
    }
  }

  /// 更新播放列表元数据
  Future<void> _updateMetadata({
    required String name,
    required int privacy,
    required String description,
  }) async {
    try {
      // 显示加载提示
      if (!mounted) return;
      SnackBarUtil.showLoading(context, '正在保存...');

      await ref
          .read(playlistDetailProvider(widget.playlistId).notifier)
          .updateMetadata(
            name: name,
            privacy: privacy,
            description: description,
          );

      if (!mounted) return;

      // 隐藏加载提示
      SnackBarUtil.hide(context);

      // 显示成功提示
      SnackBarUtil.showSuccess(context, '保存成功');
    } catch (e) {
      if (!mounted) return;

      // 隐藏加载提示
      SnackBarUtil.hide(context);

      // 显示错误提示
      SnackBarUtil.showError(context, '保存失败: ${e.toString()}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playlistDetailProvider(widget.playlistId));

    return Scaffold(
      appBar: ScrollableAppBar(
        actions: [
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
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddWorksDialog,
        tooltip: '添加作品',
        child: const Icon(Icons.add),
      ),
      body: ScrollNotificationObserver(
        child: _buildBody(state),
      ),
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
                  final authState = ref.watch(authProvider);
                  final currentUserName = authState.currentUser?.name ?? '';
                  final isOwner = state.metadata?.userName == currentUserName;

                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    child: _buildPlaylistWorkCard(work, isOwner),
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
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
              width: 1,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题栏
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        metadata.displayName,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        metadata.userName,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                
                // 操作按钮
                Builder(
                  builder: (context) {
                    final authState = ref.watch(authProvider);
                    final currentUserName = authState.currentUser?.name ?? '';
                    final isOwner = metadata.userName == currentUserName;

                    if (isOwner) {
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: () => _showEditDialog(metadata),
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: '编辑',
                            visualDensity: VisualDensity.compact,
                          ),
                          IconButton(
                            onPressed: _showDeleteConfirmDialog,
                            icon: const Icon(Icons.delete_outline),
                            tooltip: '删除',
                            visualDensity: VisualDensity.compact,
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ],
                      );
                    } else {
                      return IconButton(
                        onPressed: _showDeleteConfirmDialog,
                        icon: const Icon(Icons.delete_outline),
                        tooltip: '取消收藏',
                        visualDensity: VisualDensity.compact,
                        color: Theme.of(context).colorScheme.error,
                      );
                    }
                  },
                ),
              ],
            ),

            // 描述（如果有）
            if (metadata.description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                metadata.description,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],

            // 底部信息栏
            const SizedBox(height: 16),
            Row(
              children: [
                // 统计信息
                Icon(
                  Icons.music_note,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  '${metadata.worksCount} 作品',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                
                if (metadata.playbackCount > 0) ...[
                  const SizedBox(width: 16),
                  Icon(
                    Icons.play_circle_outline,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${metadata.playbackCount} 播放',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],

                const Spacer(),

                // 时间信息
                if (displayDate.isNotEmpty)
                  Text(
                    '$dateLabel: $displayDate',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // 扁平播放列表风格的作品卡片
  Widget _buildPlaylistWorkCard(Work work, bool isOwner) {
    final authState = ref.watch(authProvider);
    final host = authState.host ?? '';
    final token = authState.token ?? '';
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => WorkDetailScreen(work: work),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border(
            bottom: BorderSide(
              color: colorScheme.outlineVariant.withOpacity(0.5),
              width: 1,
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 封面图
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: CachedNetworkImage(
                imageUrl: '$host/api/cover/${work.id}?type=main&token=$token',
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: colorScheme.surfaceContainerHighest,
                  child: Center(
                    child: Icon(
                      Icons.image,
                      color: colorScheme.onSurfaceVariant,
                      size: 24,
                    ),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  color: colorScheme.surfaceContainerHighest,
                  child: Center(
                    child: Icon(
                      Icons.broken_image,
                      color: colorScheme.onSurfaceVariant,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            
            // 信息区域
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 标题
                  Text(
                    work.title,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  
                  // RJ号、社团名和用户评分
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'RJ${work.id}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (work.name != null && work.name!.isNotEmpty)
                        Text(
                          work.name!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      if (work.userRating != null && work.userRating! > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.person,
                                color: colorScheme.onPrimaryContainer,
                                size: 12,
                              ),
                              const SizedBox(width: 2),
                              Icon(
                                Icons.star,
                                size: 12,
                                color: Colors.amber[700],
                              ),
                              const SizedBox(width: 2),
                              Text(
                                '${work.userRating}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            
            // 移除按钮（仅作者可见）
            if (isOwner) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(Icons.remove_circle_outline, size: 20),
                color: colorScheme.error,
                visualDensity: VisualDensity.compact,
                onPressed: () => _showRemoveWorkConfirmDialog(work),
                tooltip: '从播放列表移除',
              ),
            ],
          ],
        ),
      ),
    );
  }
}
