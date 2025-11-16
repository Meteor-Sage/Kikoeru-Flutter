import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../models/download_task.dart';
import 'cache_service.dart';
import 'storage_service.dart';

class DownloadService {
  static DownloadService? _instance;
  static DownloadService get instance => _instance ??= DownloadService._();

  DownloadService._();

  final Map<String, CancelToken> _cancelTokens = {};
  final StreamController<List<DownloadTask>> _tasksController =
      StreamController<List<DownloadTask>>.broadcast();
  final List<DownloadTask> _tasks = [];
  final Dio _dio = Dio();

  // 用于延迟保存任务，避免频繁 I/O 操作
  Timer? _saveTimer;
  bool _needsSave = false;

  Stream<List<DownloadTask>> get tasksStream => _tasksController.stream;
  List<DownloadTask> get tasks => List.unmodifiable(_tasks);

  static const String _tasksKey = 'download_tasks';

  Future<void> initialize() async {
    await _loadTasks();
    // 恢复未完成的下载任务
    for (final task in _tasks) {
      if (task.status == DownloadStatus.downloading) {
        _updateTask(task.copyWith(status: DownloadStatus.paused));
      }
    }
    // 启动时从硬盘完全同步任务（静默执行）
    try {
      await reloadMetadataFromDisk();
      print('[Download] 启动时同步完成');
    } catch (e) {
      print('[Download] 启动时同步失败: $e');
      // 同步失败则保持当前状态，等待用户手动刷新
    }
  }

