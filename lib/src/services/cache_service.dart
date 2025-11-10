import 'dart:io';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'storage_service.dart';

class CacheService {
  // 缓存时长（过期后自动删除）
  static const Duration workDetailCacheDuration =
      Duration(hours: 24); // 作品详情缓存24小时（SharedPreferences）
  static const Duration workTracksCacheDuration =
      Duration(hours: 24); // 作品文件列表缓存24小时（包含URL，避免token过期）
  static const Duration fileCacheDuration =
      Duration(days: 30); // 文件资源（PDF等）缓存30天（基于hash，不受URL变化影响）
  static const Duration audioCacheDuration =
      Duration(days: 30); // 音频文件缓存30天（基于hash，不受URL变化影响）
  // 注意：图片缓存由 cached_network_image 包自己管理过期时间（默认7天）

  static String _safeAudioHash(String hash) => hash.replaceAll('/', '_');

  static Future<File> _audioFinalFile(String hash) async {
    final safeHash = _safeAudioHash(hash);
    final cacheDir = await _getAudioCacheDirectory();
    return File('${cacheDir.path}/$safeHash.audio');
  }

  static Future<File> _audioTempFile(String hash) async {
    final safeHash = _safeAudioHash(hash);
    final cacheDir = await _getAudioCacheDirectory();
    return File('${cacheDir.path}/$safeHash.audio.part');
  }

  static Future<void> _writeAudioCacheMeta(String hash) async {
    final safeHash = _safeAudioHash(hash);
    final prefs = await StorageService.getPrefs();
    await prefs.setInt(
        'audio_cache_meta_$safeHash', DateTime.now().millisecondsSinceEpoch);
  }

  static Future<void> _removeAudioCacheMeta(String hash) async {
    final safeHash = _safeAudioHash(hash);
    final prefs = await StorageService.getPrefs();
    await prefs.remove('audio_cache_meta_$safeHash');
  }

  static Future<void> resetAudioCachePartial(String hash) async {
    final tempFile = await _audioTempFile(hash);
    if (await tempFile.exists()) {
      await tempFile.delete();
    }
    // 在重新下载之前移除旧的 meta，防止过期逻辑误判
    await _removeAudioCacheMeta(hash);
  }

  static Future<File> prepareAudioCacheTempFile(String hash) async {
    final tempFile = await _audioTempFile(hash);
    if (!await tempFile.exists()) {
      await tempFile.create(recursive: true);
    }
    return tempFile;
  }

  static Future<void> finalizeAudioCacheFile(String hash,
      {required int expectedSize}) async {
    final tempFile = await _audioTempFile(hash);
    if (!await tempFile.exists()) {
      return;
    }

    final currentSize = await tempFile.length();
    if (currentSize < expectedSize) {
      return;
    }

    final finalFile = await _audioFinalFile(hash);

    if (await finalFile.exists()) {
      await finalFile.delete();
    }

    await tempFile.rename(finalFile.path);
    await _writeAudioCacheMeta(hash);
  }

  // 缓存大小上限配置键
  static const String cacheSizeLimitKey = 'cache_size_limit_mb';
  static const int defaultCacheSizeLimitMB = 1000; // 默认1GB (1000MB)

  // 自动清理检查间隔（避免过于频繁检查）
  static const Duration autoCleanCheckInterval = Duration(minutes: 5);
  static const String lastCleanCheckTimeKey = 'last_clean_check_time';

  // 缓存作品详情
  static Future<void> cacheWorkDetail(
      int workId, Map<String, dynamic> workData) async {
    final prefs = await StorageService.getPrefs();
    final cacheKey = 'work_detail_$workId';
    final cacheTimeKey = 'work_detail_time_$workId';

    // 使用 JSON 编码保存完整数据
    await prefs.setString(cacheKey, jsonEncode(workData));
    await prefs.setInt(cacheTimeKey, DateTime.now().millisecondsSinceEpoch);
  }

