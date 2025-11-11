import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/audio_track.dart';
import '../models/lyric.dart';
import '../providers/audio_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/lyric_provider.dart';
import 'lyric_player_screen.dart';
import 'responsive_dialog.dart';
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

        // Build work cover URL from host/token + track.workId
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
                                        fontSize: 11,
                                        height: 1.0,
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
                                                child: CachedNetworkImage(
                                                  imageUrl: (workCoverUrl ??
                                                      track.artworkUrl)!,
                                                  fit: BoxFit.cover,
                                                  errorWidget:
                                                      (context, url, error) {
                                                    return const Icon(
                                                        Icons.album,
                                                        size: 32);
                                                  },
                                                  placeholder: (context, url) =>
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

class AudioPlayerScreen extends ConsumerStatefulWidget {
  const AudioPlayerScreen({super.key});

  @override
  ConsumerState<AudioPlayerScreen> createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends ConsumerState<AudioPlayerScreen> {
  bool _isSeekingManually = false;
  double _seekValue = 0.0;
  bool _showLyricHint = false;

  @override
  void initState() {
    super.initState();
    _checkAndShowLyricHint();
  }

  Future<void> _checkAndShowLyricHint() async {
    final prefs = await SharedPreferences.getInstance();
    final hasShown = prefs.getBool('lyric_hint_has_shown') ?? false;

    // 如果从未显示过提示
    if (!hasShown) {
      setState(() {
        _showLyricHint = true;
      });

      // 标记为已显示
      await prefs.setBool('lyric_hint_has_shown', true);

      // 8秒后隐藏提示
      Future.delayed(const Duration(seconds: 8), () {
        if (mounted) {
          setState(() {
            _showLyricHint = false;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentTrack = ref.watch(currentTrackProvider);
    final isPlaying = ref.watch(isPlayingProvider);
    final position = ref.watch(positionProvider);
    final duration = ref.watch(durationProvider);
    final audioState = ref.watch(audioPlayerControllerProvider);
    final authState = ref.watch(authProvider);
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    // 启用自动歌词加载器
    ref.watch(lyricAutoLoaderProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: IconButton(
              icon: const Icon(Icons.queue_music),
              onPressed: () {
                _showPlaylistDialog(context, ref);
              },
              tooltip: '播放列表',
            ),
          ),
        ],
        automaticallyImplyLeading: false,
      ),
      body: isLandscape
          ? _buildLandscapeLayout(
              context,
              currentTrack,
              isPlaying,
              position,
              duration,
              audioState,
              authState,
            )
          : Stack(
              children: [
                currentTrack.when(
                  data: (track) {
                    if (track == null) {
                      return const Center(
                        child: Text('没有正在播放的音频'),
                      );
                    }

                    // Build work cover URL from host/token + track.workId
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

                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 16),
                      child: Column(
                        children: [
                          // Album art (clickable to open lyrics if available)
                          Flexible(
                            child: Consumer(
                              builder: (context, ref, child) {
                                final lyricState =
                                    ref.watch(lyricControllerProvider);
                                final hasLyrics = lyricState.lyrics.isNotEmpty;

                                return GestureDetector(
                                  onTap: hasLyrics
                                      ? () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  const LyricPlayerScreen(),
                                            ),
                                          );
                                        }
                                      : null,
                                  child: Center(
                                    child: Hero(
                                      tag: 'audio_player_artwork_${track.id}',
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          maxWidth: MediaQuery.of(context)
                                                  .size
                                                  .width -
                                              48,
                                          maxHeight: MediaQuery.of(context)
                                                  .size
                                                  .height *
                                              0.4, // 最大高度为屏幕的40%
                                        ),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            color: Theme.of(context)
                                                .colorScheme
                                                .surfaceContainerHighest,
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black
                                                    .withOpacity(0.1),
                                                blurRadius: 20,
                                                offset: const Offset(0, 10),
                                              ),
                                            ],
                                          ),
                                          child: (workCoverUrl ??
                                                      track.artworkUrl) !=
                                                  null
                                              ? ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                  child: CachedNetworkImage(
                                                    imageUrl: (workCoverUrl ??
                                                        track.artworkUrl)!,
                                                    fit: BoxFit.contain,
                                                    errorWidget:
                                                        (context, url, error) {
                                                      return const Padding(
                                                        padding:
                                                            EdgeInsets.all(40),
                                                        child: Icon(
                                                          Icons.album,
                                                          size: 120,
                                                        ),
                                                      );
                                                    },
                                                    placeholder:
                                                        (context, url) {
                                                      return const Padding(
                                                        padding:
                                                            EdgeInsets.all(40),
                                                        child: Icon(
                                                          Icons.album,
                                                          size: 120,
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                )
                                              : const Padding(
                                                  padding: EdgeInsets.all(40),
                                                  child: Icon(
                                                    Icons.album,
                                                    size: 120,
                                                  ),
                                                ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Track info (clickable to open lyrics if available)
                          Consumer(
                            builder: (context, ref, child) {
                              final lyricState =
                                  ref.watch(lyricControllerProvider);
                              final hasLyrics = lyricState.lyrics.isNotEmpty;

                              return GestureDetector(
                                onTap: hasLyrics
                                    ? () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                const LyricPlayerScreen(),
                                          ),
                                        );
                                      }
                                    : null,
                                child: SingleChildScrollView(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        track.title,
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                        textAlign: TextAlign.center,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      if (track.artist != null)
                                        Text(
                                          track.artist!,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyLarge
                                              ?.copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                          textAlign: TextAlign.center,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      // 歌词显示区域（如果有歌词则显示歌词，否则显示专辑名）
                                      _LyricDisplay(albumName: track.album),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 4),
                          // Progress slider
                          Column(
                            children: [
                              Consumer(
                                builder: (context, ref, child) {
                                  final pos = position.value ?? Duration.zero;
                                  final dur = duration.value ?? Duration.zero;

                                  return Slider(
                                    value: (_isSeekingManually
                                            ? _seekValue
                                            : dur.inMilliseconds > 0
                                                ? pos.inMilliseconds /
                                                    dur.inMilliseconds
                                                : 0.0)
                                        .clamp(0.0, 1.0),
                                    onChanged: (value) {
                                      setState(() {
                                        _isSeekingManually = true;
                                        _seekValue = value;
                                      });
                                    },
                                    onChangeEnd: (value) {
                                      final newPosition = Duration(
                                        milliseconds:
                                            (value * dur.inMilliseconds)
                                                .round(),
                                      );
                                      ref
                                          .read(audioPlayerControllerProvider
                                              .notifier)
                                          .seek(newPosition);
                                      setState(() {
                                        _isSeekingManually = false;
                                      });
                                    },
                                  );
                                },
                              ),
                              // Time labels
                              Consumer(
                                builder: (context, ref, child) {
                                  final pos = position.value ?? Duration.zero;
                                  final dur = duration.value ?? Duration.zero;

                                  // Show seek position when seeking manually
                                  final displayPos = _isSeekingManually
                                      ? Duration(
                                          milliseconds:
                                              (_seekValue * dur.inMilliseconds)
                                                  .round())
                                      : pos;

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 24),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          _formatDuration(displayPos),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                        Text(
                                          _formatDuration(dur),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Main controls
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              IconButton(
                                onPressed: () {
                                  ref
                                      .read(audioPlayerControllerProvider
                                          .notifier)
                                      .skipToPrevious();
                                },
                                icon: const Icon(Icons.skip_previous),
                                iconSize: 48,
                              ),
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                child: IconButton(
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
                                  icon: Icon(
                                    isPlaying ? Icons.pause : Icons.play_arrow,
                                    color:
                                        Theme.of(context).colorScheme.onPrimary,
                                  ),
                                  iconSize: 36,
                                ),
                              ),
                              IconButton(
                                onPressed: () {
                                  ref
                                      .read(audioPlayerControllerProvider
                                          .notifier)
                                      .skipToNext();
                                },
                                icon: const Icon(Icons.skip_next),
                                iconSize: 48,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Additional controls
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              // Repeat mode button
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    onPressed: () {
                                      final nextMode =
                                          switch (audioState.repeatMode) {
                                        LoopMode.off => LoopMode.one,
                                        LoopMode.one => LoopMode.all,
                                        LoopMode.all => LoopMode.off,
                                      };
                                      ref
                                          .read(audioPlayerControllerProvider
                                              .notifier)
                                          .setRepeatMode(nextMode);
                                    },
                                    icon: Icon(
                                      switch (audioState.repeatMode) {
                                        LoopMode.off => Icons.repeat,
                                        LoopMode.one => Icons.repeat_one,
                                        LoopMode.all => Icons.repeat_on,
                                      },
                                      color:
                                          audioState.repeatMode != LoopMode.off
                                              ? Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                              : null,
                                    ),
                                  ),
                                  const SizedBox(
                                      height: 14), // Placeholder for alignment
                                ],
                              ),
                              // Speed button with current speed display
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    onPressed: () {
                                      _showSpeedDialog(
                                          context, ref, audioState.speed);
                                    },
                                    icon: const Icon(Icons.speed),
                                    padding: EdgeInsets.zero,
                                  ),
                                  SizedBox(
                                      height: audioState.speed == 1.0 ? 14 : 2),
                                  if (audioState.speed != 1.0)
                                    Text(
                                      '${audioState.speed.toStringAsFixed(1)}x',
                                      style: TextStyle(
                                        fontSize: 10,
                                        height: 1.0,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                    ),
                                ],
                              ),
                              // Seek backward 10s button
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    onPressed: () {
                                      ref
                                          .read(audioPlayerControllerProvider
                                              .notifier)
                                          .seekBackward(
                                              const Duration(seconds: 10));
                                    },
                                    icon: const Icon(Icons.replay_10),
                                  ),
                                  const SizedBox(
                                      height: 14), // Placeholder for alignment
                                ],
                              ),
                              // Seek forward 10s button
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    onPressed: () {
                                      ref
                                          .read(audioPlayerControllerProvider
                                              .notifier)
                                          .seekForward(
                                              const Duration(seconds: 10));
                                    },
                                    icon: const Icon(Icons.forward_10),
                                  ),
                                  const SizedBox(
                                      height: 14), // Placeholder for alignment
                                ],
                              ),
                              // Volume control (desktop platforms only)
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Consumer(
                                    builder: (context, ref, child) {
                                      return VolumeControl(
                                        volume: audioState.volume,
                                        onVolumeChanged: (value) {
                                          ref
                                              .read(
                                                  audioPlayerControllerProvider
                                                      .notifier)
                                              .setVolume(value);
                                        },
                                      );
                                    },
                                  ),
                                  const SizedBox(
                                      height: 14), // Placeholder for alignment
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, stack) => Center(
                    child: Text('错误: $error'),
                  ),
                ),
                // 歌词提示横幅
                if (_showLyricHint)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Consumer(
                      builder: (context, ref, child) {
                        final lyricState = ref.watch(lyricControllerProvider);
                        // 只在有歌词时显示提示
                        if (lyricState.lyrics.isEmpty) {
                          return const SizedBox.shrink();
                        }

                        return Material(
                          color: Colors.transparent,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 18,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    '点击封面或标题可以进入歌词界面',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onPrimaryContainer,
                                        ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () {
                                    setState(() {
                                      _showLyricHint = false;
                                    });
                                  },
                                  icon: Icon(
                                    Icons.close,
                                    size: 18,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onPrimaryContainer,
                                  ),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    } else {
      return '${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
  }

  void _showSpeedDialog(
      BuildContext context, WidgetRef ref, double currentSpeed) {
    // Use a local state variable to track the speed during dragging
    double localSpeed = currentSpeed;

    showDialog(
      context: context,
      builder: (context) => ResponsiveAlertDialog(
        title: const Text('播放速度'),
        content: StatefulBuilder(
          builder: (context, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Slider(
                  value: localSpeed,
                  min: 0.25,
                  max: 2.5,
                  divisions: 9,
                  label: '${localSpeed.toStringAsFixed(1)}x',
                  onChanged: (value) {
                    setState(() {
                      localSpeed = value;
                    });
                    ref
                        .read(audioPlayerControllerProvider.notifier)
                        .setSpeed(value);
                  },
                ),
                Text('${localSpeed.toStringAsFixed(1)}x'),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  // 横屏布局：左侧封面和控制，右侧歌词
  Widget _buildLandscapeLayout(
    BuildContext context,
    AsyncValue<AudioTrack?> currentTrack,
    bool isPlaying,
    AsyncValue<Duration> position,
    AsyncValue<Duration?> duration,
    AudioPlayerState audioState,
    AuthState authState,
  ) {
    return currentTrack.when(
      data: (track) {
        if (track == null) {
          return const Center(
            child: Text('没有正在播放的音频'),
          );
        }

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

        return Row(
          children: [
            // 左侧：封面和控制按钮
            Expanded(
              flex: 2,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // 封面
                      Hero(
                        tag: 'audio_player_artwork_${track.id}',
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.35,
                            maxHeight: MediaQuery.of(context).size.height * 0.6,
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: (workCoverUrl ?? track.artworkUrl) != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: CachedNetworkImage(
                                      imageUrl:
                                          (workCoverUrl ?? track.artworkUrl)!,
                                      fit: BoxFit.contain,
                                      errorWidget: (context, url, error) {
                                        return const Icon(
                                          Icons.album,
                                          size: 80,
                                        );
                                      },
                                      placeholder: (context, url) {
                                        return const Icon(
                                          Icons.album,
                                          size: 80,
                                        );
                                      },
                                    ),
                                  )
                                : const Icon(
                                    Icons.album,
                                    size: 80,
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // 标题和艺术家
                      Text(
                        track.title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (track.artist != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          track.artist!,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 16),
                      // 进度条
                      Column(
                        children: [
                          Consumer(
                            builder: (context, ref, child) {
                              final pos = position.value ?? Duration.zero;
                              final dur = duration.value ?? Duration.zero;

                              return Slider(
                                value: (_isSeekingManually
                                        ? _seekValue
                                        : dur.inMilliseconds > 0
                                            ? pos.inMilliseconds /
                                                dur.inMilliseconds
                                            : 0.0)
                                    .clamp(0.0, 1.0),
                                onChanged: (value) {
                                  setState(() {
                                    _isSeekingManually = true;
                                    _seekValue = value;
                                  });
                                },
                                onChangeEnd: (value) {
                                  final newPosition = Duration(
                                    milliseconds:
                                        (value * dur.inMilliseconds).round(),
                                  );
                                  ref
                                      .read(audioPlayerControllerProvider
                                          .notifier)
                                      .seek(newPosition);
                                  setState(() {
                                    _isSeekingManually = false;
                                  });
                                },
                              );
                            },
                          ),
                          Consumer(
                            builder: (context, ref, child) {
                              final pos = position.value ?? Duration.zero;
                              final dur = duration.value ?? Duration.zero;
                              final displayPos = _isSeekingManually
                                  ? Duration(
                                      milliseconds:
                                          (_seekValue * dur.inMilliseconds)
                                              .round())
                                  : pos;

                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _formatDuration(displayPos),
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                    Text(
                                      _formatDuration(dur),
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // 主控制按钮
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            onPressed: () {
                              ref
                                  .read(audioPlayerControllerProvider.notifier)
                                  .skipToPrevious();
                            },
                            icon: const Icon(Icons.skip_previous),
                            iconSize: 40,
                          ),
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            child: IconButton(
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
                              icon: Icon(
                                isPlaying ? Icons.pause : Icons.play_arrow,
                                color: Theme.of(context).colorScheme.onPrimary,
                              ),
                              iconSize: 32,
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              ref
                                  .read(audioPlayerControllerProvider.notifier)
                                  .skipToNext();
                            },
                            icon: const Icon(Icons.skip_next),
                            iconSize: 40,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // 附加控制按钮
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                onPressed: () {
                                  final nextMode =
                                      switch (audioState.repeatMode) {
                                    LoopMode.off => LoopMode.one,
                                    LoopMode.one => LoopMode.all,
                                    LoopMode.all => LoopMode.off,
                                  };
                                  ref
                                      .read(audioPlayerControllerProvider
                                          .notifier)
                                      .setRepeatMode(nextMode);
                                },
                                icon: Icon(
                                  switch (audioState.repeatMode) {
                                    LoopMode.off => Icons.repeat,
                                    LoopMode.one => Icons.repeat_one,
                                    LoopMode.all => Icons.repeat_on,
                                  },
                                  color: audioState.repeatMode != LoopMode.off
                                      ? Theme.of(context).colorScheme.primary
                                      : null,
                                ),
                                iconSize: 24,
                              ),
                            ],
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                onPressed: () {
                                  _showSpeedDialog(
                                      context, ref, audioState.speed);
                                },
                                icon: const Icon(Icons.speed),
                                iconSize: 24,
                              ),
                              if (audioState.speed != 1.0)
                                Text(
                                  '${audioState.speed.toStringAsFixed(1)}x',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                          IconButton(
                            onPressed: () {
                              ref
                                  .read(audioPlayerControllerProvider.notifier)
                                  .seekBackward(const Duration(seconds: 10));
                            },
                            icon: const Icon(Icons.replay_10),
                            iconSize: 24,
                          ),
                          IconButton(
                            onPressed: () {
                              ref
                                  .read(audioPlayerControllerProvider.notifier)
                                  .seekForward(const Duration(seconds: 10));
                            },
                            icon: const Icon(Icons.forward_10),
                            iconSize: 24,
                          ),
                          // 音量控制组件（非移动端）
                          Consumer(
                            builder: (context, ref, child) {
                              return VolumeControl(
                                volume: audioState.volume,
                                onVolumeChanged: (value) {
                                  ref
                                      .read(audioPlayerControllerProvider
                                          .notifier)
                                      .setVolume(value);
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
            ),
            const VerticalDivider(width: 1, thickness: 1),
            // 右侧：歌词显示
            Expanded(
              flex: 3,
              child: Consumer(
                builder: (context, ref, child) {
                  final lyricState = ref.watch(lyricControllerProvider);
                  final hasLyrics = lyricState.lyrics.isNotEmpty;

                  if (!hasLyrics) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.lyrics_outlined,
                            size: 64,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withOpacity(0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '暂无歌词',
                            style:
                                Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                          ),
                        ],
                      ),
                    );
                  }

                  return _LandscapeLyricDisplay();
                },
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(
        child: Text('错误: $error'),
      ),
    );
  }

  void _showPlaylistDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => Consumer(
        builder: (context, ref, child) {
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
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
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
                        // Use stream value if available, otherwise use current queue
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
                                child: (workCoverUrl ?? track.artworkUrl) !=
                                        null
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: CachedNetworkImage(
                                          imageUrl: (workCoverUrl ??
                                              track.artworkUrl)!,
                                          fit: BoxFit.cover,
                                          errorWidget: (context, url, error) {
                                            return const Icon(Icons.music_note,
                                                size: 24);
                                          },
                                          placeholder: (context, url) =>
                                              const Center(
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
                                            ? Theme.of(context)
                                                .colorScheme
                                                .primary
                                            : null,
                                      ),
                                    )
                                  : null,
                              trailing: isCurrentTrack
                                  ? Icon(
                                      Icons.music_note,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    )
                                  : null,
                              selected: isCurrentTrack,
                              onTap: () async {
                                // Skip to the selected track
                                await ref
                                    .read(
                                        audioPlayerControllerProvider.notifier)
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
        },
      ),
    );
  }
}

// 歌词显示组件
class _LyricDisplay extends ConsumerWidget {
  final String? albumName;

  const _LyricDisplay({this.albumName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLyric = ref.watch(currentLyricTextProvider);
    final lyricState = ref.watch(lyricControllerProvider);

    // 如果有歌词，显示歌词
    if (lyricState.lyrics.isNotEmpty) {
      return Container(
        constraints: const BoxConstraints(
          minHeight: 23,
          maxHeight: 70,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        child: Center(
          child: SingleChildScrollView(
            child: Text(
              currentLyric ?? '♪',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                    height: 1.2,
                    fontSize: 14,
                  ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      );
    }

    // 没有歌词时显示专辑名
    if (albumName != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        child: Text(
          albumName!,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

// 横屏歌词显示组件 - 显示更多上下文，可点击跳转
class _LandscapeLyricDisplay extends ConsumerStatefulWidget {
  const _LandscapeLyricDisplay();

  @override
  ConsumerState<_LandscapeLyricDisplay> createState() =>
      _LandscapeLyricDisplayState();
}

class _LandscapeLyricDisplayState
    extends ConsumerState<_LandscapeLyricDisplay> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};
  int? _currentLyricIndex;
  bool _autoScroll = true;

  @override
  void dispose() {
    _scrollController.dispose();
    _itemKeys.clear();
    super.dispose();
  }

  GlobalKey _getKeyForIndex(int index) {
    if (!_itemKeys.containsKey(index)) {
      _itemKeys[index] = GlobalKey();
    }
    return _itemKeys[index]!;
  }

  int _getCurrentLyricIndex(Duration position, List<LyricLine> lyrics) {
    for (int i = lyrics.length - 1; i >= 0; i--) {
      if (position >= lyrics[i].startTime) {
        return i;
      }
    }
    return -1;
  }

  void _scrollToLyric(int index) {
    if (!_autoScroll || !_scrollController.hasClients) return;

    final key = _getKeyForIndex(index);
    final context = key.currentContext;

    if (context != null) {
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _onLyricTap(int index) {
    final lyricState = ref.read(lyricControllerProvider);
    if (index >= 0 && index < lyricState.lyrics.length) {
      final targetTime = lyricState.lyrics[index].startTime;
      ref.read(audioPlayerControllerProvider.notifier).seek(targetTime);

      // 暂时禁用自动滚动，避免跳转时冲突
      setState(() {
        _autoScroll = false;
      });

      // 1秒后恢复自动滚动
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          setState(() {
            _autoScroll = true;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lyricState = ref.watch(lyricControllerProvider);
    final position = ref.watch(positionProvider);

    return position.when(
      data: (pos) {
        final currentIndex = _getCurrentLyricIndex(pos, lyricState.lyrics);

        // 当歌词索引变化时滚动
        if (currentIndex != _currentLyricIndex && currentIndex >= 0) {
          _currentLyricIndex = currentIndex;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToLyric(currentIndex);
          });
        }

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
          itemCount: lyricState.lyrics.length,
          itemBuilder: (context, index) {
            final lyric = lyricState.lyrics[index];
            final isActive = index == currentIndex;
            final isPast = index < currentIndex;

            return GestureDetector(
              key: _getKeyForIndex(index),
              onTap: () => _onLyricTap(index),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: isActive
                      ? Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withOpacity(0.3)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  lyric.text,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: isActive
                            ? Theme.of(context).colorScheme.primary
                            : isPast
                                ? Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant
                                    .withOpacity(0.5)
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                        fontWeight:
                            isActive ? FontWeight.bold : FontWeight.normal,
                        fontSize: isActive ? 18 : 16,
                        height: 1.5,
                      ),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('加载失败')),
    );
  }
}
