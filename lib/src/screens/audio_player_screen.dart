import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/work.dart';
import '../providers/audio_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/lyric_provider.dart';
import '../widgets/player/player_cover_widget.dart';
import '../widgets/player/player_controls_widget.dart';
import '../widgets/player/lyric_display_widget.dart';
import '../widgets/player/playlist_dialog.dart';
import '../widgets/work_bookmark_manager.dart';
import 'work_detail_screen.dart';

/// 音频播放器主屏幕
class AudioPlayerScreen extends ConsumerStatefulWidget {
  const AudioPlayerScreen({super.key});

  @override
  ConsumerState<AudioPlayerScreen> createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends ConsumerState<AudioPlayerScreen> {
  bool _isSeekingManually = false;
  double _seekValue = 0.0;
  bool _showLyricHint = false;
  String? _currentProgress;
  int? _currentRating;
  int? _currentWorkId;
  Duration? _seekingPosition;
  bool _showLyricView = false;

  @override
  void initState() {
    super.initState();
    _checkAndShowLyricHint();
  }

  Future<void> _checkAndShowLyricHint() async {
    final prefs = await SharedPreferences.getInstance();
    final hasShown = prefs.getBool('lyric_hint_has_shown') ?? false;

    if (!hasShown) {
      setState(() {
        _showLyricHint = true;
      });

      await prefs.setBool('lyric_hint_has_shown', true);

      Future.delayed(const Duration(seconds: 8), () {
        if (mounted) {
          setState(() {
            _showLyricHint = false;
          });
        }
      });
    }
  }

  Future<void> _loadCurrentProgress(int workId) async {
    try {
      final apiService = ref.read(kikoeruApiServiceProvider);
      final workData = await apiService.getWork(workId);
      final work = Work.fromJson(workData);

      if (mounted && _currentWorkId == workId) {
        setState(() {
          _currentProgress = work.progress;
          _currentRating = work.userRating;
        });
      }
    } catch (e) {
      debugPrint('Failed to load progress for work $workId: $e');
    }
  }

  String? _buildWorkCoverUrl(int? workId, String? artworkUrl) {
    // 优先使用 track.artworkUrl（可能是本地文件 file://）
    if (artworkUrl != null && artworkUrl.startsWith('file://')) {
      return artworkUrl;
    }

    if (workId == null) return null;

    final authState = ref.read(authProvider);
    final host = authState.host ?? '';
    final token = authState.token ?? '';

    if (host.isEmpty) return null;

    var normalizedHost = host;
    if (!normalizedHost.startsWith('http://') &&
        !normalizedHost.startsWith('https://')) {
      normalizedHost = 'https://$normalizedHost';
    }

    return token.isNotEmpty
        ? '$normalizedHost/api/cover/$workId?token=$token'
        : '$normalizedHost/api/cover/$workId';
  }

  void _handleSeekChanged(double value) {
    final dur = ref.read(durationProvider).value ?? Duration.zero;
    setState(() {
      _isSeekingManually = true;
      _seekValue = value;
      _seekingPosition = Duration(
        milliseconds: (value * dur.inMilliseconds).round(),
      );
    });
  }

  void _handleSeekEnd(double value) {
    final dur = ref.read(durationProvider).value ?? Duration.zero;
    final newPosition = Duration(
      milliseconds: (value * dur.inMilliseconds).round(),
    );

    setState(() {
      _seekingPosition = newPosition;
    });

    ref.read(audioPlayerControllerProvider.notifier).seek(newPosition);

    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        setState(() {
          _isSeekingManually = false;
          _seekingPosition = null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentTrack = ref.watch(currentTrackProvider);
    final isPlaying = ref.watch(isPlayingProvider);
    final position = ref.watch(positionProvider);
    final duration = ref.watch(durationProvider);
    final audioState = ref.watch(audioPlayerControllerProvider);
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    // 启用自动歌词加载器
    ref.watch(lyricAutoLoaderProvider);

    // 根据主题亮度设置状态栏图标颜色
    final brightness = Theme.of(context).brightness;
    final systemOverlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness:
          brightness == Brightness.light ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
    );

    return Scaffold(
      appBar: _buildAppBar(context, systemOverlayStyle, currentTrack),
      body: isLandscape
          ? _buildLandscapeLayout(
              context,
              currentTrack,
              isPlaying,
              position,
              duration,
              audioState,
            )
          : _buildPortraitLayout(
              context,
              currentTrack,
              isPlaying,
              position,
              duration,
              audioState,
            ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    SystemUiOverlayStyle systemOverlayStyle,
    AsyncValue currentTrack,
  ) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle: systemOverlayStyle,
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
            onPressed: () => PlaylistDialog.show(context),
            tooltip: '播放列表',
          ),
        ),
      ],
      automaticallyImplyLeading: false,
    );
  }

  Widget _buildPortraitLayout(
    BuildContext context,
    AsyncValue currentTrack,
    bool isPlaying,
    AsyncValue<Duration> position,
    AsyncValue<Duration?> duration,
    AudioPlayerState audioState,
  ) {
    return Stack(
      children: [
        currentTrack.when(
          data: (track) {
            if (track == null) {
              return const Center(child: Text('没有正在播放的音频'));
            }

            // 加载进度信息
            if (track.workId != null && _currentWorkId != track.workId) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() {
                    _currentWorkId = track.workId;
                    _currentProgress = null;
                  });
                  _loadCurrentProgress(track.workId!);
                }
              });
            }

            final workCoverUrl =
                _buildWorkCoverUrl(track.workId, track.artworkUrl);

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                children: [
                  if (_showLyricView)
                    Expanded(
                      child: _buildPortraitLyricView(),
                    )
                  else ...[
                    Flexible(
                      child: Consumer(
                        builder: (context, ref, child) {
                          final lyricState = ref.watch(lyricControllerProvider);
                          final hasLyrics = lyricState.lyrics.isNotEmpty;

                          return PlayerCoverWidget(
                            track: track,
                            workCoverUrl: workCoverUrl,
                            onTap: hasLyrics
                                ? () {
                                    setState(() {
                                      _showLyricView = true;
                                    });
                                  }
                                : null,
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    Consumer(
                      builder: (context, ref, child) {
                        final lyricState = ref.watch(lyricControllerProvider);
                        final hasLyrics = lyricState.lyrics.isNotEmpty;

                        return GestureDetector(
                          onTap: hasLyrics
                              ? () {
                                  setState(() {
                                    _showLyricView = true;
                                  });
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
                                LyricDisplay(albumName: track.album),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 4),
                  ],
                  PlayerControlsWidget(
                    isLandscape: false,
                    audioState: audioState,
                    isPlaying: isPlaying,
                    position: position,
                    duration: duration,
                    isSeekingManually: _isSeekingManually,
                    seekValue: _seekValue,
                    onSeekChanged: _handleSeekChanged,
                    onSeekEnd: _handleSeekEnd,
                    seekingPosition: _seekingPosition,
                    workId: track.workId,
                    currentProgress: _currentProgress,
                    onMarkPressed: track.workId != null
                        ? () => _showMarkDialog(context, track.workId!)
                        : null,
                    onDetailPressed: track.workId != null
                        ? () => _navigateToWorkDetail(context, track.workId!)
                        : null,
                  ),
                ],
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Center(child: Text('错误: $error')),
        ),
        if (_showLyricHint) _buildLyricHintBanner(),
      ],
    );
  }

  Widget _buildLandscapeLayout(
    BuildContext context,
    AsyncValue currentTrack,
    bool isPlaying,
    AsyncValue<Duration> position,
    AsyncValue<Duration?> duration,
    AudioPlayerState audioState,
  ) {
    return currentTrack.when(
      data: (track) {
        if (track == null) {
          return const Center(child: Text('没有正在播放的音频'));
        }

        // 加载进度信息
        if (track.workId != null && _currentWorkId != track.workId) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _currentWorkId = track.workId;
                _currentProgress = null;
              });
              _loadCurrentProgress(track.workId!);
            }
          });
        }

        final workCoverUrl = _buildWorkCoverUrl(track.workId, track.artworkUrl);

        return Row(
          children: [
            // 左侧：封面和控制
            Expanded(
              flex: 2,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // 计算所有固定元素的高度
                  const double padding = 32.0; // 上下padding 16 * 2
                  const double titleHeight = 60.0; // 标题预估高度（2行）
                  const double artistHeight = 20.0; // 艺术家名称高度
                  const double controlsHeight = 200.0; // 控制组件预估高度

                  // 计算封面之间和控制组件之间需要的间距
                  const double minSpacing1 = 12.0; // 封面到标题最小间距
                  const double minSpacing2 = 6.0; // 标题到艺术家最小间距
                  const double minSpacing3 = 12.0; // 艺术家到控制器最小间距
                  const double minTotalSpacing =
                      minSpacing1 + minSpacing2 + minSpacing3;

                  // 固定元素总高度
                  final fixedHeight = padding +
                      titleHeight +
                      (track.artist != null ? artistHeight : 0.0) +
                      controlsHeight +
                      minTotalSpacing;

                  // 可用于封面的高度
                  final availableForCover = constraints.maxHeight - fixedHeight;

                  // 封面最大高度限制
                  final maxCoverHeight = constraints.maxHeight * 0.6;
                  final coverHeight =
                      availableForCover.clamp(120.0, maxCoverHeight);

                  // 计算剩余可分配的空间
                  final usedHeight = padding +
                      coverHeight +
                      titleHeight +
                      (track.artist != null ? artistHeight : 0.0) +
                      controlsHeight +
                      minTotalSpacing;
                  final extraSpace = (constraints.maxHeight - usedHeight)
                      .clamp(0.0, double.infinity);

                  // 将额外空间分配到间距上
                  final spacing1 = minSpacing1 + (extraSpace * 0.4);
                  final spacing2 = minSpacing2 + (extraSpace * 0.1);
                  final spacing3 = minSpacing3 + (extraSpace * 0.5);

                  // 判断是否需要滚动
                  final needsScroll = usedHeight > constraints.maxHeight;

                  final content = Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisAlignment: needsScroll
                          ? MainAxisAlignment.start
                          : MainAxisAlignment.center,
                      children: [
                        // 封面
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: coverHeight,
                            maxWidth: constraints.maxWidth - 32,
                          ),
                          child: PlayerCoverWidget(
                            track: track,
                            workCoverUrl: workCoverUrl,
                            isLandscape: true,
                          ),
                        ),
                        SizedBox(height: spacing1),
                        // 标题
                        Text(
                          track.title,
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (track.artist != null) ...[
                          SizedBox(height: spacing2),
                          Text(
                            track.artist!,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        SizedBox(height: spacing3),
                        // 控制组件
                        PlayerControlsWidget(
                          isLandscape: true,
                          audioState: audioState,
                          isPlaying: isPlaying,
                          position: position,
                          duration: duration,
                          isSeekingManually: _isSeekingManually,
                          seekValue: _seekValue,
                          onSeekChanged: _handleSeekChanged,
                          onSeekEnd: _handleSeekEnd,
                          seekingPosition: _seekingPosition,
                          workId: track.workId,
                          currentProgress: _currentProgress,
                          onMarkPressed: track.workId != null
                              ? () => _showMarkDialog(context, track.workId!)
                              : null,
                          onDetailPressed: track.workId != null
                              ? () =>
                                  _navigateToWorkDetail(context, track.workId!)
                              : null,
                        ),
                      ],
                    ),
                  );

                  // 根据是否需要滚动返回不同的widget
                  return needsScroll
                      ? SingleChildScrollView(child: content)
                      : content;
                },
              ),
            ),
            const VerticalDivider(width: 1, thickness: 1),
            // 右侧：歌词
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

                  return FullLyricDisplay(
                    seekingPosition: _seekingPosition,
                  );
                },
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text('错误: $error')),
    );
  }

  Widget _buildPortraitLyricView() {
    return Stack(
      children: [
        FullLyricDisplay(
          seekingPosition: _seekingPosition,
          isPortrait: true,
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            onPressed: () {
              setState(() {
                _showLyricView = false;
              });
            },
            tooltip: '返回封面',
            child: const Icon(Icons.album),
          ),
        ),
      ],
    );
  }

  Widget _buildLyricHintBanner() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Consumer(
        builder: (context, ref, child) {
          final lyricState = ref.watch(lyricControllerProvider);
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
                color: Theme.of(context).colorScheme.primaryContainer,
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
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '点击封面或标题可以进入歌词界面',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
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
    );
  }

  Future<void> _showMarkDialog(BuildContext context, int workId) async {
    final manager = WorkBookmarkManager(ref: ref, context: context);

    await manager.showMarkDialog(
      workId: workId,
      currentProgress: _currentProgress,
      currentRating: _currentRating,
      onChanged: (newProgress, newRating) {
        if (mounted) {
          setState(() {
            _currentProgress = newProgress;
            _currentRating = newRating;
          });
        }
      },
    );
  }

  Future<void> _navigateToWorkDetail(BuildContext context, int workId) async {
    try {
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
        );
      }

      final apiService = ref.read(kikoeruApiServiceProvider);
      final workData = await apiService.getWork(workId);
      final work = Work.fromJson(workData);

      if (context.mounted) {
        Navigator.of(context).pop();

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => WorkDetailScreen(work: work),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载失败: $e')),
        );
      }
    }
  }
}