  // 获取缓存的作品详情
  static Future<Map<String, dynamic>?> getCachedWorkDetail(int workId) async {
    final prefs = await StorageService.getPrefs();
    final cacheKey = 'work_detail_$workId';
    final cacheTimeKey = 'work_detail_time_$workId';

    final cachedData = prefs.getString(cacheKey);
    final cacheTime = prefs.getInt(cacheTimeKey);

    if (cachedData == null || cacheTime == null) {
      return null;
    }

    // 检查是否过期
    final cacheDateTime = DateTime.fromMillisecondsSinceEpoch(cacheTime);
    if (DateTime.now().difference(cacheDateTime) > workDetailCacheDuration) {
      // 过期，删除缓存
      await prefs.remove(cacheKey);
      await prefs.remove(cacheTimeKey);
      return null;
    }

    // 返回解码后的完整数据
    try {
      return jsonDecode(cachedData) as Map<String, dynamic>;
    } catch (e) {
      print('[Cache] 解码作品详情缓存失败: $e');
      // 数据损坏，删除缓存
      await prefs.remove(cacheKey);
      await prefs.remove(cacheTimeKey);
      return null;
    }
  }

  // 清除指定作品的详情缓存（用于收藏状态更新后强制刷新）
  static Future<void> invalidateWorkDetailCache(int workId) async {
    final prefs = await StorageService.getPrefs();
    final cacheKey = 'work_detail_$workId';
    final cacheTimeKey = 'work_detail_time_$workId';

    await prefs.remove(cacheKey);
    await prefs.remove(cacheTimeKey);
    print('[Cache] 已清除作品详情缓存: $workId');
  }

  // 缓存作品文件列表
  static Future<void> cacheWorkTracks(int workId, String tracksJson) async {
    final prefs = await StorageService.getPrefs();
    final cacheKey = 'work_tracks_$workId';
    final cacheTimeKey = 'work_tracks_time_$workId';

    await prefs.setString(cacheKey, tracksJson);
    await prefs.setInt(cacheTimeKey, DateTime.now().millisecondsSinceEpoch);
  }

  // 获取缓存的作品文件列表
  static Future<String?> getCachedWorkTracks(int workId) async {
    final prefs = await StorageService.getPrefs();
    final cacheKey = 'work_tracks_$workId';
    final cacheTimeKey = 'work_tracks_time_$workId';

    final cachedData = prefs.getString(cacheKey);
    final cacheTime = prefs.getInt(cacheTimeKey);

    if (cachedData == null || cacheTime == null) {
      return null;
    }

    // 检查是否过期
    final cacheDateTime = DateTime.fromMillisecondsSinceEpoch(cacheTime);
    if (DateTime.now().difference(cacheDateTime) > workTracksCacheDuration) {
      // 过期，删除缓存
      await prefs.remove(cacheKey);
      await prefs.remove(cacheTimeKey);
      return null;
    }

    return cachedData;
  }

  // 缓存音频文件（基于 hash）
  static Future<String?> cacheAudioFile({
    required String hash,
    required String url,
    required Dio dio,
  }) async {
    try {
      final finalFile = await _audioFinalFile(hash);
      final file = finalFile;
      if (await file.exists()) {
        final lastModified = await file.lastModified();
        if (DateTime.now().difference(lastModified) < audioCacheDuration) {
          print('[Cache] 音频缓存命中: $hash');
          return file.path; // 未过期，直接返回
        }
        // 过期，删除旧文件
        print('[Cache] 音频缓存过期，重新下载: $hash');
        await file.delete();
        await _removeAudioCacheMeta(hash);
      }

      // 清理旧的临时文件
      await resetAudioCachePartial(hash);
      final tempFile = await prepareAudioCacheTempFile(hash);

      // 下载文件（先至临时文件）
      print('[Cache] 下载音频文件: $hash');
      await dio.download(url, tempFile.path);

      // 下载完成后重命名为最终文件并写入 meta
      await finalizeAudioCacheFile(hash, expectedSize: await tempFile.length());

      // 检查并自动清理缓存
      await checkAndCleanCache();
      return (await _audioFinalFile(hash)).path;
    } catch (e) {
      print('[Cache] 缓存音频文件失败: $e');
      return null;
    }
  }

