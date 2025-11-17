import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';

import '../models/download_task.dart';
import 'cache_service.dart';
import 'storage_service.dart';
import 'kikoeru_api_service.dart';
import 'download_path_service.dart';

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
    // 使用 DownloadPathService 获取下载目录（支持自定义路径）
    return await DownloadPathService.getDownloadDirectory();
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
      final jsonStr = jsonEncode(metadata);
      await metadataFile.writeAsString(jsonStr);
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

        // 使用完整的文件名（包含相对路径），以便后续检测
        final fullFileName = relativePath != null && relativePath.isNotEmpty
            ? '$relativePath/$fileName'
            : fileName;

        final task = DownloadTask(
          id: hash,
          workId: workId,
          workTitle: workTitle,
          fileName: fullFileName, // 使用包含路径的完整文件名
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

    try {
      // 先检查缓存中是否已有此文件
      if (task.hash != null && task.hash!.isNotEmpty) {
        final fileType = task.fileName.split('.').last.toLowerCase();
        final cachedPath = await CacheService.getCachedFileResource(
          workId: task.workId,
          hash: task.hash!,
          fileType: fileType,
        );

        if (cachedPath != null) {
          // 缓存存在,直接复制文件
          print('[Download] 从缓存复制文件: $cachedPath -> $filePath');
          final cachedFile = File(cachedPath);
          if (await cachedFile.exists()) {
            await cachedFile.copy(filePath);

            final completedTask = task.copyWith(
              status: DownloadStatus.completed,
              completedAt: DateTime.now(),
              downloadedBytes: await file.length(),
              totalBytes: await file.length(),
            );
            _updateTask(completedTask, immediate: true);
            _cancelTokens.remove(task.id);
            return;
          }
        }
      }

      // 缓存不存在,从网络下载
      // 节流：限制进度更新频率
      int lastUpdateTime = 0;
      const updateInterval = 500; // 500ms 更新一次

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

      final completedTask = task.copyWith(
        status: DownloadStatus.completed,
        completedAt: DateTime.now(),
      );
      _updateTask(completedTask, immediate: true); // 完成时立即保存
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

  /// 删除单个文件（用于离线详情页）
  /// 删除后会清理空文件夹并同步任务列表
  Future<void> deleteFile(int workId, String relativePath) async {
    try {
      final workDir = await _getWorkDownloadDirectory(workId);
      final file = File('$workDir/$relativePath');

      if (!await file.exists()) {
        throw Exception('文件不存在');
      }

      // 删除文件
      await file.delete();
      print('[Download] 已删除文件: $relativePath');

      // 清理空文件夹
      await _cleanEmptyDirectories(file.parent, workDir);

      // 从任务列表中移除对应的任务
      _tasks.removeWhere((t) =>
          t.workId == workId &&
          t.fileName == relativePath &&
          t.status == DownloadStatus.completed);

      // 检查该作品是否还有其他文件
      final workDirObj = Directory(workDir);
      if (await workDirObj.exists()) {
        final contents = await workDirObj.list().toList();
        // 只剩下 metadata 和 cover 文件时，删除整个作品文件夹
        final hasOtherFiles = contents.any((entity) {
          final name = entity.path.split(Platform.pathSeparator).last;
          return name != 'work_metadata.json' && name != 'cover.jpg';
        });

        if (!hasOtherFiles) {
          await workDirObj.delete(recursive: true);
          print('[Download] 作品文件夹已空，已删除: $workDir');
          // 删除所有相关任务
          _tasks.removeWhere((t) => t.workId == workId);
        }
      }

      await _saveTasks();
      _tasksController.add(List.from(_tasks));
    } catch (e) {
      print('[Download] 删除文件失败: $e');
      rethrow;
    }
  }

  /// 递归清理空文件夹
  Future<void> _cleanEmptyDirectories(Directory dir, String workDir) async {
    try {
      // 不要删除作品根目录
      if (dir.path == workDir) {
        return;
      }

      // 检查目录是否为空
      final contents = await dir.list().toList();
      if (contents.isEmpty) {
        print('[Download] 清理空文件夹: ${dir.path}');
        await dir.delete();

        // 递归检查父目录
        await _cleanEmptyDirectories(dir.parent, workDir);
      }
    } catch (e) {
      print('[Download] 清理空文件夹失败: $e');
    }
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

  // 升级旧版本的作品文件夹（尝试从 API 获取元数据）
  Future<void> _upgradeOldWorkFolders(Map<int, Directory> workFolders) async {
    for (final entry in workFolders.entries) {
      final workId = entry.key;
      final workDir = entry.value;

      // 检查是否已有元数据文件
      final metadataFile = File('${workDir.path}/work_metadata.json');
      if (await metadataFile.exists()) {
        continue; // 已有元数据，跳过
      }

      print('[Download] 发现旧版本作品文件夹，尝试升级: RJ$workId');

      try {
        // 创建 API 服务实例尝试获取元数据
        final apiService = KikoeruApiService();

        // 获取作品详情
        final workData = await apiService.getWork(workId);

        // 获取文件树
        final tracks = await apiService.getWorkTracks(workId);

        // 将 tracks 转换为 children 格式并添加到 workData
        workData['children'] = tracks;

        // 保存元数据（使用相对路径）
        workData['localCoverPath'] = 'cover.jpg';
        await metadataFile.writeAsString(jsonEncode(workData));
        print('[Download] 已保存作品元数据: RJ$workId');

        // 下载封面（使用高清封面 URL）
        final host = StorageService.getString('server_host') ?? '';
        final token = StorageService.getString('auth_token') ?? '';

        if (host.isNotEmpty) {
          String normalizedHost = host;
          if (!host.startsWith('http://') && !host.startsWith('https://')) {
            normalizedHost = 'https://$host';
          }

          final coverUrl = token.isNotEmpty
              ? '$normalizedHost/api/cover/$workId?token=$token'
              : '$normalizedHost/api/cover/$workId';

          await _downloadCoverImage(workId, coverUrl);
          print('[Download] 已下载作品封面: RJ$workId');
        }

        // 尝试组织文件树结构
        await _organizeFilesIntoTree(workId, workDir, tracks);

        print('[Download] 作品升级成功: RJ$workId');
      } catch (e) {
        print('[Download] 升级作品失败 RJ$workId: $e');
        // 升级失败不影响继续运行，保持原有文件不变
      }
    }
  }

  // 将扁平的文件结构组织成树形结构
  Future<void> _organizeFilesIntoTree(
      int workId, Directory workDir, List<dynamic> tracks) async {
    try {
      // 构建文件树映射：hash -> 相对路径
      final Map<String, String> hashToPath = {};

      void buildPathMap(List<dynamic> items, String parentPath) {
        for (final item in items) {
          final type = item['type'] as String?;
          final title =
              item['title'] as String? ?? item['name'] as String? ?? '';
          final hash = item['hash'] as String?;

          if (type == 'folder') {
            // 文件夹，递归处理子项
            final folderPath =
                parentPath.isEmpty ? title : '$parentPath/$title';
            final children = item['children'] as List<dynamic>?;
            if (children != null) {
              buildPathMap(children, folderPath);
            }
          } else if (hash != null) {
            // 文件，记录路径映射
            final filePath = parentPath.isEmpty ? title : '$parentPath/$title';
            hashToPath[hash] = filePath;
          }
        }
      }

      buildPathMap(tracks, '');

      // 扫描工作目录中的所有文件
      await for (final entity in workDir.list()) {
        if (entity is File) {
          final fileName = entity.path.split(Platform.pathSeparator).last;

          // 跳过元数据和封面文件
          if (fileName == 'work_metadata.json' || fileName == 'cover.jpg') {
            continue;
          }

          // 尝试从文件树中找到对应的路径
          String? targetPath;
          for (final entry in hashToPath.entries) {
            final expectedFileName = entry.value.split('/').last;
            if (expectedFileName == fileName) {
              targetPath = entry.value;
              break;
            }
          }

          // 如果找到了对应路径且包含目录，则移动文件
          if (targetPath != null && targetPath.contains('/')) {
            final targetFile = File('${workDir.path}/$targetPath');

            // 创建目标目录
            await targetFile.parent.create(recursive: true);

            // 移动文件
            try {
              await entity.rename(targetFile.path);
              print('[Download] 文件已重新组织: $fileName -> $targetPath');
            } catch (e) {
              // 如果 rename 失败（跨文件系统），尝试复制后删除
              await entity.copy(targetFile.path);
              await entity.delete();
              print('[Download] 文件已复制并重新组织: $fileName -> $targetPath');
            }
          }
        }
      }

      print('[Download] 文件树结构组织完成: RJ$workId');
    } catch (e) {
      print('[Download] 组织文件树失败 RJ$workId: $e');
      // 失败不影响继续运行
    }
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

      // 第二步：检查并升级旧版本文件（没有元数据的文件）
      await _upgradeOldWorkFolders(workFolders);

      // 第三步：扫描硬盘上的所有文件，添加新发现的任务
      final newTasks = <DownloadTask>[];
      for (final entry in workFolders.entries) {
        final workId = entry.key;
        final workDir = entry.value;

        // 加载元数据（现在可能已经通过升级创建了）
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
