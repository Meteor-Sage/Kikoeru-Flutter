import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../providers/audio_provider.dart';
import '../../providers/auth_provider.dart';

/// 播放列表对话框
class PlaylistDialog extends ConsumerWidget {
  const PlaylistDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueAsync = ref.watch(queueProvider);
    final currentTrack = ref.watch(currentTrackProvider);
    final authState = ref.watch(authProvider);

    // Get current queue synchronously as fallback
    final audioService = ref.read(audioPlayerServiceProvider);
    final currentQueue = audioService.queue;

    return Dialog(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
          maxWidth: MediaQuery.of(context).size.width * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '播放列表',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Playlist
            Flexible(
              child: Builder(
                builder: (context) {
                  final tracks = queueAsync.valueOrNull ?? currentQueue;

                  if (tracks.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('播放列表为空'),
                      ),
                    );
                  }

                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: tracks.length,
                    itemBuilder: (context, index) {
                      final track = tracks[index];
                      final isCurrentTrack =
                          currentTrack.valueOrNull?.id == track.id;

                      // Build work cover URL
                      String? workCoverUrl;
                      final host = authState.host ?? '';
                      final token = authState.token ?? '';
                      if (track.workId != null && host.isNotEmpty) {
                        var normalizedHost = host;
                        if (!normalizedHost.startsWith('http://') &&
                            !normalizedHost.startsWith('https://')) {
                          normalizedHost = 'https://$normalizedHost';
                        }
                        workCoverUrl = token.isNotEmpty
                            ? '$normalizedHost/api/cover/${track.workId}?token=$token'
                            : '$normalizedHost/api/cover/${track.workId}';
                      }

                      return ListTile(
                        leading: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                          ),
                          child: (workCoverUrl ?? track.artworkUrl) != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: CachedNetworkImage(
                                    imageUrl:
                                        (workCoverUrl ?? track.artworkUrl)!,
                                    fit: BoxFit.cover,
                                    errorWidget: (context, url, error) {
                                      return const Icon(Icons.music_note,
                                          size: 24);
                                    },
                                    placeholder: (context, url) => const Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  ),
                                )
                              : const Icon(Icons.music_note, size: 24),
                        ),
                        title: Text(
                          track.title,
                          style: TextStyle(
                            fontWeight: isCurrentTrack
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isCurrentTrack
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: track.artist != null
                            ? Text(
                                track.artist!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isCurrentTrack
                                      ? Theme.of(context).colorScheme.primary
                                      : null,
                                ),
                              )
                            : null,
                        trailing: isCurrentTrack
                            ? Icon(
                                Icons.music_note,
                                color: Theme.of(context).colorScheme.primary,
                              )
                            : null,
                        selected: isCurrentTrack,
                        onTap: () async {
                          await ref
                              .read(audioPlayerControllerProvider.notifier)
                              .skipToIndex(index);
                          if (context.mounted) {
                            Navigator.of(context).pop();
                          }
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 显示播放列表对话框
  static void show(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: !Platform.isIOS,
      builder: (context) => const PlaylistDialog(),
    );
  }
}
