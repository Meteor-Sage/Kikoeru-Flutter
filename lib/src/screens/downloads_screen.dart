import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/download_task.dart';
import '../models/work.dart';
import '../services/download_service.dart';
import '../utils/string_utils.dart';
import '../providers/auth_provider.dart';
import 'offline_work_detail_screen.dart';

class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isSelectionMode = false;
  final Set<String> _selectedTaskIds = {}; // 选中的任务ID
  final Set<int> _selectedWorkIds = {}; // 选中的作品ID

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    // 切换标签时更新UI（退出选择模式，刷新按钮显示状态）
    setState(() {
      if (_isSelectionMode) {
        _isSelectionMode = false;
        _selectedTaskIds.clear();
        _selectedWorkIds.clear();
      }
    });
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedTaskIds.clear();
        _selectedWorkIds.clear();
      }
    });
  }

  void _toggleTaskSelection(String taskId) {
    setState(() {
      if (_selectedTaskIds.contains(taskId)) {
        _selectedTaskIds.remove(taskId);
      } else {
        _selectedTaskIds.add(taskId);
      }
    });
  }

  void _toggleWorkSelection(int workId, List<DownloadTask> workTasks) {
    setState(() {
      if (_selectedWorkIds.contains(workId)) {
        // 取消选择整个作品
        _selectedWorkIds.remove(workId);
        for (final task in workTasks) {
          _selectedTaskIds.remove(task.id);
        }
      } else {
        // 选择整个作品
        _selectedWorkIds.add(workId);
        for (final task in workTasks) {
          _selectedTaskIds.add(task.id);
        }
      }
    });
  }

  void _selectAll(List<DownloadTask> tasks) {
    setState(() {
      _selectedTaskIds.clear();
      _selectedWorkIds.clear();
      for (final task in tasks) {
        _selectedTaskIds.add(task.id);
      }
      // 找出所有完整选中的作品
      final Map<int, List<DownloadTask>> groupedTasks = {};
      for (final task in tasks) {
        groupedTasks.putIfAbsent(task.workId, () => []).add(task);
      }
      for (final entry in groupedTasks.entries) {
        _selectedWorkIds.add(entry.key);
      }
    });
  }

  void _deselectAll() {
    setState(() {
      _selectedTaskIds.clear();
      _selectedWorkIds.clear();
    });
  }

  // 刷新已完成任务的元数据
  Future<void> _refreshMetadata() async {
    try {
      // 显示加载提示
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
                Text('正在从硬盘重新加载元数据...'),
              ],
            ),
            duration: Duration(seconds: 1),
          ),
        );
      }

      // 重新加载元数据
      await DownloadService.instance.reloadMetadataFromDisk();

      // 显示成功提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('元数据刷新完成'),
              ],
            ),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      // 显示错误提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('刷新失败: $e')),
              ],
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        scrolledUnderElevation: 0,
        title: _isSelectionMode
            ? Text('已选择 ${_selectedTaskIds.length} 项')
            : const Text('下载管理', style: TextStyle(fontSize: 18)),
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _toggleSelectionMode,
              )
            : null,
        actions: _isSelectionMode
            ? [
                IconButton(
                  icon: const Icon(Icons.select_all),
                  onPressed: () {
                    final tasks = DownloadService.instance.tasks;
                    final currentTasks = _tabController.index == 0
                        ? tasks.where((t) =>
                            t.status == DownloadStatus.downloading ||
                            t.status == DownloadStatus.paused ||
                            t.status == DownloadStatus.pending ||
                            t.status == DownloadStatus.failed)
                        : tasks
                            .where((t) => t.status == DownloadStatus.completed);
                    _selectAll(currentTasks.toList());
                  },
                  tooltip: '全选',
                ),
                IconButton(
                  icon: const Icon(Icons.deselect),
                  onPressed: _deselectAll,
                  tooltip: '取消全选',
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: _selectedTaskIds.isEmpty
                      ? null
                      : () => _confirmBatchDelete(),
                  tooltip: '删除',
                ),
              ]
            : [
                // 仅在已完成标签页显示刷新按钮
                if (_tabController.index == 1)
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _refreshMetadata,
                    tooltip: '从硬盘重新加载元数据',
                  ),
                IconButton(
                  icon: const Icon(Icons.checklist),
                  onPressed: _toggleSelectionMode,
                  tooltip: '选择',
                ),
              ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '正在下载', icon: Icon(Icons.downloading)),
            Tab(text: '已完成', icon: Icon(Icons.download_done)),
          ],
        ),
      ),
      body: StreamBuilder<List<DownloadTask>>(
        stream: DownloadService.instance.tasksStream,
        initialData: DownloadService.instance.tasks,
        builder: (context, snapshot) {
          final tasks = snapshot.data ?? [];

          final downloadingTasks = tasks
              .where((t) =>
                  t.status == DownloadStatus.downloading ||
                  t.status == DownloadStatus.paused ||
                  t.status == DownloadStatus.pending ||
                  t.status == DownloadStatus.failed)
              .toList();

          final completedTasks =
              tasks.where((t) => t.status == DownloadStatus.completed).toList();

          return TabBarView(
            controller: _tabController,
            children: [
              _buildDownloadingList(downloadingTasks),
              _buildCompletedList(completedTasks),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDownloadingList(List<DownloadTask> tasks) {
    if (tasks.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.download_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('暂无下载任务', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    // 按作品分组
    final Map<int, List<DownloadTask>> groupedTasks = {};
    for (final task in tasks) {
      groupedTasks.putIfAbsent(task.workId, () => []).add(task);
    }

    return ListView.builder(
      itemCount: groupedTasks.length,
      itemBuilder: (context, index) {
        final workId = groupedTasks.keys.elementAt(index);
        final workTasks = groupedTasks[workId]!;
        final firstTask = workTasks.first;

        final isWorkSelected = _selectedWorkIds.contains(workId);

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: ExpansionTile(
            leading: _isSelectionMode
                ? Checkbox(
                    value: isWorkSelected,
                    onChanged: (_) => _toggleWorkSelection(workId, workTasks),
                  )
                : const Icon(Icons.folder),
            title: Text(
              firstTask.workTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${workTasks.length} 个文件',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: _isSelectionMode ? null : const Icon(Icons.expand_more),
            children: workTasks.map((task) => _buildTaskTile(task)).toList(),
          ),
        );
      },
    );
  }

  Widget _buildTaskTile(DownloadTask task) {
    final isSelected = _selectedTaskIds.contains(task.id);

    return ListTile(
      leading: _isSelectionMode
          ? Checkbox(
              value: isSelected,
              onChanged: (_) => _toggleTaskSelection(task.id),
            )
          : _buildStatusIcon(task.status),
      title: Text(
        task.fileName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: _isSelectionMode ? () => _toggleTaskSelection(task.id) : null,
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (task.totalBytes != null && task.totalBytes! > 0) ...[
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: task.progress,
              backgroundColor: Colors.grey[300],
            ),
            const SizedBox(height: 4),
            Text(
              '${formatBytes(task.downloadedBytes)} / ${formatBytes(task.totalBytes!)} (${(task.progress * 100).toStringAsFixed(1)}%)',
              style: const TextStyle(fontSize: 11),
            ),
          ],
          if (task.error != null) ...[
            const SizedBox(height: 4),
            Text(
              '错误: ${task.error}',
              style: const TextStyle(fontSize: 11, color: Colors.red),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
      trailing: _buildTaskActions(task),
    );
  }

  Widget _buildStatusIcon(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.pending:
        return const Icon(Icons.schedule, color: Colors.grey);
      case DownloadStatus.downloading:
        return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case DownloadStatus.paused:
        return const Icon(Icons.pause_circle, color: Colors.orange);
      case DownloadStatus.completed:
        return const Icon(Icons.check_circle, color: Colors.green);
      case DownloadStatus.failed:
        return const Icon(Icons.error, color: Colors.red);
    }
  }

  Widget _buildTaskActions(DownloadTask task) {
    switch (task.status) {
      case DownloadStatus.downloading:
        return IconButton(
          icon: const Icon(Icons.pause),
          onPressed: () => DownloadService.instance.pauseTask(task.id),
          tooltip: '暂停',
        );
      case DownloadStatus.paused:
      case DownloadStatus.failed:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.play_arrow),
              onPressed: () => DownloadService.instance.resumeTask(task.id),
              tooltip: '继续',
            ),
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () => _confirmDelete(task),
              tooltip: '删除',
            ),
          ],
        );
      default:
        return IconButton(
          icon: const Icon(Icons.delete),
          onPressed: () => _confirmDelete(task),
          tooltip: '删除',
        );
    }
  }

  Widget _buildCompletedList(List<DownloadTask> tasks) {
    if (tasks.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.download_done_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('暂无已完成的下载', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    // 按作品分组
    final Map<int, List<DownloadTask>> groupedTasks = {};
    for (final task in tasks) {
      groupedTasks.putIfAbsent(task.workId, () => []).add(task);
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 400,
        childAspectRatio: 3 / 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: groupedTasks.length,
      itemBuilder: (context, index) {
        final workId = groupedTasks.keys.elementAt(index);
        final workTasks = groupedTasks[workId]!;
        final firstTask = workTasks.first;
        final isWorkSelected = _selectedWorkIds.contains(workId);

        return _buildWorkCard(
          workId: workId,
          workTasks: workTasks,
          firstTask: firstTask,
          isSelected: isWorkSelected,
        );
      },
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

    // 尝试从元数据构建Work对象
    Work? work;
    if (firstTask.workMetadata != null) {
      try {
        final sanitized = _sanitizeMetadata(firstTask.workMetadata!);
        work = Work.fromJson(sanitized);
      } catch (e) {
        // 如果解析失败，使用基本信息
        work = null;
      }
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      child: InkWell(
        onTap: _isSelectionMode
            ? () => _toggleWorkSelection(workId, workTasks)
            : () => _openWorkDetail(workId, firstTask),
        onLongPress: !_isSelectionMode
            ? () {
                setState(() {
                  _isSelectionMode = true;
                  _toggleWorkSelection(workId, workTasks);
                });
              }
            : null,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 封面图片
                Expanded(
                  child: Container(
                    width: double.infinity,
                    color: Colors.grey[300],
                    child: work != null
                        ? Hero(
                            tag: 'offline_work_cover_$workId',
                            child: CachedNetworkImage(
                              imageUrl:
                                  work.getCoverImageUrl(host, token: token),
                              cacheKey: 'work_cover_$workId',
                              fit: BoxFit.cover,
                              errorWidget: (context, url, error) => const Icon(
                                Icons.image_not_supported,
                                size: 48,
                                color: Colors.grey,
                              ),
                            ),
                          )
                        : const Icon(
                            Icons.image_not_supported,
                            size: 48,
                            color: Colors.grey,
                          ),
                  ),
                ),
                // 作品信息
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 标题
                      Text(
                        firstTask.workTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              height: 1.3,
                            ),
                      ),
                      const SizedBox(height: 4),
                      // 文件数量和大小
                      Row(
                        children: [
                          Icon(
                            Icons.folder,
                            size: 14,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${workTasks.length} 个文件',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.storage,
                            size: 14,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            formatBytes(totalSize),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                      // 评分信息（如果有元数据）
                      if (work != null &&
                          work.rateAverage != null &&
                          work.rateCount != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.star,
                              size: 14,
                              color: Colors.amber,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              work.rateAverage!.toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '(${work.rateCount})',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            // 选择框
            if (_isSelectionMode)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (_) => _toggleWorkSelection(workId, workTasks),
                  ),
                ),
              ),
            // 离线标签
            if (firstTask.workMetadata != null)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.offline_bolt, size: 12, color: Colors.white),
                      SizedBox(width: 2),
                      Text(
                        '离线',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
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
      // 深拷贝 metadata 并确保所有嵌套结构正确
      final metadata = _sanitizeMetadata(task.workMetadata!);
      final work = Work.fromJson(metadata);

      // 从 metadata 中提取本地封面路径，动态构建完整路径
      final downloadDir = await DownloadService.instance.getDownloadDirectory();
      final relativeCoverPath = metadata['localCoverPath'] as String?;
      final localCoverPath = relativeCoverPath != null
          ? '${downloadDir.path}/$workId/$relativeCoverPath'
          : null;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => OfflineWorkDetailScreen(
            work: work,
            isOffline: true,
            localCoverPath: localCoverPath,
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('打开作品详情失败: $e'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // 清理和规范化元数据，确保所有嵌套对象都是正确的 Map<String, dynamic>
  Map<String, dynamic> _sanitizeMetadata(Map<String, dynamic> metadata) {
    return _deepSanitize(metadata) as Map<String, dynamic>;
  }

  // 深度递归清理数据结构，将所有对象转换为可序列化的基本类型
  dynamic _deepSanitize(dynamic value) {
    if (value == null) {
      return null;
    } else if (value is Map) {
      final sanitized = <String, dynamic>{};
      value.forEach((key, val) {
        sanitized[key.toString()] = _deepSanitize(val);
      });
      return sanitized;
    } else if (value is List) {
      return value.map((item) => _deepSanitize(item)).toList();
    } else if (value is String ||
        value is num ||
        value is bool ||
        value is int ||
        value is double) {
      // 基本类型直接返回
      return value;
    } else {
      // 对于其他对象类型（如 Va、Tag、AudioFile 等），尝试调用 toJson
      try {
        final dynamic obj = value;
        if (obj is Object && obj.runtimeType.toString().contains('AudioFile')) {
          // AudioFile 对象
          return {
            'title': (obj as dynamic).title,
            'type': (obj as dynamic).type,
            'hash': (obj as dynamic).hash,
            'mediaDownloadUrl': (obj as dynamic).mediaDownloadUrl,
            'size': (obj as dynamic).size,
            'children': _deepSanitize((obj as dynamic).children),
          };
        } else if (obj is Object && obj.runtimeType.toString().contains('Va')) {
          // Va 对象
          return {
            'id': (obj as dynamic).id,
            'name': (obj as dynamic).name,
          };
        } else if (obj is Object &&
            obj.runtimeType.toString().contains('Tag')) {
          // Tag 对象
          return {
            'id': (obj as dynamic).id,
            'name': (obj as dynamic).name,
            'upvote': (obj as dynamic).upvote,
            'downvote': (obj as dynamic).downvote,
            'myVote': (obj as dynamic).myVote,
          };
        } else if (obj is Object &&
            obj.runtimeType.toString().contains('RatingDetail')) {
          // RatingDetail 对象
          return {
            'review_point': (obj as dynamic).reviewPoint,
            'count': (obj as dynamic).count,
            'ratio': (obj as dynamic).ratio,
          };
        } else if (obj is Object &&
            obj.runtimeType.toString().contains('OtherLanguageEdition')) {
          // OtherLanguageEdition 对象
          return {
            'id': (obj as dynamic).id,
            'lang': (obj as dynamic).lang,
            'title': (obj as dynamic).title,
            'source_id': (obj as dynamic).sourceId,
            'is_original': (obj as dynamic).isOriginal,
            'source_type': (obj as dynamic).sourceType,
          };
        }
        // 如果有 toJson 方法，调用它
        return (obj as dynamic).toJson();
      } catch (e) {
        // 无法序列化，返回 null
        return null;
      }
    }
  }

  Future<void> _confirmDelete(DownloadTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除 "${task.fileName}" 吗?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await DownloadService.instance.deleteTask(task.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已删除')),
        );
      }
    }
  }

  Future<void> _confirmBatchDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除选中的 ${_selectedTaskIds.length} 个文件吗?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final taskIds = List<String>.from(_selectedTaskIds);
      for (final taskId in taskIds) {
        await DownloadService.instance.deleteTask(taskId);
      }

      setState(() {
        _isSelectionMode = false;
        _selectedTaskIds.clear();
        _selectedWorkIds.clear();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已删除 ${taskIds.length} 个文件')),
        );
      }
    }
  }
}
