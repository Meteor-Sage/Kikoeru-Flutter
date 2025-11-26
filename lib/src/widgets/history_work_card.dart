import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/history_record.dart';
import '../models/audio_track.dart';
import '../providers/auth_provider.dart';
import '../providers/history_provider.dart';
import '../services/audio_player_service.dart';
import '../services/download_service.dart';
import '../services/cache_service.dart';
import '../services/kikoeru_api_service.dart' hide kikoeruApiServiceProvider;
import '../screens/work_detail_screen.dart';
import '../utils/string_utils.dart';
import '../providers/lyric_provider.dart';

class HistoryWorkCard extends ConsumerWidget {
  final HistoryRecord record;
  final VoidCallback? onTap;

  const HistoryWorkCard({
    super.key,
    required this.record,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final host = authState.host ?? '';
    final token = authState.token ?? '';
    final work = record.work;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => WorkDetailScreen(work: work),
            ),
          );
        },
        onLongPress: () {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('删除记录'),
              content: Text('确定要删除 "${work.title}" 的播放记录吗？'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () {
                    ref.read(historyProvider.notifier).remove(work.id);
                    Navigator.pop(context);
                  },
                  child: const Text('删除'),
                ),
              ],
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: work.getCoverImageUrl(host, token: token),
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: Colors.grey[200],
                      child: const Center(
                          child: Icon(Icons.image, color: Colors.grey)),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: Colors.grey[200],
                      child: const Center(
                          child: Icon(Icons.broken_image, color: Colors.grey)),
                    ),
                  ),
                  // Gradient
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
                  // Play Button
                  if (record.lastTrack != null)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Material(
                        color: Theme.of(context).colorScheme.primary,
                        shape: const CircleBorder(),
                        elevation: 4,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => _resumePlayback(context, ref),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Icon(
                              Icons.play_arrow,
                              size: 20,
                              color: Theme.of(context).colorScheme.onPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Info
            Container(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    work.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (record.lastTrack != null) ...[
                    Text(
                      record.lastTrack!.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${formatDuration(Duration(milliseconds: record.lastPositionMs))} / ${formatDuration(record.lastTrack!.duration ?? Duration.zero)}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        if (record.playlistTotal > 0)
                          Text(
                            '${record.playlistIndex + 1} / ${record.playlistTotal}',
                            style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: (record.lastTrack!.duration?.inMilliseconds ?? 1) >
                              0
                          ? (record.lastPositionMs /
                                  record.lastTrack!.duration!.inMilliseconds)
                              .clamp(0.0, 1.0)
                          : 0.0,
                      backgroundColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      color: Theme.of(context).colorScheme.primary,
                      minHeight: 3,
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ] else
                    Text(
                      '尚未播放',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _resumePlayback(BuildContext context, WidgetRef ref) async {
    final work = record.work;
    final authState = ref.read(authProvider);
    final host = authState.host ?? '';
    final token = authState.token ?? '';

    // 1. Get all files
    final apiService = ref.read(kikoeruApiServiceProvider);
    List<dynamic> allFiles = [];
    try {
      allFiles = await apiService.getWorkTracks(work.id);
      ref.read(fileListControllerProvider.notifier).updateFiles(allFiles);
    } catch (e) {
      print('Failed to update file list: $e');
    }

    if (allFiles.isEmpty) {
      // Fallback to single track if list fetch fails
      if (record.lastTrack != null) {
        await AudioPlayerService.instance.updateQueue([record.lastTrack!]);
        await AudioPlayerService.instance
            .seek(Duration(milliseconds: record.lastPositionMs));
        await AudioPlayerService.instance.play();
        ref.read(historyProvider.notifier).addOrUpdate(work);
      }
      return;
    }

    // 2. Find the directory containing the last track and get its audio files
    List<dynamic> getSiblingAudioFiles(List<dynamic> files) {
      // Helper to check if a file matches the last track
      bool isTargetFile(dynamic file) {
        if (file['type'] == 'folder') return false;
        final fileHash = file['hash'];
        final fileName = file['title'] ?? file['name'];

        if (record.lastTrack!.hash != null &&
            fileHash == record.lastTrack!.hash) {
          return true;
        }
        // Fallback to title match if hash is missing
        return fileName == record.lastTrack!.title;
      }

      // Helper to extract audio files from a list
      List<dynamic> extractAudioFiles(List<dynamic> list) {
        return list.where((file) {
          if (file['type'] == 'folder') return false;
          final name = file['title'] ?? file['name'] ?? '';
          final ext = name.split('.').last.toLowerCase();
          return ['mp3', 'wav', 'flac', 'm4a', 'aac', 'ogg'].contains(ext);
        }).toList();
      }

      // Recursive search
      for (final file in files) {
        if (file['type'] == 'folder') {
          if (file['children'] != null) {
            // Check if target is in this folder's children (direct siblings)
            final children = file['children'] as List<dynamic>;
            if (children.any(isTargetFile)) {
              return extractAudioFiles(children);
            }
            // If not found directly, recurse deeper
            final result = getSiblingAudioFiles(children);
            if (result.isNotEmpty) return result;
          }
        } else {
          // Check if target is in the root list
          if (isTargetFile(file)) {
            return extractAudioFiles(files);
          }
        }
      }

      return [];
    }

    List<dynamic> audioFiles = getSiblingAudioFiles(allFiles);

    // If we couldn't find the specific directory (e.g. file moved/renamed),
    // fallback to flattening all files to ensure playback works
    if (audioFiles.isEmpty) {
      List<dynamic> flattenAudioFiles(List<dynamic> files) {
        final List<dynamic> result = [];
        for (final file in files) {
          if (file['type'] == 'folder') {
            if (file['children'] != null) {
              result.addAll(flattenAudioFiles(file['children']));
            }
          } else {
            final name = file['title'] ?? file['name'] ?? '';
            final ext = name.split('.').last.toLowerCase();
            if (['mp3', 'wav', 'flac', 'm4a', 'aac', 'ogg'].contains(ext)) {
              result.add(file);
            }
          }
        }
        return result;
      }

      audioFiles = flattenAudioFiles(allFiles);
    }

    // 3. Build AudioTracks
    final List<AudioTrack> tracks = [];
    final downloadService = DownloadService.instance;

    // Current work cover URL
    String? coverUrl;
    if (host.isNotEmpty) {
      String normalizedUrl = host;
      if (!host.startsWith('http://') && !host.startsWith('https://')) {
        normalizedUrl = 'https://$host';
      }
      coverUrl = token.isNotEmpty
          ? '$normalizedUrl/api/cover/${work.id}?token=$token'
          : '$normalizedUrl/api/cover/${work.id}';
    }

    for (final file in audioFiles) {
      final fileHash = file['hash'];
      final fileTitle = file['title'] ?? file['name'] ?? '未知';

      // 优先级: 本地下载文件 → 缓存文件 → 网络URL
      String audioUrl = '';
      if (fileHash != null) {
        // 1. 检查是否有本地下载的文件
        final localPath = await downloadService.getDownloadedFilePath(
          work.id,
          fileHash,
        );

        if (localPath != null) {
          audioUrl = 'file://$localPath';
        } else {
          // 2. 如果没有本地文件，检查缓存
          final cachedPath = await CacheService.getCachedAudioFile(fileHash);
          if (cachedPath != null) {
            audioUrl = 'file://$cachedPath';
          }
        }
      }

      // 3. 如果缓存也没有，使用网络URL
      if (audioUrl.isEmpty) {
        if (file['mediaStreamUrl'] != null &&
            file['mediaStreamUrl'].toString().isNotEmpty) {
          audioUrl = file['mediaStreamUrl'];
        } else if (host.isNotEmpty && fileHash != null) {
          String normalizedUrl = host;
          if (!host.startsWith('http://') && !host.startsWith('https://')) {
            normalizedUrl = 'https://$host';
          }
          audioUrl = '$normalizedUrl/api/media/stream/$fileHash?token=$token';
        }
      }

      if (audioUrl.isNotEmpty) {
        final vaNames = work.vas?.map((va) => va.name).toList() ?? [];
        final artistInfo = vaNames.isNotEmpty ? vaNames.join(', ') : null;

        tracks.add(AudioTrack(
          id: fileHash ?? fileTitle,
          url: audioUrl,
          title: fileTitle,
          artist: artistInfo,
          album: work.title,
          artworkUrl: coverUrl,
          duration: file['duration'] != null
              ? Duration(milliseconds: (file['duration'] * 1000).round())
              : null,
          workId: work.id,
          hash: fileHash,
        ));
      }
    }

    if (tracks.isEmpty && record.lastTrack != null) {
      tracks.add(record.lastTrack!);
    }

    // 4. Find index
    final lastTrackId = record.lastTrack?.id;
    int index = 0;
    if (lastTrackId != null) {
      index = tracks.indexWhere((t) => t.id == lastTrackId);
      if (index == -1) {
        // Try matching by title if ID/hash mismatch
        index = tracks.indexWhere((t) => t.title == record.lastTrack!.title);
      }
      if (index == -1) index = 0;
    }

    // 5. Play
    if (tracks.isNotEmpty) {
      await AudioPlayerService.instance.updateQueue(tracks, startIndex: index);
      await AudioPlayerService.instance
          .seek(Duration(milliseconds: record.lastPositionMs));
      await AudioPlayerService.instance.play();
      ref.read(historyProvider.notifier).addOrUpdate(work);
    }
  }
}
