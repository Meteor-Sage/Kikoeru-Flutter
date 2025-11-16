import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:io';

import '../models/download_task.dart';
import '../models/work.dart';
import '../services/download_service.dart';
import '../utils/string_utils.dart';
import '../providers/auth_provider.dart';
import '../widgets/pagination_bar.dart';
import 'offline_work_detail_screen.dart';

/// 本地下载屏幕 - 显示已完成的下载内容
class LocalDownloadsScreen extends ConsumerStatefulWidget {
  const LocalDownloadsScreen({super.key});

  @override
  ConsumerState<LocalDownloadsScreen> createState() =>
      _LocalDownloadsScreenState();
}

class _LocalDownloadsScreenState extends ConsumerState<LocalDownloadsScreen>
    with AutomaticKeepAliveClientMixin {
  bool _isSelectionMode = false;
  final Set<int> _selectedWorkIds = {}; // 选中的作品ID
  final ScrollController _scrollController = ScrollController();
  int _currentPage = 1;
  final int _pageSize = 30;

  @override
  bool get wantKeepAlive => true;

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

  void _goToPage(int page) {
    setState(() {
      _currentPage = page;
    });
    _scrollToTop();
  }

  void _nextPage(int totalPages) {
    if (_currentPage < totalPages) {
      _goToPage(_currentPage + 1);
    }
  }

  void _previousPage() {
    if (_currentPage > 1) {
      _goToPage(_currentPage - 1);
    }
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedWorkIds.clear();
      }
    });
  }

  void _toggleWorkSelection(int workId) {
    setState(() {
      if (_selectedWorkIds.contains(workId)) {
        _selectedWorkIds.remove(workId);
      } else {
        _selectedWorkIds.add(workId);
      }
    });
  }

  void _selectAll(Map<int, List<DownloadTask>> groupedTasks) {
    setState(() {
      _selectedWorkIds.clear();
      _selectedWorkIds.addAll(groupedTasks.keys);
    });
  }

  void _deselectAll() {
    setState(() {
      _selectedWorkIds.clear();
    });
  }

  // 刷新元数据
  Future<void> _refreshMetadata() async {
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                SizedBox(width: 12),
                Text('正在从硬盘重新加载...'),
              ],
            ),
            duration: Duration(seconds: 1),
          ),
        );
      }

      await DownloadService.instance.reloadMetadataFromDisk();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('刷新完成'),
              ],
            ),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('刷新失败: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // 删除选中的作品
  Future<void> _deleteSelectedWorks(
      Map<int, List<DownloadTask>> groupedTasks) async {
    if (_selectedWorkIds.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除选中的 ${_selectedWorkIds.length} 个作品吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      for (final workId in _selectedWorkIds) {
        final tasks = groupedTasks[workId] ?? [];
        for (final task in tasks) {
          await DownloadService.instance.deleteTask(task.id);
        }
      }

      setState(() {
        _isSelectionMode = false;
        _selectedWorkIds.clear();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('删除成功')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e')),
        );
      }
    }
  }

  void _openWorkDetail(int workId, DownloadTask task) async {
    if (task.workMetadata == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('该下载任务没有保存作品详情，无法离线查看'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    try {
      final metadata = _sanitizeMetadata(task.workMetadata!);
      final work = Work.fromJson(metadata);

      // 动态构建完整的封面路径
      final downloadDir = await DownloadService.instance.getDownloadDirectory();
      final relativeCoverPath = metadata['localCoverPath'] as String?;
      final localCoverPath = relativeCoverPath != null
          ? '${downloadDir.path}/$workId/$relativeCoverPath'
          : null;

      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => OfflineWorkDetailScreen(
              work: work,
              isOffline: true,
              localCoverPath: localCoverPath,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('打开作品详情失败: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Map<String, dynamic> _sanitizeMetadata(Map<String, dynamic> metadata) {
    return _deepSanitize(metadata) as Map<String, dynamic>;
  }

  dynamic _deepSanitize(dynamic value) {
    if (value == null) return null;

    if (value is Map) {
      return value
          .map((key, val) => MapEntry(key.toString(), _deepSanitize(val)));
    }

    if (value is List) {
      return value.map(_deepSanitize).toList();
    }

    // 处理特殊类型对象
    if (value.runtimeType.toString() == 'Va') {
      return {
        'id': _getProperty(value, 'id'),
        'name': _getProperty(value, 'name'),
      };
    }

    if (value.runtimeType.toString() == 'Tag') {
      return {
        'id': _getProperty(value, 'id'),
        'name': _getProperty(value, 'name'),
      };
    }

    if (value.runtimeType.toString() == 'AudioFile') {
      return {
        'title': _getProperty(value, 'title'),
        'type': _getProperty(value, 'type'),
        'hash': _getProperty(value, 'hash'),
        'children': _deepSanitize(_getProperty(value, 'children')),
        'size': _getProperty(value, 'size'),
        'mediaDownloadUrl': _getProperty(value, 'mediaDownloadUrl'),
      };
    }

    if (value.runtimeType.toString() == 'RatingDetail') {
      return {
        'review_point': _getProperty(value, 'review_point'),
        'count': _getProperty(value, 'count'),
        'ratio': _getProperty(value, 'ratio'),
      };
    }

    return value;
  }

  dynamic _getProperty(dynamic obj, String propertyName,
      {dynamic defaultValue}) {
    try {
      if (obj is Map) {
        return obj[propertyName] ?? defaultValue;
      }
      final mirror = obj.runtimeType.toString();
      if (mirror.contains(propertyName)) {
        return (obj as dynamic).toJson()[propertyName] ?? defaultValue;
      }
      return defaultValue;
    } catch (e) {
      return defaultValue;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return StreamBuilder<List<DownloadTask>>(
      stream: DownloadService.instance.tasksStream,
      initialData: DownloadService.instance.tasks,
      builder: (context, snapshot) {
        final tasks = snapshot.data ?? [];
        final completedTasks =
            tasks.where((t) => t.status == DownloadStatus.completed).toList();

        // 按作品分组
        final Map<int, List<DownloadTask>> groupedTasks = {};
        for (final task in completedTasks) {
          groupedTasks.putIfAbsent(task.workId, () => []).add(task);
        }

        // 计算分页
        final totalCount = groupedTasks.length;
        final totalPages = (totalCount / _pageSize).ceil();
        final startIndex = (_currentPage - 1) * _pageSize;
        final endIndex = (startIndex + _pageSize).clamp(0, totalCount);

        // 获取当前页的作品
        final currentPageWorkIds = groupedTasks.keys.toList().sublist(
              startIndex,
              endIndex,
            );
        final currentPageTasks = Map<int, List<DownloadTask>>.fromEntries(
          currentPageWorkIds.map((id) => MapEntry(id, groupedTasks[id]!)),
        );

        return Column(
          children: [
            // 顶部工具栏
            _buildTopBar(groupedTasks),
            // 内容区域
            Expanded(
              child: groupedTasks.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.download_outlined,
                            size: 64,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '暂无本地下载',
                            style: TextStyle(
                              fontSize: 16,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  : CustomScrollView(
                      controller: _scrollController,
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.all(16),
                          sliver: SliverGrid(
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 210,
                              childAspectRatio: 0.72,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final workId = currentPageWorkIds[index];
                                final workTasks = currentPageTasks[workId]!;
                                final firstTask = workTasks.first;
                                final isSelected =
                                    _selectedWorkIds.contains(workId);

                                return _buildWorkCard(
                                  workId: workId,
                                  workTasks: workTasks,
                                  firstTask: firstTask,
                                  isSelected: isSelected,
                                );
                              },
                              childCount: currentPageTasks.length,
                            ),
                          ),
                        ),
                        // 分页控件
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                          sliver: SliverToBoxAdapter(
                            child: PaginationBar(
                              currentPage: _currentPage,
                              totalCount: totalCount,
                              pageSize: _pageSize,
                              hasMore: _currentPage < totalPages,
                              isLoading: false,
                              onPreviousPage: _previousPage,
                              onNextPage: () => _nextPage(totalPages),
                              onGoToPage: _goToPage,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTopBar(Map<int, List<DownloadTask>> groupedTasks) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final horizontalPadding = isLandscape ? 24.0 : 8.0;

    return Container(
      height: 48,
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withOpacity(0.5),
      child: _isSelectionMode
          ? Row(
              children: [
                // 退出选择按钮
                Padding(
                  padding: EdgeInsets.only(left: horizontalPadding - 8),
                  child: IconButton(
                    icon: const Icon(Icons.close),
                    iconSize: 22,
                    padding: const EdgeInsets.all(8),
                    constraints:
                        const BoxConstraints(minWidth: 40, minHeight: 40),
                    onPressed: _toggleSelectionMode,
                    tooltip: '退出选择',
                  ),
                ),
                // 选中数量显示
                Text(
                  '已选择 ${_selectedWorkIds.length} 项',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                // 全选/取消全选按钮
                IconButton(
                  icon: Icon(
                    _selectedWorkIds.length == groupedTasks.length
                        ? Icons.deselect
                        : Icons.select_all,
                  ),
                  iconSize: 22,
                  padding: const EdgeInsets.all(8),
                  constraints:
                      const BoxConstraints(minWidth: 40, minHeight: 40),
                  onPressed: _selectedWorkIds.length == groupedTasks.length
                      ? _deselectAll
                      : () => _selectAll(groupedTasks),
                  tooltip: _selectedWorkIds.length == groupedTasks.length
                      ? '取消全选'
                      : '全选',
                ),
                // 删除按钮
                if (_selectedWorkIds.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.delete),
                    iconSize: 22,
                    padding: const EdgeInsets.all(8),
                    constraints:
                        const BoxConstraints(minWidth: 40, minHeight: 40),
                    onPressed: () => _deleteSelectedWorks(groupedTasks),
                    tooltip: '删除 (${_selectedWorkIds.length})',
                    color: Theme.of(context).colorScheme.error,
                  ),
                SizedBox(width: horizontalPadding - 8),
              ],
            )
          : Row(
              children: [
                Expanded(child: Container()),
                // 选择按钮
                Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: IconButton(
                    icon: const Icon(Icons.checklist),
                    iconSize: 22,
                    padding: const EdgeInsets.all(8),
                    constraints:
                        const BoxConstraints(minWidth: 40, minHeight: 40),
                    onPressed: _toggleSelectionMode,
                    tooltip: '选择',
                  ),
                ),
                // 刷新按钮
                Padding(
                  padding: EdgeInsets.only(right: horizontalPadding - 8),
                  child: IconButton(
                    icon: const Icon(Icons.refresh),
                    iconSize: 22,
                    padding: const EdgeInsets.all(8),
                    constraints:
                        const BoxConstraints(minWidth: 40, minHeight: 40),
                    onPressed: _refreshMetadata,
                    tooltip: '刷新',
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildWorkCard({
    required int workId,
    required List<DownloadTask> workTasks,
    required DownloadTask firstTask,
    required bool isSelected,
  }) {
    final authState = ref.watch(authProvider);
    final host = authState.host ?? '';
    final token = authState.token ?? '';
    final totalSize = workTasks.fold<int>(
      0,
      (sum, task) => sum + (task.totalBytes ?? 0),
    );

    Work? work;
    if (firstTask.workMetadata != null) {
      try {
        final sanitized = _sanitizeMetadata(firstTask.workMetadata!);
        work = Work.fromJson(sanitized);
      } catch (e) {
        work = null;
      }
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: isSelected ? 8 : 2,
      shadowColor: isSelected
          ? Theme.of(context).colorScheme.primary.withOpacity(0.4)
          : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              )
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: _isSelectionMode
            ? () => _toggleWorkSelection(workId)
            : () => _openWorkDetail(workId, firstTask),
        onLongPress: !_isSelectionMode
            ? () {
                setState(() {
                  _isSelectionMode = true;
                  _toggleWorkSelection(workId);
                });
              }
            : null,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 封面区域
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildCover(workId, work, host, token, firstTask),
                      // 底部渐变遮罩，提升文字可读性
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          height: 60,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withOpacity(0.7),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // 信息区域
                Container(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 标题
                      Text(
                        work?.title ?? firstTask.workTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // 声优信息
                      if (work?.vas != null && work!.vas!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Icon(
                                Icons.mic,
                                size: 12,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  work.vas!.first.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      // 文件信息
                      Row(
                        children: [
                          // 文件数量
                          Icon(
                            Icons.folder_outlined,
                            size: 12,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${workTasks.length}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // 文件大小
                          Icon(
                            Icons.storage,
                            size: 12,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              formatBytes(totalSize),
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // 选择模式的勾选标记
            if (_isSelectionMode)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.white.withOpacity(0.95),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    isSelected ? Icons.check : Icons.circle_outlined,
                    color: isSelected
                        ? Colors.white
                        : Theme.of(context).colorScheme.outline,
                    size: 20,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCover(
    int workId,
    Work? work,
    String host,
    String token,
    DownloadTask task,
  ) {
    // 优先使用本地封面
    if (task.workMetadata != null) {
      final relativeCoverPath = task.workMetadata!['localCoverPath'] as String?;
      if (relativeCoverPath != null) {
        return FutureBuilder<Directory>(
          future: DownloadService.instance.getDownloadDirectory(),
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              final localCoverPath =
                  '${snapshot.data!.path}/$workId/$relativeCoverPath';
              final coverFile = File(localCoverPath);
              if (coverFile.existsSync()) {
                return Image.file(
                  coverFile,
                  fit: BoxFit.cover,
                  width: double.infinity,
                );
              }
            }
            return _buildPlaceholder();
          },
        );
      }
    }

    // 降级使用网络封面
    if (work != null && host.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: work.getCoverImageUrl(host, token: token),
        fit: BoxFit.cover,
        errorWidget: (context, url, error) => _buildPlaceholder(),
      );
    }

    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.image_not_supported,
        size: 48,
        color: Theme.of(context).colorScheme.outline,
      ),
    );
  }
}
