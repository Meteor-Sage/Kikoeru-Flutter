import 'dart:io';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:archive/archive.dart';
import 'package:gbk_codec/gbk_codec.dart';
import 'download_path_service.dart';
import '../utils/file_icon_utils.dart';

/// 字幕库管理服务
class SubtitleLibraryService {
  static const String _libraryFolderName = 'subtitle_library';

  /// 获取字幕库目录
  static Future<Directory> getSubtitleLibraryDirectory() async {
    final downloadDir = await DownloadPathService.getDownloadDirectory();
    final libraryDir = Directory('${downloadDir.path}/$_libraryFolderName');

    // 如果不存在则自动创建
    if (!await libraryDir.exists()) {
      await libraryDir.create(recursive: true);
      print('[SubtitleLibrary] 创建字幕库目录: ${libraryDir.path}');
    }

    return libraryDir;
  }

  /// 检查字幕库是否存在
  static Future<bool> exists() async {
    final libraryDir = await getSubtitleLibraryDirectory();
    return await libraryDir.exists();
  }

  /// 导入单个字幕文件
  static Future<ImportResult> importSubtitleFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'vtt',
          'srt',
          'lrc',
          'txt',
          'ass',
          'ssa',
          'sub',
          'idx',
          'sbv',
          'dfxp',
          'ttml'
        ],
        allowMultiple: true,
      );

      if (result == null || result.files.isEmpty) {
        return ImportResult(
          success: false,
          message: '未选择文件',
        );
      }

      final libraryDir = await getSubtitleLibraryDirectory();
      int successCount = 0;
      int errorCount = 0;
      final List<String> errorFiles = [];

      for (final platformFile in result.files) {
        if (platformFile.path == null) continue;

        final sourceFile = File(platformFile.path!);
        final fileName = platformFile.name;

        // 验证是否是字幕文件
        if (!FileIconUtils.isLyricFile(fileName)) {
          errorCount++;
          errorFiles.add('$fileName (不是字幕文件)');
          continue;
        }

        try {
          final destFile = File('${libraryDir.path}/$fileName');

          // 如果文件已存在，添加序号
          String finalFileName = fileName;
          int counter = 1;
          File finalDestFile = destFile;

          while (await finalDestFile.exists()) {
            final nameWithoutExt =
                fileName.substring(0, fileName.lastIndexOf('.'));
            final ext = fileName.substring(fileName.lastIndexOf('.'));
            finalFileName = '${nameWithoutExt}_$counter$ext';
            finalDestFile = File('${libraryDir.path}/$finalFileName');
            counter++;
          }

          await sourceFile.copy(finalDestFile.path);
          successCount++;
          print('[SubtitleLibrary] 导入字幕文件: $finalFileName');
        } catch (e) {
          errorCount++;
          errorFiles.add('$fileName ($e)');
          print('[SubtitleLibrary] 导入文件失败: $fileName, 错误: $e');
        }
      }

      String message = '成功导入 $successCount 个字幕文件';
      if (errorCount > 0) {
        message += '\n失败 $errorCount 个';
        if (errorFiles.length <= 3) {
          message += ': ${errorFiles.join(", ")}';
        }
      }

      return ImportResult(
        success: successCount > 0,
        message: message,
        importedCount: successCount,
        errorCount: errorCount,
      );
    } catch (e) {
      return ImportResult(
        success: false,
        message: '导入失败: $e',
      );
    }
  }

  /// 导入文件夹（保留内部结构，过滤非字幕文件）
  static Future<ImportResult> importFolder() async {
    try {
      final directoryPath = await FilePicker.platform.getDirectoryPath();

      if (directoryPath == null) {
        return ImportResult(
          success: false,
          message: '未选择文件夹',
        );
      }

      final sourceDir = Directory(directoryPath);
      if (!await sourceDir.exists()) {
        return ImportResult(
          success: false,
          message: '文件夹不存在',
        );
      }

      final libraryDir = await getSubtitleLibraryDirectory();
      final folderName = sourceDir.path.split(Platform.pathSeparator).last;
      final targetDir = Directory('${libraryDir.path}/$folderName');

      int successCount = 0;
      int errorCount = 0;
      int skippedCount = 0;

      // 递归处理文件夹
      await for (final entity
          in sourceDir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          final fileName = entity.path.split(Platform.pathSeparator).last;

          // 只处理字幕文件
          if (!FileIconUtils.isLyricFile(fileName)) {
            skippedCount++;
            continue;
          }

          try {
            // 保持相对路径结构
            final relativePath =
                entity.path.substring(sourceDir.path.length + 1);
            final targetFile = File('${targetDir.path}/$relativePath');

            await targetFile.parent.create(recursive: true);
            await entity.copy(targetFile.path);
            successCount++;
            print('[SubtitleLibrary] 导入: $relativePath');
          } catch (e) {
            errorCount++;
            print('[SubtitleLibrary] 导入文件失败: $fileName, 错误: $e');
          }
        }
      }

      if (successCount == 0) {
        return ImportResult(
          success: false,
          message: '文件夹中没有找到字幕文件',
        );
      }

      String message = '成功导入 $successCount 个字幕文件';
      if (skippedCount > 0) {
        message += '\n跳过 $skippedCount 个非字幕文件';
      }
      if (errorCount > 0) {
        message += '\n失败 $errorCount 个';
      }

      return ImportResult(
        success: true,
        message: message,
        importedCount: successCount,
        errorCount: errorCount,
      );
    } catch (e) {
      return ImportResult(
        success: false,
        message: '导入文件夹失败: $e',
      );
    }
  }

  /// 导入压缩包（解压后按文件夹方式处理）
  static Future<ImportResult> importArchive() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip', 'rar', '7z'],
      );

      if (result == null || result.files.isEmpty) {
        return ImportResult(
          success: false,
          message: '未选择压缩包',
        );
      }

      final platformFile = result.files.first;
      if (platformFile.path == null) {
        return ImportResult(
          success: false,
          message: '无法访问文件',
        );
      }

      final archiveFile = File(platformFile.path!);
      final bytes = await archiveFile.readAsBytes();

      // 解压
      Archive? archive;
      try {
        if (platformFile.extension == 'zip') {
          // 使用 verify: false 以支持中文文件名（GBK/UTF-8编码）
          archive = ZipDecoder().decodeBytes(bytes, verify: false);
        } else {
          return ImportResult(
            success: false,
            message: '暂只支持 ZIP 格式压缩包',
          );
        }
      } catch (e) {
        return ImportResult(
          success: false,
          message: '解压失败，可能是加密的压缩包: $e',
        );
      }

      final libraryDir = await getSubtitleLibraryDirectory();
      final archiveName =
          platformFile.name.substring(0, platformFile.name.lastIndexOf('.'));
      final targetDir = Directory('${libraryDir.path}/$archiveName');

      int successCount = 0;
      int errorCount = 0;
      int skippedCount = 0;

      for (final file in archive.files) {
        if (file.isFile) {
          // 尝试修复文件名编码（处理 GBK 编码的中文文件名）
          String decodedName = file.name;
          try {
            // 如果文件名包含乱码字符，尝试用 GBK 解码
            final nameBytes = latin1.encode(file.name);
            decodedName = gbk_bytes.decode(nameBytes);
          } catch (e) {
            // 如果 GBK 解码失败，保持原文件名
            decodedName = file.name;
          }

          final fileName = decodedName.split('/').last;

          // 只处理字幕文件
          if (!FileIconUtils.isLyricFile(fileName)) {
            skippedCount++;
            continue;
          }

          try {
            final targetFile = File('${targetDir.path}/$decodedName');
            await targetFile.parent.create(recursive: true);
            await targetFile.writeAsBytes(file.content as List<int>);
            successCount++;
            print('[SubtitleLibrary] 解压: $decodedName');
          } catch (e) {
            errorCount++;
            print('[SubtitleLibrary] 解压文件失败: $decodedName, 错误: $e');
          }
        }
      }

      if (successCount == 0) {
        return ImportResult(
          success: false,
          message: '压缩包中没有找到字幕文件',
        );
      }

      String message = '成功导入 $successCount 个字幕文件';
      if (skippedCount > 0) {
        message += '\n跳过 $skippedCount 个非字幕文件';
      }
      if (errorCount > 0) {
        message += '\n失败 $errorCount 个';
      }

      return ImportResult(
        success: true,
        message: message,
        importedCount: successCount,
        errorCount: errorCount,
      );
    } catch (e) {
      return ImportResult(
        success: false,
        message: '导入压缩包失败: $e',
      );
    }
  }

  /// 获取字幕库文件列表（树状结构）
  static Future<List<Map<String, dynamic>>> getSubtitleFiles() async {
    final libraryDir = await getSubtitleLibraryDirectory();

    if (!await libraryDir.exists()) {
      return [];
    }

    return await _buildFileTree(libraryDir, libraryDir.path);
  }

  /// 构建文件树
  static Future<List<Map<String, dynamic>>> _buildFileTree(
      Directory dir, String rootPath) async {
    final List<Map<String, dynamic>> items = [];

    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is Directory) {
          final children = await _buildFileTree(entity, rootPath);
          if (children.isNotEmpty) {
            items.add({
              'type': 'folder',
              'title': entity.path.split(Platform.pathSeparator).last,
              'path': entity.path,
              'children': children,
            });
          }
        } else if (entity is File) {
          final fileName = entity.path.split(Platform.pathSeparator).last;
          if (FileIconUtils.isLyricFile(fileName)) {
            final stat = await entity.stat();
            items.add({
              'type': 'text',
              'title': fileName,
              'path': entity.path,
              'size': stat.size,
              'modified': stat.modified.toIso8601String(),
            });
          }
        }
      }
    } catch (e) {
      print('[SubtitleLibrary] 读取目录失败: ${dir.path}, 错误: $e');
    }

    // 按类型和名称排序
    items.sort((a, b) {
      if (a['type'] == 'folder' && b['type'] != 'folder') return -1;
      if (a['type'] != 'folder' && b['type'] == 'folder') return 1;
      return (a['title'] as String).compareTo(b['title'] as String);
    });

    return items;
  }

  /// 删除字幕文件或文件夹
  static Future<bool> delete(String path) async {
    try {
      final entity = FileSystemEntity.typeSync(path);

      if (entity == FileSystemEntityType.file) {
        await File(path).delete();
      } else if (entity == FileSystemEntityType.directory) {
        await Directory(path).delete(recursive: true);
      } else {
        return false;
      }

      print('[SubtitleLibrary] 已删除: $path');
      return true;
    } catch (e) {
      print('[SubtitleLibrary] 删除失败: $path, 错误: $e');
      return false;
    }
  }

  /// 重命名字幕文件或文件夹
  static Future<bool> rename(String oldPath, String newName) async {
    try {
      final entity = FileSystemEntity.typeSync(oldPath);
      final parentPath =
          oldPath.substring(0, oldPath.lastIndexOf(Platform.pathSeparator));
      final newPath = '$parentPath${Platform.pathSeparator}$newName';

      if (entity == FileSystemEntityType.file) {
        await File(oldPath).rename(newPath);
      } else if (entity == FileSystemEntityType.directory) {
        await Directory(oldPath).rename(newPath);
      } else {
        return false;
      }

      print('[SubtitleLibrary] 已重命名: $oldPath -> $newPath');
      return true;
    } catch (e) {
      print('[SubtitleLibrary] 重命名失败: $oldPath, 错误: $e');
      return false;
    }
  }

  /// 获取字幕库统计信息
  static Future<LibraryStats> getStats() async {
    final libraryDir = await getSubtitleLibraryDirectory();

    if (!await libraryDir.exists()) {
      return LibraryStats(
        totalFiles: 0,
        totalSize: 0,
        folderCount: 0,
      );
    }

    int fileCount = 0;
    int folderCount = 0;
    int totalSize = 0;

    await for (final entity
        in libraryDir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final fileName = entity.path.split(Platform.pathSeparator).last;
        if (FileIconUtils.isLyricFile(fileName)) {
          fileCount++;
          try {
            final stat = await entity.stat();
            totalSize += stat.size;
          } catch (e) {
            // 忽略无法读取的文件
          }
        }
      } else if (entity is Directory) {
        folderCount++;
      }
    }

    return LibraryStats(
      totalFiles: fileCount,
      totalSize: totalSize,
      folderCount: folderCount,
    );
  }
}

/// 导入结果
class ImportResult {
  final bool success;
  final String message;
  final int importedCount;
  final int errorCount;

  ImportResult({
    required this.success,
    required this.message,
    this.importedCount = 0,
    this.errorCount = 0,
  });
}

/// 字幕库统计信息
class LibraryStats {
  final int totalFiles;
  final int totalSize;
  final int folderCount;

  LibraryStats({
    required this.totalFiles,
    required this.totalSize,
    required this.folderCount,
  });

  String get sizeFormatted {
    if (totalSize < 1024) {
      return '$totalSize B';
    } else if (totalSize < 1024 * 1024) {
      return '${(totalSize / 1024).toStringAsFixed(1)} KB';
    } else if (totalSize < 1024 * 1024 * 1024) {
      return '${(totalSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(totalSize / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
  }
}