  // 获取缓存的音频文件（基于 hash）
  static Future<String?> getCachedAudioFile(String hash) async {
    try {
      final finalFile = await _audioFinalFile(hash);
      final tempFile = await _audioTempFile(hash);

      // 如果只有临时文件存在，说明尚未缓存完成
      if (!await finalFile.exists()) {
        // 清理久远的临时文件，避免占用空间
        if (await tempFile.exists()) {
          final lastModified = await tempFile.lastModified();
          if (DateTime.now().difference(lastModified) > audioCacheDuration) {
            await tempFile.delete();
          }
        }
        return null;
      }

      final file = finalFile;
      if (await file.exists()) {
        // 检查是否过期
        final prefs = await StorageService.getPrefs();
        final metaKey = 'audio_cache_meta_${_safeAudioHash(hash)}';
        final cacheTime = prefs.getInt(metaKey);

        if (cacheTime != null) {
          final cacheDateTime = DateTime.fromMillisecondsSinceEpoch(cacheTime);
          if (DateTime.now().difference(cacheDateTime) < audioCacheDuration) {
            print('[Cache] 使用缓存的音频文件: $hash');
            return file.path; // 未过期
          }
        }

        // 过期，删除
        print('[Cache] 音频缓存过期: $hash');
        await file.delete();
        await prefs.remove(metaKey);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      }

      return null;
    } catch (e) {
      print('[Cache] 获取缓存音频文件失败: $e');
      return null;
    }
  }

  // 缓存文件资源（PDF等）
  static Future<String?> cacheFileResource({
    required int workId,
    required String hash,
    required String fileType,
    required String url,
    required Dio dio,
  }) async {
    try {
      final cacheDir = await _getCacheDirectory();
      // 使用 hash 作为文件名（替换路径分隔符为下划线）
      final safeHash = hash.replaceAll('/', '_');
      final fileName = '${workId}_${safeHash}_$fileType';
      final filePath = '${cacheDir.path}/$fileName';

      // 如果文件已存在，检查是否过期
      final file = File(filePath);
      if (await file.exists()) {
        final lastModified = await file.lastModified();
        if (DateTime.now().difference(lastModified) < fileCacheDuration) {
          return filePath; // 未过期，直接返回
        }
        // 过期，删除旧文件
        await file.delete();
      }

      // 下载文件
      await dio.download(url, filePath);

      // 保存缓存元数据
      final prefs = await StorageService.getPrefs();
      final metaKey = 'file_cache_meta_${workId}_$safeHash';
      await prefs.setInt(metaKey, DateTime.now().millisecondsSinceEpoch);

      // 检查并自动清理缓存
      await checkAndCleanCache();

      return filePath;
    } catch (e) {
      print('[Cache] 缓存文件失败: $e');
      return null;
    }
  }

  // 获取缓存的文件资源
  static Future<String?> getCachedFileResource({
    required int workId,
    required String hash,
    required String fileType,
  }) async {
    try {
      final cacheDir = await _getCacheDirectory();
      final safeHash = hash.replaceAll('/', '_');
      final fileName = '${workId}_${safeHash}_$fileType';
      final filePath = '${cacheDir.path}/$fileName';

      final file = File(filePath);
      if (await file.exists()) {
        // 检查是否过期
        final prefs = await StorageService.getPrefs();
        final metaKey = 'file_cache_meta_${workId}_$safeHash';
        final cacheTime = prefs.getInt(metaKey);

        if (cacheTime != null) {
          final cacheDateTime = DateTime.fromMillisecondsSinceEpoch(cacheTime);
          if (DateTime.now().difference(cacheDateTime) < fileCacheDuration) {
            return filePath; // 未过期
          }
        }

        // 过期，删除
        await file.delete();
        await prefs.remove(metaKey);
      }

      return null;
    } catch (e) {
      print('[Cache] 获取缓存文件失败: $e');
      return null;
    }
  }

