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
  }

  Future<Directory> _getDownloadDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final downloadDir = Directory('${appDir.path}/downloads');
    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }
    return downloadDir;
  }

  Future<String> _getWorkDownloadDirectory(int workId) async {
    final downloadDir = await _getDownloadDirectory();
    final workDir = Directory('${downloadDir.path}/$workId');
    if (!await workDir.exists()) {
      await workDir.create(recursive: true);
    }
    return workDir.path;
  }

  // 添加下载任务
  Future<DownloadTask> addTask({
    required int workId,
    required String workTitle,
    required String fileName,
    required String downloadUrl,
    required String? hash,
    int? totalBytes,
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
        final targetPath = '$workDir/$fileName';
        final targetFile = File(targetPath);

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
        );

        _tasks.add(task);
        await _saveTasks();
        _tasksController.add(List.from(_tasks));
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
    );

    _tasks.add(task);
    _tasksController.add(List.from(_tasks));

    // 添加任务后立即保存
    await _saveTasks();

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
    final filePath = '$workDir/${task.fileName}';
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

    // 取消下载
    final token = _cancelTokens[taskId];
    if (token != null) {
      token.cancel();
      _cancelTokens.remove(taskId);
    }

    // 删除文件
    if (task.status == DownloadStatus.completed) {
      final workDir = await _getWorkDownloadDirectory(task.workId);
      final file = File('$workDir/${task.fileName}');
      if (await file.exists()) {
        await file.delete();
      }
    }

    _tasks.removeWhere((t) => t.id == taskId);
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
