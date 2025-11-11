import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/download_task.dart';
import '../services/download_service.dart';
import '../utils/string_utils.dart';
import '../utils/file_icon_utils.dart';

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
    // 切换标签时退出选择模式
    if (_isSelectionMode) {
      setState(() {
        _isSelectionMode = false;
        _selectedTaskIds.clear();
        _selectedWorkIds.clear();
      });
    }
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

    return ListView.builder(
      itemCount: groupedTasks.length,
      itemBuilder: (context, index) {
        final workId = groupedTasks.keys.elementAt(index);
        final workTasks = groupedTasks[workId]!;
        final firstTask = workTasks.first;

        final totalSize = workTasks.fold<int>(
          0,
          (sum, task) => sum + (task.totalBytes ?? 0),
        );

        final isWorkSelected = _selectedWorkIds.contains(workId);

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: ExpansionTile(
            leading: _isSelectionMode
                ? Checkbox(
                    value: isWorkSelected,
                    onChanged: (_) => _toggleWorkSelection(workId, workTasks),
                  )
                : const Icon(Icons.folder, color: Colors.green),
            title: Text(
              firstTask.workTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${workTasks.length} 个文件 • ${formatBytes(totalSize)}',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: _isSelectionMode ? null : const Icon(Icons.expand_more),
            children:
                workTasks.map((task) => _buildCompletedTaskTile(task)).toList(),
          ),
        );
      },
    );
  }

  Widget _buildCompletedTaskTile(DownloadTask task) {
    final isSelected = _selectedTaskIds.contains(task.id);

    return ListTile(
      leading: _isSelectionMode
          ? Checkbox(
              value: isSelected,
              onChanged: (_) => _toggleTaskSelection(task.id),
            )
          : Icon(
              FileIconUtils.getFileIconByName(task.fileName),
              color: FileIconUtils.getFileIconColorByName(task.fileName),
            ),
      title: Text(
        task.fileName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: task.totalBytes != null
          ? Text(
              formatBytes(task.totalBytes!),
              style: const TextStyle(fontSize: 11),
            )
          : null,
      trailing: _isSelectionMode
          ? null
          : IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () => _confirmDelete(task),
              tooltip: '删除',
            ),
      onTap: _isSelectionMode ? () => _toggleTaskSelection(task.id) : null,
    );
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