  // 缓存文本内容
  static Future<void> cacheTextContent({
    required int workId,
    required String hash,
    required String content,
  }) async {
    try {
      final cacheDir = await _getCacheDirectory();
      final safeHash = hash.replaceAll('/', '_');
      final fileName = '${workId}_${safeHash}_text.txt';
      final filePath = '${cacheDir.path}/$fileName';

      final file = File(filePath);
      await file.writeAsString(content);

      // 保存缓存元数据
      final prefs = await StorageService.getPrefs();
      final metaKey = 'text_cache_meta_${workId}_$safeHash';
      await prefs.setInt(metaKey, DateTime.now().millisecondsSinceEpoch);

      // 检查并自动清理缓存
      await checkAndCleanCache();
    } catch (e) {
      print('[Cache] 缓存文本失败: $e');
    }
  }

  // 获取缓存的文本内容
  static Future<String?> getCachedTextContent({
    required int workId,
    required String hash,
  }) async {
    try {
      final cacheDir = await _getCacheDirectory();
      final safeHash = hash.replaceAll('/', '_');
      final fileName = '${workId}_${safeHash}_text.txt';
      final filePath = '${cacheDir.path}/$fileName';

      final file = File(filePath);
      if (await file.exists()) {
        // 检查是否过期
        final prefs = await StorageService.getPrefs();
        final metaKey = 'text_cache_meta_${workId}_$safeHash';
        final cacheTime = prefs.getInt(metaKey);

        if (cacheTime != null) {
          final cacheDateTime = DateTime.fromMillisecondsSinceEpoch(cacheTime);
          if (DateTime.now().difference(cacheDateTime) < fileCacheDuration) {
            return await file.readAsString(); // 未过期
          }
        }

        // 过期，删除
        await file.delete();
        await prefs.remove(metaKey);
      }

      return null;
    } catch (e) {
      print('[Cache] 获取缓存文本失败: $e');
      return null;
    }
  }

