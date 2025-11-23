import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../providers/audio_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/lyric_provider.dart';
import '../providers/player_lyric_style_provider.dart';
import '../screens/audio_player_screen.dart';
import 'volume_control.dart';

class MiniPlayer extends ConsumerStatefulWidget {
  const MiniPlayer({super.key});

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer> {
  bool _isDragging = false;
  double _dragValue = 0.0;
  String? _lastTrackId;
  bool _isAdjustingVolume = false;
  double _tempVolume = 1.0;

  @override
  Widget build(BuildContext context) {
    final currentTrack = ref.watch(currentTrackProvider);
    final isPlaying = ref.watch(isPlayingProvider);
    final position = ref.watch(positionProvider);
    final duration = ref.watch(durationProvider);
    final authState = ref.watch(authProvider);
    final isMiniPlayerVisible = ref.watch(miniPlayerVisibilityProvider);

    // 启用自动歌词加载器
    ref.watch(lyricAutoLoaderProvider);

    return currentTrack.when(
      data: (track) {
        // 当播放新音轨时（并且不是因为重建导致的检查），重新显示MiniPlayer
        if (track != null && _lastTrackId != null && track.id != _lastTrackId) {
          _lastTrackId = track.id;
          // 使用addPostFrameCallback确保在build完成后再更新状态
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ref.read(miniPlayerVisibilityProvider.notifier).show();
            }
          });
        } else if (track != null && _lastTrackId == null) {
          // 首次加载或删除后，记录当前音轨但不改变可见性
          _lastTrackId = track.id;
        }

        if (track == null || !isMiniPlayerVisible) {
          return const SizedBox.shrink();
        }

        final progress = position.when(
          data: (pos) => duration.when(
            data: (dur) => dur != null && dur.inMilliseconds > 0
                ? pos.inMilliseconds / dur.inMilliseconds
                : 0.0,
            loading: () => 0.0,
            error: (_, __) => 0.0,
          ),
          loading: () => 0.0,
          error: (_, __) => 0.0,
        );

        final displayProgress = _isDragging ? _dragValue : progress;

        // Build work cover URL（优先使用本地文件）
        String? workCoverUrl;
        // 优先使用 track.artworkUrl（可能是本地文件 file://）
        if (track.artworkUrl != null &&
            track.artworkUrl!.startsWith('file://')) {
          workCoverUrl = track.artworkUrl;
        } else if (track.workId != null) {
          final host = authState.host ?? '';
          final token = authState.token ?? '';
          if (host.isNotEmpty) {
            var normalizedHost = host;
            if (!normalizedHost.startsWith('http://') &&
                !normalizedHost.startsWith('https://')) {
              normalizedHost = 'https://$normalizedHost';
            }
            workCoverUrl = token.isNotEmpty
                ? '$normalizedHost/api/cover/${track.workId}?token=$token'
                : '$normalizedHost/api/cover/${track.workId}';
          }
        }

        return Dismissible(
          key: Key('miniplayer_${track.id}'),
          direction: DismissDirection.down,
          background: Container(color: Colors.transparent),
          onDismissed: (direction) {
            // Stop playback and hide the MiniPlayer
            ref.read(audioPlayerControllerProvider.notifier).stop();
            ref.read(miniPlayerVisibilityProvider.notifier).hide();
            // Reset track ID to allow re-showing when a new track is played
            _lastTrackId = null;
          },
          child: Consumer(
            builder: (context, ref, child) {
              final currentLyric = ref.watch(currentLyricTextProvider);
              final lyricState = ref.watch(lyricControllerProvider);
              final hasLyrics = lyricState.lyrics.isNotEmpty;
              final shouldShowLyric =
                  isPlaying && hasLyrics && currentLyric != null;

              return Container(
                height: shouldShowLyric ? 88 : 72,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border(
                    top: BorderSide(
                      color: Theme.of(context)
                          .colorScheme
                          .outline
                          .withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    // Lyric display and progress bar wrapped in gesture detector
                    GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragStart: (details) {
                        setState(() {
                          _isDragging = true;
                        });
                      },
                      onHorizontalDragUpdate: (details) {
                        final box = context.findRenderObject() as RenderBox?;
                        if (box != null) {
                          final localPosition = details.localPosition.dx;
                          final width = box.size.width;
                          final value = (localPosition / width).clamp(0.0, 1.0);
                          setState(() {
                            _dragValue = value;
                          });
                        }
                      },
                      onHorizontalDragEnd: (details) {
                        final dur = duration.valueOrNull;
                        if (dur != null) {
                          final seekPosition = Duration(
                            milliseconds:
                                (_dragValue * dur.inMilliseconds).round(),
                          );
                          ref
                              .read(audioPlayerControllerProvider.notifier)
                              .seek(seekPosition);
                        }
                        setState(() {
                          _isDragging = false;
                        });
                      },
                      onTapUp: (details) {
                        final box = context.findRenderObject() as RenderBox?;
                        if (box != null) {
                          final localPosition = details.localPosition.dx;
                          final width = box.size.width;
                          final value = (localPosition / width).clamp(0.0, 1.0);
                          final dur = duration.valueOrNull;
                          if (dur != null) {
                            final seekPosition = Duration(
                              milliseconds:
                                  (value * dur.inMilliseconds).round(),
                            );
                            ref
                                .read(audioPlayerControllerProvider.notifier)
                                .seek(seekPosition);
                          }
                        }
                      },
                      child: Column(
                        children: [
                          // Lyric display (only show when playing and has lyrics)
                          Consumer(
                            builder: (context, ref, child) {
                              final currentLyric =
                                  ref.watch(currentLyricTextProvider);
                              final lyricState =
                                  ref.watch(lyricControllerProvider);
                              final lyricSettings =
                                  ref.watch(playerLyricSettingsProvider);
                              final hasLyrics = lyricState.lyrics.isNotEmpty;

                              // Only show when playing and has lyrics
                              if (!isPlaying ||
                                  !hasLyrics ||
                                  currentLyric == null) {
                                return const SizedBox.shrink();
                              }

                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 2,
                                ),
                                child: Text(
                                  currentLyric,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        fontSize: lyricSettings.miniFontSize,
                                        height: lyricSettings.miniLineHeight,
                                        fontWeight: FontWeight.w600,
                                      ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                ),
                              );
                            },
                          ),
                          // Draggable Progress bar
                          SizedBox(
                            height: 4,
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 4,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 0,
                                  disabledThumbRadius: 0,
                                ),
                                overlayShape: SliderComponentShape.noOverlay,
                                activeTrackColor:
                                    Theme.of(context).colorScheme.primary,
                                inactiveTrackColor: Theme.of(context)
                                    .colorScheme
                                    .outline
                                    .withOpacity(0.2),
                              ),
                              child: Slider(
                                value: displayProgress.clamp(0.0, 1.0),
                                onChanged: (value) {
                                  setState(() {
                                    _isDragging = true;
                                    _dragValue = value;
                                  });
                                },
                                onChangeEnd: (value) {
                                  final dur = duration.valueOrNull;
                                  if (dur != null) {
                                    final seekPosition = Duration(
                                      milliseconds:
                                          (value * dur.inMilliseconds).round(),
                                    );
                                    ref
                                        .read(audioPlayerControllerProvider
                                            .notifier)
                                        .seek(seekPosition);
                                  }
                                  setState(() {
                                    _isDragging = false;
                                  });
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Player controls
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Row(
                          children: [
                            // Left tap area: artwork + info opens full player
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  Navigator.of(context).push(
                                    PageRouteBuilder(
                                      pageBuilder: (context, animation,
                                              secondaryAnimation) =>
                                          const AudioPlayerScreen(),
                                      transitionDuration:
                                          const Duration(milliseconds: 400),
                                      reverseTransitionDuration:
                                          const Duration(milliseconds: 400),
                                      transitionsBuilder: (context, animation,
                                          secondaryAnimation, child) {
                                        // 前进动画：使用渐变和缩放效果，配合 Hero 动画
                                        // 返回动画：只保留 Hero 动画，其他元素立即消失
                                        return AnimatedBuilder(
                                          animation: animation,
                                          builder: (context, child) {
                                            // 检测动画方向：reverse 表示返回
                                            if (animation.status ==
                                                    AnimationStatus.reverse ||
                                                animation.status ==
                                                    AnimationStatus.dismissed) {
                                              // 返回时：完全透明（让非 Hero 元素不可见），但仍然渲染 child 以保留 Hero 动画
                                              return Opacity(
                                                opacity: 0.0,
                                                child: child,
                                              );
                                            }

                                            // 前进时使用缩放和淡入动画
                                            const begin = 0.0;
                                            const end = 1.0;
                                            const curve = Curves.easeOutCubic;

                                            final scale = Tween<double>(
                                              begin: begin,
                                              end: end,
                                            )
                                                .chain(CurveTween(curve: curve))
                                                .evaluate(animation);

                                            final opacity =
                                                CurveTween(curve: Curves.easeIn)
                                                    .evaluate(animation);

                                            return Transform.scale(
                                              scale: scale,
                                              alignment: Alignment.bottomLeft,
                                              child: Opacity(
                                                opacity: opacity,
                                                child: child,
                                              ),
                                            );
                                          },
                                          child: child,
                                        );
                                      },
                                    ),
                                  );
                                },
                                child: Row(
                                  children: [
                                    // Album art (use work cover) with Hero animation
                                    Hero(
                                      tag: 'audio_player_artwork_${track.id}',
                                      child: Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          color: Theme.of(context)
                                              .colorScheme
                                              .surfaceContainerHighest,
                                        ),
                                        child: (workCoverUrl ??
                                                    track.artworkUrl) !=
                                                null
                                            ? ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                child: (workCoverUrl ??
                                                                track
                                                                    .artworkUrl)
                                                            ?.startsWith(
                                                                'file://') ??
                                                        false
                                                    ? Image.file(
                                                        File((workCoverUrl ??
                                                                track
                                                                    .artworkUrl)!
                                                            .replaceFirst(
                                                                'file://', '')),
                                                        fit: BoxFit.cover,
                                                        errorBuilder: (context,
                                                            error, stackTrace) {
                                                          return const Icon(
                                                              Icons.album,
                                                              size: 32);
                                                        },
                                                      )
                                                    : CachedNetworkImage(
                                                        imageUrl: (workCoverUrl ??
                                                            track.artworkUrl)!,
                                                        // 使用workId作为cacheKey，与作品详情页保持一致
                                                        cacheKey: track
                                                                    .workId !=
                                                                null
                                                            ? 'work_cover_${track.workId}'
                                                            : null,
                                                        fit: BoxFit.cover,
                                                        errorWidget: (context,
                                                            url, error) {
                                                          return const Icon(
                                                              Icons.album,
                                                              size: 32);
                                                        },
                                                        placeholder:
                                                            (context, url) =>
                                                                const Center(
                                                          child:
                                                              CircularProgressIndicator(),
                                                        ),
                                                      ),
                                              )
                                            : const Icon(
                                                Icons.album,
                                                size: 32,
                                              ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    // Track info
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            track.title,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w500,
                                                ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (track.artist != null) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              track.artist!,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // Controls (do not trigger navigation)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  onPressed: () async {
                                    try {
                                      await ref
                                          .read(audioPlayerControllerProvider
                                              .notifier)
                                          .skipToPrevious();
                                    } catch (e) {
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(e
                                              .toString()
                                              .replaceAll('Exception: ', '')),
                                          duration: const Duration(seconds: 1),
                                        ),
                                      );
                                    }
                                  },
                                  icon: const Icon(Icons.skip_previous),
                                  iconSize: 24,
                                ),
                                IconButton(
                                  onPressed: () {
                                    if (isPlaying) {
                                      ref
                                          .read(audioPlayerControllerProvider
                                              .notifier)
                                          .pause();
                                    } else {
                                      ref
                                          .read(audioPlayerControllerProvider
                                              .notifier)
                                          .play();
                                    }
                                  },
                                  icon: Icon(isPlaying
                                      ? Icons.pause
                                      : Icons.play_arrow),
                                  iconSize: 28,
                                ),
                                IconButton(
                                  onPressed: () async {
                                    try {
                                      await ref
                                          .read(audioPlayerControllerProvider
                                              .notifier)
                                          .skipToNext();
                                    } catch (e) {
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(e
                                              .toString()
                                              .replaceAll('Exception: ', '')),
                                          duration: const Duration(seconds: 1),
                                        ),
                                      );
                                    }
                                  },
                                  icon: const Icon(Icons.skip_next),
                                  iconSize: 24,
                                ),
                                // Volume control (desktop platforms only)
                                Consumer(
                                  builder: (context, ref, child) {
                                    final audioState = ref
                                        .watch(audioPlayerControllerProvider);
                                    // 使用临时音量值避免拖动时重建
                                    final displayVolume = _isAdjustingVolume
                                        ? _tempVolume
                                        : audioState.volume;
                                    return VolumeControl(
                                      volume: displayVolume,
                                      onVolumeChanged: (value) {
                                        setState(() {
                                          _isAdjustingVolume = true;
                                          _tempVolume = value;
                                        });
                                        ref
                                            .read(audioPlayerControllerProvider
                                                .notifier)
                                            .setVolume(value);
                                      },
                                      onVolumeChangeEnd: () {
                                        setState(() {
                                          _isAdjustingVolume = false;
                                        });
                                      },
                                      iconSize: 24,
                                    );
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (error, stack) => const SizedBox.shrink(),
    );
  }
}