  Future<Directory> _getDownloadDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final downloadDir = Directory('${appDir.path}/downloads');
    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }
    return downloadDir;
  }

  // 公开方法，用于获取下载根目录
  Future<Directory> getDownloadDirectory() async {
    return _getDownloadDirectory();
  }

  Future<String> _getWorkDownloadDirectory(int workId) async {
    final downloadDir = await _getDownloadDirectory();
    final workDir = Directory('${downloadDir.path}/$workId');
    if (!await workDir.exists()) {
      await workDir.create(recursive: true);
    }
    return workDir.path;
  }

  // 下载封面图片到本地
  Future<String?> _downloadCoverImage(int workId, String coverUrl) async {
    try {
      final workDir = await _getWorkDownloadDirectory(workId);
      final coverFile = File('$workDir/cover.jpg');

      // 如果已存在则不重复下载
      if (await coverFile.exists()) {
        return coverFile.path;
      }

      // 下载图片
      await _dio.download(coverUrl, coverFile.path);
      return coverFile.path;
    } catch (e) {
      print('[Download] 下载封面图片失败: $e');
      return null;
    }
  }

  // 保存作品元数据到硬盘（包括下载封面图片）
  Future<void> _saveWorkMetadata(
      int workId, Map<String, dynamic> metadata, String? coverUrl) async {
    try {
      // 先下载封面图片
      if (coverUrl != null && coverUrl.isNotEmpty) {
        final localCoverPath = await _downloadCoverImage(workId, coverUrl);
        if (localCoverPath != null) {
          // 在元数据中只保存相对路径，便于迁移
          metadata['localCoverPath'] = 'cover.jpg';
        }
      }

      final workDir = await _getWorkDownloadDirectory(workId);
      final metadataFile = File('$workDir/work_metadata.json');
      await metadataFile.writeAsString(jsonEncode(metadata));
    } catch (e) {
      print('[Download] 保存作品元数据失败: $e');
    }
  }

  // 从硬盘读取作品元数据
  Future<Map<String, dynamic>?> _loadWorkMetadata(int workId) async {
    try {
      final workDir = await _getWorkDownloadDirectory(workId);
      final metadataFile = File('$workDir/work_metadata.json');
      if (await metadataFile.exists()) {
        final content = await metadataFile.readAsString();
        final metadata = jsonDecode(content) as Map<String, dynamic>;

        // 迁移旧的绝对路径为相对路径
        if (metadata.containsKey('localCoverPath')) {
          final coverPath = metadata['localCoverPath'] as String?;
          if (coverPath != null && coverPath.contains(Platform.pathSeparator)) {
            // 如果包含路径分隔符，说明是绝对路径，转换为相对路径
            metadata['localCoverPath'] = 'cover.jpg';
            // 保存更新后的元数据
            await metadataFile.writeAsString(jsonEncode(metadata));
            print('[Download] 已迁移作品 $workId 的封面路径为相对路径');
          }
        }

        return metadata;
      }
    } catch (e) {
      print('[Download] 读取作品元数据失败: $e');
    }
    return null;
  }

  // 获取作品元数据（公共方法，优先从内存读取，否则从硬盘读取）
  Future<Map<String, dynamic>?> getWorkMetadata(int workId) async {
    // 先尝试从任务中获取
    final task = _tasks.firstWhere(
      (t) => t.workId == workId && t.workMetadata != null,
      orElse: () => DownloadTask(
        id: '',
        workId: 0,
        workTitle: '',
        fileName: '',
        downloadUrl: '',
        createdAt: DateTime.now(),
      ),
    );

    if (task.id.isNotEmpty && task.workMetadata != null) {
      return task.workMetadata;
    }

    // 如果内存中没有，从硬盘读取
    return await _loadWorkMetadata(workId);
  }

  // 添加下载任务
  Future<DownloadTask> addTask({
    required int workId,
    required String workTitle,
    required String fileName,
    required String downloadUrl,
    required String? hash,
    int? totalBytes,
    Map<String, dynamic>? workMetadata,
    String? coverUrl,
    String? relativePath, // 相对路径，用于按文件树组织
  }) async {
    // 检查是否已存在
    final existingTask = _tasks.firstWhere(
      (t) => t.hash == hash && t.workId == workId,
      orElse: () => DownloadTask(
        id: '',
        workId: 0,
        workTitle: '',
        fileName: '',
        downloadUrl: '',
        createdAt: DateTime.now(),
      ),
    );

    if (existingTask.id.isNotEmpty) {
      if (existingTask.status == DownloadStatus.completed) {
        // 如果任务已完成但没有元数据，更新元数据
        if (existingTask.workMetadata == null && workMetadata != null) {
          final updatedTask = existingTask.copyWith(workMetadata: workMetadata);
          _updateTask(updatedTask, immediate: true);
          // 保存元数据到硬盘
          unawaited(_saveWorkMetadata(workId, workMetadata, coverUrl));
          return updatedTask;
        }
        return existingTask;
      }
      // 如果任务存在但未完成，返回现有任务
      return existingTask;
    }

    // 检查缓存中是否已有此文件
    if (hash != null && hash.isNotEmpty) {
      final cachedFile = await CacheService.getCachedAudioFile(hash);
      if (cachedFile != null) {
        // 从缓存移动到下载目录
        final workDir = await _getWorkDownloadDirectory(workId);
        final targetPath = relativePath != null && relativePath.isNotEmpty
            ? '$workDir/$relativePath/$fileName'
            : '$workDir/$fileName';
        final targetFile = File(targetPath);

        // 确保目录存在
        await targetFile.parent.create(recursive: true);

        if (!await targetFile.exists()) {
          await File(cachedFile).copy(targetPath);
        }

        final task = DownloadTask(
          id: hash,
          workId: workId,
          workTitle: workTitle,
          fileName: fileName,
          downloadUrl: downloadUrl,
          hash: hash,
          totalBytes: totalBytes ?? await targetFile.length(),
          downloadedBytes: totalBytes ?? await targetFile.length(),
          status: DownloadStatus.completed,
          createdAt: DateTime.now(),
          completedAt: DateTime.now(),
          workMetadata: workMetadata,
        );

        _tasks.add(task);
        await _saveTasks();
        _tasksController.add(List.from(_tasks));

        // 保存作品元数据到硬盘
        if (workMetadata != null) {
          unawaited(_saveWorkMetadata(workId, workMetadata, coverUrl));
        }

        return task;
      }
    }

    final task = DownloadTask(
      id: hash ?? '${workId}_${DateTime.now().millisecondsSinceEpoch}',
      workId: workId,
      workTitle: workTitle,
      fileName: fileName,
      downloadUrl: downloadUrl,
      hash: hash,
      totalBytes: totalBytes,
      createdAt: DateTime.now(),
      workMetadata: workMetadata,
    );

    _tasks.add(task);
    _tasksController.add(List.from(_tasks));

    // 添加任务后立即保存
    await _saveTasks();

    // 保存作品元数据到硬盘
    if (workMetadata != null) {
      unawaited(_saveWorkMetadata(workId, workMetadata, coverUrl));
    }

    // 自动开始下载（异步，不阻塞返回）
    unawaited(_startDownload(task));

    return task;
  }

  Future<void> _startDownload(DownloadTask task) async {
    if (task.status == DownloadStatus.downloading ||
        task.status == DownloadStatus.completed) {
      return;
    }

    _updateTask(task.copyWith(status: DownloadStatus.downloading),
        immediate: true);

    final workDir = await _getWorkDownloadDirectory(task.workId);
    // 使用fileName中的路径信息（如果包含/）
    final filePath = '$workDir/${task.fileName}';
    final file = File(filePath);

    // 确保父目录存在
    await file.parent.create(recursive: true);

    final cancelToken = CancelToken();
    _cancelTokens[task.id] = cancelToken;

    // 节流：限制进度更新频率
    int lastUpdateTime = 0;
    const updateInterval = 500; // 500ms 更新一次

    try {
      await _dio.download(
        task.downloadUrl,
        filePath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            final now = DateTime.now().millisecondsSinceEpoch;
            // 只在间隔足够时才更新，避免过于频繁的更新
            if (now - lastUpdateTime > updateInterval || received == total) {
              lastUpdateTime = now;
              _updateTask(task.copyWith(
                downloadedBytes: received,
                totalBytes: total,
              )); // 不立即保存，使用延迟保存
            }
          }
        },
      );

      _updateTask(
          task.copyWith(
            status: DownloadStatus.completed,
            completedAt: DateTime.now(),
          ),
          immediate: true); // 完成时立即保存
      _cancelTokens.remove(task.id);
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.cancel) {
        _updateTask(task.copyWith(status: DownloadStatus.paused),
            immediate: true);
      } else {
        _updateTask(
            task.copyWith(
              status: DownloadStatus.failed,
              error: e.toString(),
            ),
            immediate: true);
      }
      _cancelTokens.remove(task.id);
    }
  }

  Future<void> pauseTask(String taskId) async {
    final token = _cancelTokens[taskId];
    if (token != null) {
      token.cancel();
    }
  }

  Future<void> resumeTask(String taskId) async {
    final task = _tasks.firstWhere((t) => t.id == taskId);
    if (task.status == DownloadStatus.paused ||
        task.status == DownloadStatus.failed) {
      await _startDownload(task);
    }
  }

  Future<void> deleteTask(String taskId) async {
    final task = _tasks.firstWhere((t) => t.id == taskId);
    final workId = task.workId;

    // 取消下载
    final token = _cancelTokens[taskId];
    if (token != null) {
      token.cancel();
      _cancelTokens.remove(taskId);
    }

    // 删除文件
    if (task.status == DownloadStatus.completed) {
      final workDir = await _getWorkDownloadDirectory(workId);
      final file = File('$workDir/${task.fileName}');
      if (await file.exists()) {
        await file.delete();
      }
    }

    // 从任务列表中移除
    _tasks.removeWhere((t) => t.id == taskId);

    // 检查该作品是否还有其他任务
    final remainingTasks = _tasks.where((t) => t.workId == workId).toList();
    if (remainingTasks.isEmpty) {
      // 如果没有其他任务了，删除整个作品文件夹
      try {
        final workDir = await _getWorkDownloadDirectory(workId);
        final dir = Directory(workDir);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
          print('[Download] 已删除作品文件夹: $workDir');
        }
      } catch (e) {
        print('[Download] 删除作品文件夹失败: $e');
      }
    }

    await _saveTasks();
    _tasksController.add(List.from(_tasks));
  }

  Future<List<DownloadTask>> getWorkTasks(int workId) async {
    return _tasks.where((t) => t.workId == workId).toList();
  }

  Future<String?> getDownloadedFilePath(int workId, String? hash) async {
    if (hash == null) return null;

    final task = _tasks.firstWhere(
      (t) =>
          t.workId == workId &&
          t.hash == hash &&
          t.status == DownloadStatus.completed,
      orElse: () => DownloadTask(
        id: '',
        workId: 0,
        workTitle: '',
        fileName: '',
        downloadUrl: '',
        createdAt: DateTime.now(),
      ),
    );

    if (task.id.isEmpty) return null;

    final workDir = await _getWorkDownloadDirectory(workId);
    final file = File('$workDir/${task.fileName}');
    if (await file.exists()) {
      return file.path;
    }
    return null;
  }

  void _updateTask(DownloadTask updatedTask, {bool immediate = false}) {
    final index = _tasks.indexWhere((t) => t.id == updatedTask.id);
    if (index != -1) {
      _tasks[index] = updatedTask;
      _tasksController.add(List.from(_tasks));

      // 对于下载进度更新，使用延迟保存避免频繁 I/O
      if (immediate) {
        _saveTasks();
      } else {
        _scheduleDelayedSave();
      }
    }
  }

  // 延迟保存，避免频繁的 I/O 操作
  void _scheduleDelayedSave() {
    _needsSave = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), () {
      if (_needsSave) {
        _saveTasks();
        _needsSave = false;
      }
    });
  }

  Future<void> _loadTasks() async {
    try {
      final prefs = await StorageService.getPrefs();
      final tasksJson = prefs.getString(_tasksKey);
      if (tasksJson != null) {
        final List<dynamic> tasksList = jsonDecode(tasksJson);
        _tasks.clear();
        _tasks.addAll(
          tasksList.map((json) => DownloadTask.fromJson(json)).toList(),
        );
      }
    } catch (e) {
      print('[Download] 加载下载任务失败: $e');
    }
  }

  // 从硬盘加载元数据并补充到任务中
  /// 公开方法：从硬盘完全同步下载任务
  /// 扫描硬盘文件系统，删除不存在的任务，添加新发现的文件
  /// 用于手动刷新，确保下载完成界面与硬盘文件完全一致
  Future<void> reloadMetadataFromDisk() async {
    try {
      print('[Download] 开始从硬盘同步任务...');

      // 获取下载目录
      final downloadDir = await _getDownloadDirectory();
      if (!await downloadDir.exists()) {
        print('[Download] 下载目录不存在，清空所有已完成任务');
        _tasks.removeWhere((t) => t.status == DownloadStatus.completed);
        _tasksController.add(List.from(_tasks));
        await _saveTasks();
        return;
      }

      // 扫描硬盘上所有的作品文件夹
      final workFolders = <int, Directory>{};
      await for (final entity in downloadDir.list()) {
        if (entity is Directory) {
          final workIdStr = entity.path.split(Platform.pathSeparator).last;
          final workId = int.tryParse(workIdStr);
          if (workId != null) {
            workFolders[workId] = entity;
          }
        }
      }

      print('[Download] 发现 ${workFolders.length} 个作品文件夹');

      // 第一步：删除硬盘上不存在的已完成任务
      final tasksToRemove = <String>[];
      for (final task in _tasks) {
        if (task.status == DownloadStatus.completed) {
          final workDir = workFolders[task.workId];
          if (workDir == null) {
            // 作品文件夹不存在，删除任务
            tasksToRemove.add(task.id);
            print('[Download] 作品文件夹不存在，删除任务: ${task.workTitle}');
          } else {
            // 检查文件是否存在
            final file = File('${workDir.path}/${task.fileName}');
            if (!await file.exists()) {
              tasksToRemove.add(task.id);
              print('[Download] 文件不存在，删除任务: ${task.fileName}');
            }
          }
        }
      }

      // 执行删除
      if (tasksToRemove.isNotEmpty) {
        _tasks.removeWhere((t) => tasksToRemove.contains(t.id));
        print('[Download] 删除了 ${tasksToRemove.length} 个不存在的任务');
      }

      // 第二步：扫描硬盘上的所有文件，添加新发现的任务
      final newTasks = <DownloadTask>[];
      for (final entry in workFolders.entries) {
        final workId = entry.key;
        final workDir = entry.value;

        // 加载元数据
        final metadata = await _loadWorkMetadata(workId);
        final workTitle = metadata?['title'] as String? ?? 'RJ$workId';

        // 递归扫描文件夹中的所有文件
        Future<void> scanDirectory(Directory dir, String relativePath) async {
          await for (final entity in dir.list()) {
            if (entity is File) {
              final fileName = entity.path.split(Platform.pathSeparator).last;

              // 跳过元数据和封面文件
              if (fileName == 'work_metadata.json' || fileName == 'cover.jpg') {
                continue;
              }

              // 构建相对路径下的文件名
              final fullFileName =
                  relativePath.isEmpty ? fileName : '$relativePath/$fileName';

              // 检查该文件是否已有对应的任务
              final existingTask = _tasks.firstWhere(
                (t) => t.workId == workId && t.fileName == fullFileName,
                orElse: () => DownloadTask(
                  id: '',
                  workId: 0,
                  workTitle: '',
                  fileName: '',
                  downloadUrl: '',
                  createdAt: DateTime.now(),
                ),
              );

              if (existingTask.id.isEmpty) {
                // 发现新文件，创建任务
                final newTask = DownloadTask(
                  id: '${workId}_${fullFileName}_${DateTime.now().millisecondsSinceEpoch}',
                  workId: workId,
                  workTitle: workTitle,
                  fileName: fullFileName,
                  downloadUrl: '', // 硬盘扫描的任务没有下载URL
                  status: DownloadStatus.completed,
                  totalBytes: await entity.length(),
                  downloadedBytes: await entity.length(),
                  createdAt: entity.statSync().modified,
                  completedAt: entity.statSync().modified,
                  workMetadata: metadata,
                );
                newTasks.add(newTask);
                print('[Download] 发现新文件: $fullFileName (${workTitle})');
              }
            } else if (entity is Directory) {
              // 递归扫描子目录
              final dirName = entity.path.split(Platform.pathSeparator).last;
              final subPath =
                  relativePath.isEmpty ? dirName : '$relativePath/$dirName';
              await scanDirectory(entity, subPath);
            }
          }
        }

        await scanDirectory(workDir, '');
      }

      // 添加新任务
      if (newTasks.isNotEmpty) {
        _tasks.addAll(newTasks);
        print('[Download] 添加了 ${newTasks.length} 个新任务');
      }

      // 第三步：为所有已完成任务更新元数据
      for (var i = 0; i < _tasks.length; i++) {
        final task = _tasks[i];
        if (task.status == DownloadStatus.completed) {
          final metadata = await _loadWorkMetadata(task.workId);
          if (metadata != null) {
            _tasks[i] = task.copyWith(workMetadata: metadata);
          }
        }
      }

      // 通知更新并保存
      _tasksController.add(List.from(_tasks));
      await _saveTasks();

      print(
          '[Download] 同步完成：删除 ${tasksToRemove.length} 个，新增 ${newTasks.length} 个');
    } catch (e) {
      print('[Download] 从硬盘同步任务失败: $e');
      rethrow;
    }
  }

  Future<void> _saveTasks() async {
    try {
      final prefs = await StorageService.getPrefs();
      final tasksJson = jsonEncode(_tasks.map((t) => t.toJson()).toList());
      await prefs.setString(_tasksKey, tasksJson);
    } catch (e) {
      print('[Download] 保存下载任务失败: $e');
    }
  }

  void dispose() {
    _saveTimer?.cancel();
    _saveTimer = null;
    _tasksController.close();
    for (final token in _cancelTokens.values) {
      token.cancel();
    }
    _cancelTokens.clear();

    // 确保最后保存一次
    if (_needsSave) {
      _saveTasks();
    }
  }
}