  // 清除所有缓存
  static Future<void> clearAllCache() async {
    try {
      // 1. 清除文件缓存（PDF、文本等）
      final cacheDir = await _getCacheDirectory();
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
      }

      // 2. 清除音频缓存
      await clearAudioCache();

      // 3. 清除图片缓存
      await clearImageCache();

      // 4. 清除 SharedPreferences 中的缓存元数据
      final prefs = await StorageService.getPrefs();
      final keys = prefs.getKeys();
      for (final key in keys) {
        if (key.startsWith('work_detail_') ||
            key.startsWith('work_tracks_') ||
            key.startsWith('file_cache_meta_') ||
            key.startsWith('text_cache_meta_') ||
            key.startsWith('audio_cache_meta_')) {
          await prefs.remove(key);
        }
      }

      print('[Cache] 所有缓存已清除');
    } catch (e) {
      print('[Cache] 清除缓存失败: $e');
      rethrow;
    }
  }

  // 清除音频缓存
  static Future<void> clearAudioCache() async {
    try {
      // 1. 清除自定义音频缓存（基于 hash）
      final customAudioCacheDir = await _getAudioCacheDirectory();
      if (await customAudioCacheDir.exists()) {
        await customAudioCacheDir.delete(recursive: true);
        print('[Cache] 自定义音频缓存已清除');
      }

      // 2. 清除 SharedPreferences 中的音频缓存元数据
      final prefs = await StorageService.getPrefs();
      final keys = prefs.getKeys();
      for (final key in keys) {
        if (key.startsWith('audio_cache_meta_')) {
          await prefs.remove(key);
        }
      }

      // 3. 清除 just_audio 的旧缓存（如果存在）
      final appCacheDir = await getApplicationCacheDirectory();
      final justAudioCacheDir =
          Directory('${appCacheDir.path}/just_audio_cache');
      if (await justAudioCacheDir.exists()) {
        await justAudioCacheDir.delete(recursive: true);
        print('[Cache] just_audio 缓存已清除');
      }
    } catch (e) {
      print('[Cache] 清除音频缓存失败: $e');
    }
  }

  // 清除图片缓存
  static Future<void> clearImageCache() async {
    try {
      final appCacheDir = await getApplicationCacheDirectory();
      final imageCacheDir = Directory('${appCacheDir.path}/libCachedImageData');

      if (await imageCacheDir.exists()) {
        await imageCacheDir.delete(recursive: true);
        print('[Cache] 图片缓存已清除');
      }
    } catch (e) {
      print('[Cache] 清除图片缓存失败: $e');
    }
  }

  // 获取缓存大小
  static Future<int> getCacheSize() async {
    try {
      int totalSize = 0;

      // 1. 获取 Kikoeru 自定义缓存大小（PDF、文本等）
      final cacheDir = await _getCacheDirectory();
      if (await cacheDir.exists()) {
        await for (final entity in cacheDir.list(recursive: true)) {
          if (entity is File) {
            totalSize += await entity.length();
          }
        }
      }

      // 2. 获取 just_audio 的音频缓存大小
      final audioCacheSize = await _getAudioCacheSize();
      totalSize += audioCacheSize;

      // 3. 获取 CachedNetworkImage 的图片缓存大小
      final imageCacheSize = await _getImageCacheSize();
      totalSize += imageCacheSize;

      // 4. 获取 SharedPreferences 的作品详情缓存大小（估算）
      final prefsSize = await _getSharedPreferencesCacheSize();
      totalSize += prefsSize;

      return totalSize;
    } catch (e) {
      print('[Cache] 获取缓存大小失败: $e');
      return 0;
    }
  }

  // 获取音频缓存目录大小
  static Future<int> _getAudioCacheSize() async {
    try {
      int totalSize = 0;

      // 1. 获取自定义音频缓存大小（基于 hash）
      final customAudioCacheDir = await _getAudioCacheDirectory();
      if (await customAudioCacheDir.exists()) {
        await for (final entity in customAudioCacheDir.list(recursive: true)) {
          if (entity is File) {
            totalSize += await entity.length();
          }
        }
      }

      // 2. 获取 just_audio 的旧缓存大小（如果存在）
      final appCacheDir = await getApplicationCacheDirectory();
      final justAudioCacheDir =
          Directory('${appCacheDir.path}/just_audio_cache');
      if (await justAudioCacheDir.exists()) {
        await for (final entity in justAudioCacheDir.list(recursive: true)) {
          if (entity is File) {
            totalSize += await entity.length();
          }
        }
      }

      return totalSize;
    } catch (e) {
      print('[Cache] 获取音频缓存大小失败: $e');
      return 0;
    }
  }

  // 获取图片缓存目录大小
  static Future<int> _getImageCacheSize() async {
    try {
      // cached_network_image 使用 flutter_cache_manager 管理缓存
      // 默认缓存目录名为 libCachedImageData
      final appCacheDir = await getApplicationCacheDirectory();
      final imageCacheDir = Directory('${appCacheDir.path}/libCachedImageData');

      if (!await imageCacheDir.exists()) {
        return 0;
      }

      int totalSize = 0;
      await for (final entity in imageCacheDir.list(recursive: true)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }

      return totalSize;
    } catch (e) {
      print('[Cache] 获取图片缓存大小失败: $e');
      return 0;
    }
  }

  // 获取 SharedPreferences 缓存大小（估算）
  static Future<int> _getSharedPreferencesCacheSize() async {
    try {
      final prefs = await StorageService.getPrefs();
      final keys = prefs.getKeys();
      int estimatedSize = 0;

      for (final key in keys) {
        // 只统计缓存相关的键
        if (key.startsWith('work_detail_') ||
            key.startsWith('work_tracks_') ||
            key.startsWith('file_cache_meta_') ||
            key.startsWith('text_cache_meta_') ||
            key.startsWith('audio_cache_meta_')) {
          // 估算：键名长度 + 值长度
          estimatedSize += key.length;

          final value = prefs.get(key);
          if (value is String) {
            estimatedSize += value.length;
          } else if (value is int) {
            estimatedSize += 8; // int 通常 8 字节
          }
        }
      }

      return estimatedSize;
    } catch (e) {
      print('[Cache] 获取 SharedPreferences 缓存大小失败: $e');
      return 0;
    }
  }

  // 获取缓存目录
  static Future<Directory> _getCacheDirectory() async {
    final appCacheDir = await getApplicationCacheDirectory();
    final cacheDir = Directory('${appCacheDir.path}/kikoeru_cache');

    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }

    return cacheDir;
  }

  // 获取音频缓存目录
  static Future<Directory> _getAudioCacheDirectory() async {
    final appCacheDir = await getApplicationCacheDirectory();
    final cacheDir = Directory('${appCacheDir.path}/kikoeru_audio_cache');

    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }

    return cacheDir;
  }

  // 设置缓存大小上限（MB）
  static Future<void> setCacheSizeLimit(int limitMB) async {
    final prefs = await StorageService.getPrefs();
    await prefs.setInt(cacheSizeLimitKey, limitMB);
  }

  // 获取缓存大小上限（MB）
  static Future<int> getCacheSizeLimit() async {
    final prefs = await StorageService.getPrefs();
    return prefs.getInt(cacheSizeLimitKey) ?? defaultCacheSizeLimitMB;
  }

  // 检查并自动清理缓存（如果超过上限）
  // 使用时间间隔控制，避免过于频繁检查
  static Future<void> checkAndCleanCache({bool force = false}) async {
    try {
      // 如果不是强制检查，先判断是否需要检查
      if (!force) {
        final prefs = await StorageService.getPrefs();
        final lastCheckTime = prefs.getInt(lastCleanCheckTimeKey);

        if (lastCheckTime != null) {
          final lastCheck = DateTime.fromMillisecondsSinceEpoch(lastCheckTime);
          final timeSinceLastCheck = DateTime.now().difference(lastCheck);

          // 如果距离上次检查不到5分钟，跳过检查
          if (timeSinceLastCheck < autoCleanCheckInterval) {
            return;
          }
        }

        // 更新最后检查时间
        await prefs.setInt(
            lastCleanCheckTimeKey, DateTime.now().millisecondsSinceEpoch);
      }

      // 1. 先清理过期的缓存文件（基于时间）
      await _cleanExpiredCacheFiles();

      // 2. 再检查大小，如果超过上限则清理旧文件（基于大小）
      final currentSize = await getCacheSize();
      final limitMB = await getCacheSizeLimit();
      final limitBytes = limitMB * 1024 * 1024;

      if (currentSize > limitBytes) {
        print(
            '[Cache] 缓存大小 ${_formatBytes(currentSize)} 超过上限 ${limitMB}MB，开始清理...');
        await _cleanOldCacheFiles(limitBytes);
      }
    } catch (e) {
      print('[Cache] 自动清理缓存失败: $e');
    }
  }

  // 清理过期的缓存文件（基于时间）
  static Future<void> _cleanExpiredCacheFiles() async {
    try {
      final now = DateTime.now();
      int deletedCount = 0;

      // 1. 清理过期的自定义缓存文件（PDF、文本等）
      final cacheDir = await _getCacheDirectory();
      if (await cacheDir.exists()) {
        await for (final entity in cacheDir.list(recursive: true)) {
          if (entity is File) {
            final lastModified = await entity.lastModified();
            if (now.difference(lastModified) > fileCacheDuration) {
              await entity.delete();
              deletedCount++;

              // 删除对应的元数据
              final fileName = entity.path.split(Platform.pathSeparator).last;
              await _removeMetadataForFile(fileName);
            }
          }
        }
      }

      // 2. 清理过期的音频缓存文件（基于 hash）
      final customAudioCacheDir = await _getAudioCacheDirectory();
      if (await customAudioCacheDir.exists()) {
        await for (final entity in customAudioCacheDir.list(recursive: true)) {
          if (entity is File) {
            final lastModified = await entity.lastModified();
            if (now.difference(lastModified) > audioCacheDuration) {
              await entity.delete();
              deletedCount++;

              // 删除对应的元数据
              final fileName = entity.path.split(Platform.pathSeparator).last;
              final prefs = await StorageService.getPrefs();
              if (fileName.endsWith('.audio')) {
                final safeHash = fileName.replaceAll('.audio', '');
                await prefs.remove('audio_cache_meta_$safeHash');
              }
            }
          }
        }
      }

      // 清理旧的 just_audio 缓存（如果存在）
      final appCacheDir = await getApplicationCacheDirectory();
      final audioCacheDir = Directory('${appCacheDir.path}/just_audio_cache');
      if (await audioCacheDir.exists()) {
        await for (final entity in audioCacheDir.list(recursive: true)) {
          if (entity is File) {
            final lastModified = await entity.lastModified();
            if (now.difference(lastModified) > audioCacheDuration) {
              await entity.delete();
              deletedCount++;
            }
          }
        }
      }

      // 3. 清理过期的 SharedPreferences 作品详情缓存
      final prefsDeletedCount = await _cleanExpiredSharedPreferences();
      deletedCount += prefsDeletedCount;

      // 4. 图片缓存由 cached_network_image 自己管理过期时间，不需要手动清理

      if (deletedCount > 0) {
        print('[Cache] 已清理 $deletedCount 个过期缓存项');
      }
    } catch (e) {
      print('[Cache] 清理过期缓存文件失败: $e');
    }
  }

  // 清理过期的 SharedPreferences 缓存
  static Future<int> _cleanExpiredSharedPreferences() async {
    try {
      final prefs = await StorageService.getPrefs();
      final keys = prefs.getKeys();
      final now = DateTime.now();
      int deletedCount = 0;

      for (final key in keys) {
        // 检查作品详情缓存是否过期
        if (key.startsWith('work_detail_time_')) {
          final cacheTime = prefs.getInt(key);
          if (cacheTime != null) {
            final cacheDateTime =
                DateTime.fromMillisecondsSinceEpoch(cacheTime);
            if (now.difference(cacheDateTime) > workDetailCacheDuration) {
              // 过期，删除缓存数据和时间戳
              final workId = key.replaceFirst('work_detail_time_', '');
              await prefs.remove('work_detail_$workId');
              await prefs.remove(key);
              deletedCount += 2;
            }
          }
        }
        // 检查作品文件列表缓存是否过期
        else if (key.startsWith('work_tracks_time_')) {
          final cacheTime = prefs.getInt(key);
          if (cacheTime != null) {
            final cacheDateTime =
                DateTime.fromMillisecondsSinceEpoch(cacheTime);
            if (now.difference(cacheDateTime) > workTracksCacheDuration) {
              // 过期，删除缓存数据和时间戳
              final workId = key.replaceFirst('work_tracks_time_', '');
              await prefs.remove('work_tracks_$workId');
              await prefs.remove(key);
              deletedCount += 2;
            }
          }
        }
        // 文件和文本的元数据会在清理文件时一起删除，这里不需要单独处理
      }

      return deletedCount;
    } catch (e) {
      print('[Cache] 清理过期 SharedPreferences 失败: $e');
      return 0;
    }
  }

  // 清理旧缓存文件，直到降低到上限的80%
  static Future<void> _cleanOldCacheFiles(int limitBytes) async {
    try {
      final targetSize = (limitBytes * 0.8).toInt();

      // 收集所有缓存文件（包括 Kikoeru 缓存、音频缓存和图片缓存）
      final List<MapEntry<File, DateTime>> fileList = [];

      // 1. 收集 Kikoeru 自定义缓存文件（PDF、文本等）
      final cacheDir = await _getCacheDirectory();
      if (await cacheDir.exists()) {
        await for (final entity in cacheDir.list(recursive: true)) {
          if (entity is File) {
            final lastModified = await entity.lastModified();
            fileList.add(MapEntry(entity, lastModified));
          }
        }
      }

      // 2. 收集音频缓存文件（自定义音频缓存 + just_audio 旧缓存）
      final customAudioCacheDir = await _getAudioCacheDirectory();
      if (await customAudioCacheDir.exists()) {
        await for (final entity in customAudioCacheDir.list(recursive: true)) {
          if (entity is File) {
            final lastModified = await entity.lastModified();
            fileList.add(MapEntry(entity, lastModified));
          }
        }
      }

      final appCacheDir = await getApplicationCacheDirectory();
      final audioCacheDir = Directory('${appCacheDir.path}/just_audio_cache');
      if (await audioCacheDir.exists()) {
        await for (final entity in audioCacheDir.list(recursive: true)) {
          if (entity is File) {
            final lastModified = await entity.lastModified();
            fileList.add(MapEntry(entity, lastModified));
          }
        }
      }

      // 3. 收集图片缓存文件
      final imageCacheDir = Directory('${appCacheDir.path}/libCachedImageData');
      if (await imageCacheDir.exists()) {
        await for (final entity in imageCacheDir.list(recursive: true)) {
          if (entity is File) {
            final lastModified = await entity.lastModified();
            fileList.add(MapEntry(entity, lastModified));
          }
        }
      }

      // 按修改时间排序（旧的在前）
      fileList.sort((a, b) => a.value.compareTo(b.value));

      // 计算当前总大小
      int currentSize = 0;
      for (final entry in fileList) {
        currentSize += await entry.key.length();
      }

      // 删除旧文件直到降低到目标大小
      int deletedCount = 0;
      for (final entry in fileList) {
        if (currentSize <= targetSize) {
          break;
        }

        final fileSize = await entry.key.length();
        await entry.key.delete();
        currentSize -= fileSize;
        deletedCount++;

        // 只为 Kikoeru 自定义缓存删除元数据
        final fileName = entry.key.path.split(Platform.pathSeparator).last;
        if (entry.key.path.contains('kikoeru_cache')) {
          await _removeMetadataForFile(fileName);
        } else if (entry.key.path.contains('kikoeru_audio_cache')) {
          // 删除音频缓存元数据
          if (fileName.endsWith('.audio')) {
            final safeHash = fileName.replaceAll('.audio', '');
            final prefs = await StorageService.getPrefs();
            await prefs.remove('audio_cache_meta_$safeHash');
          }
        }
      }

      print(
          '[Cache] 已删除 $deletedCount 个旧缓存文件，当前大小: ${_formatBytes(currentSize)}');
    } catch (e) {
      print('[Cache] 清理旧缓存文件失败: $e');
    }
  }

  // 删除文件对应的元数据
  static Future<void> _removeMetadataForFile(String fileName) async {
    try {
      final prefs = await StorageService.getPrefs();

      // 从文件名解析出 workId 和 hash
      // 文件名格式: {workId}_{safeHash}_{fileType}
      final parts = fileName.split('_');
      if (parts.length >= 2) {
        final workId = parts[0];
        final safeHash = parts[1];

        // 删除可能的元数据键
        await prefs.remove('file_cache_meta_${workId}_$safeHash');
        await prefs.remove('text_cache_meta_${workId}_$safeHash');
      }
    } catch (e) {
      print('[Cache] 删除元数据失败: $e');
    }
  }

  // 格式化字节大小为可读字符串
  static String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
  }

  // 获取格式化的缓存大小字符串
  static Future<String> getFormattedCacheSize() async {
    final size = await getCacheSize();
    return _formatBytes(size);
  }
}
