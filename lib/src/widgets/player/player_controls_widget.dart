import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../providers/audio_provider.dart';
import '../../providers/player_buttons_provider.dart';
import '../responsive_dialog.dart';
import '../volume_control.dart';
import 'sleep_timer_button.dart';
import 'sleep_timer_dialog.dart';

/// 播放器控制组件
class PlayerControlsWidget extends ConsumerStatefulWidget {
  final bool isLandscape;
  final AudioPlayerState audioState;
  final bool isPlaying;
  final AsyncValue<Duration> position;
  final AsyncValue<Duration?> duration;
  final bool isSeekingManually;
  final double seekValue;
  final ValueChanged<double> onSeekChanged;
  final ValueChanged<double> onSeekEnd;
  final Duration? seekingPosition;
  final int? workId;
  final String? currentProgress;
  final VoidCallback? onMarkPressed;
  final VoidCallback? onDetailPressed;

  const PlayerControlsWidget({
    super.key,
    required this.isLandscape,
    required this.audioState,
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.isSeekingManually,
    required this.seekValue,
    required this.onSeekChanged,
    required this.onSeekEnd,
    this.seekingPosition,
    this.workId,
    this.currentProgress,
    this.onMarkPressed,
    this.onDetailPressed,
  });

  @override
  ConsumerState<PlayerControlsWidget> createState() =>
      _PlayerControlsWidgetState();
}

class _PlayerControlsWidgetState extends ConsumerState<PlayerControlsWidget> {
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
    double localSpeed = currentSpeed;

    showDialog(
      context: context,
      barrierDismissible: !Platform.isIOS,
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

  // IconData _getProgressIcon(String? progress) {
  //   switch (progress) {
  //     case 'marked':
  //       return Icons.favorite;
  //     case 'listening':
  //       return Icons.headphones;
  //     case 'listened':
  //       return Icons.check_circle;
  //     case 'replay':
  //       return Icons.replay;
  //     case 'postponed':
  //       return Icons.schedule;
  //     default:
  //       return Icons.favorite_border;
  //   }
  // }

  // String _getProgressLabel(String? progress) {
  //   switch (progress) {
  //     case 'marked':
  //       return '想听';
  //     case 'listening':
  //       return '在听';
  //     case 'listened':
  //       return '听过';
  //     case 'replay':
  //       return '重听';
  //     case 'postponed':
  //       return '搁置';
  //     default:
  //       return '标记';
  //   }
  // }

  void _showMoreMenu(BuildContext context, WidgetRef ref) {
    final isDesktop = !Platform.isAndroid && !Platform.isIOS;
    final config = isDesktop
        ? ref.read(playerButtonsConfigDesktopProvider)
        : ref.read(playerButtonsConfigMobileProvider);
    final moreButtons = config.getMoreButtons(isDesktop);

    showModalBottomSheet(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...moreButtons.map((buttonType) {
                return _buildMenuItemForButton(
                    context, ref, buttonType, setState);
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItemForButton(
      BuildContext context, WidgetRef ref, PlayerButtonType buttonType,
      [StateSetter? setState]) {
    switch (buttonType) {
      case PlayerButtonType.seekBackward:
        return ListTile(
          leading: const Icon(Icons.replay_10),
          title: const Text('后退10秒'),
          onTap: () {
            Navigator.pop(context);
            ref
                .read(audioPlayerControllerProvider.notifier)
                .seekBackward(const Duration(seconds: 10));
          },
        );
      case PlayerButtonType.seekForward:
        return ListTile(
          leading: const Icon(Icons.forward_10),
          title: const Text('前进10秒'),
          onTap: () {
            Navigator.pop(context);
            ref
                .read(audioPlayerControllerProvider.notifier)
                .seekForward(const Duration(seconds: 10));
          },
        );
      case PlayerButtonType.sleepTimer:
        final timerState = ref.watch(sleepTimerProvider);
        return ListTile(
          leading: Icon(
            timerState.isActive ? Icons.timer : Icons.timer_outlined,
            color: timerState.isActive
                ? Theme.of(context).colorScheme.primary
                : null,
          ),
          title: const Text('定时'),
          trailing: timerState.isActive && timerState.remainingTime != null
              ? Text(
                  timerState.formattedTime,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                )
              : null,
          onTap: () {
            Navigator.pop(context);
            SleepTimerDialog.show(context);
          },
        );
      case PlayerButtonType.speed:
        return ListTile(
          leading: const Icon(Icons.speed),
          title: const Text('播放速度'),
          trailing: Text(
            '${widget.audioState.speed.toStringAsFixed(1)}x',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
          onTap: () {
            Navigator.pop(context);
            _showSpeedDialog(context, ref, widget.audioState.speed);
          },
        );
      case PlayerButtonType.repeat:
        return ListTile(
          leading: Icon(
            switch (widget.audioState.repeatMode) {
              LoopMode.off => Icons.repeat,
              LoopMode.one => Icons.repeat_one,
              LoopMode.all => Icons.repeat_on,
            },
            color: widget.audioState.repeatMode != LoopMode.off
                ? Theme.of(context).colorScheme.primary
                : null,
          ),
          title: const Text('循环模式'),
          trailing: Text(
            switch (widget.audioState.repeatMode) {
              LoopMode.off => '关闭',
              LoopMode.one => '单曲',
              LoopMode.all => '列表',
            },
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: widget.audioState.repeatMode != LoopMode.off
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
          ),
          onTap: () {
            final nextMode = switch (widget.audioState.repeatMode) {
              LoopMode.off => LoopMode.one,
              LoopMode.one => LoopMode.all,
              LoopMode.all => LoopMode.off,
            };
            ref
                .read(audioPlayerControllerProvider.notifier)
                .setRepeatMode(nextMode);
            Navigator.pop(context);
          },
        );
      case PlayerButtonType.mark:
        return ListTile(
          leading: Icon(
            widget.currentProgress != null
                ? Icons.bookmark
                : Icons.bookmark_border,
            color: widget.currentProgress != null
                ? Theme.of(context).colorScheme.primary
                : null,
          ),
          title: const Text('添加标记'),
          trailing: widget.currentProgress != null
              ? Icon(
                  Icons.check_circle,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                )
              : null,
          onTap: () {
            Navigator.pop(context);
            if (widget.onMarkPressed != null) {
              widget.onMarkPressed!();
            }
          },
        );
      case PlayerButtonType.detail:
        return ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('查看详情'),
          onTap: () {
            Navigator.pop(context);
            if (widget.onDetailPressed != null) {
              widget.onDetailPressed!();
            }
          },
        );
      case PlayerButtonType.volume:
        // 使用局部变量跟踪当前音量值以实现实时反馈
        final currentVolume = ref.read(audioPlayerControllerProvider).volume;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.volume_up),
              title: const Text('音量'),
              trailing: Text(
                '${(currentVolume * 100).round()}%',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.volume_down,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  Expanded(
                    child: Slider(
                      value: currentVolume,
                      onChanged: (value) {
                        ref
                            .read(audioPlayerControllerProvider.notifier)
                            .setVolume(value);
                        // 触发菜单重建以更新显示
                        if (setState != null) {
                          setState(() {});
                        }
                      },
                    ),
                  ),
                  Icon(
                    Icons.volume_up,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ],
        );
    }
  }

  Widget _buildButton(BuildContext context, WidgetRef ref,
      PlayerButtonType buttonType, bool isLandscape) {
    final iconSize = isLandscape ? 24.0 : null;

    switch (buttonType) {
      case PlayerButtonType.seekBackward:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () {
                ref
                    .read(audioPlayerControllerProvider.notifier)
                    .seekBackward(const Duration(seconds: 10));
              },
              icon: const Icon(Icons.replay_10),
              iconSize: iconSize,
            ),
            if (!isLandscape) const SizedBox(height: 14),
          ],
        );
      case PlayerButtonType.seekForward:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () {
                ref
                    .read(audioPlayerControllerProvider.notifier)
                    .seekForward(const Duration(seconds: 10));
              },
              icon: const Icon(Icons.forward_10),
              iconSize: iconSize,
            ),
            if (!isLandscape) const SizedBox(height: 14),
          ],
        );
      case PlayerButtonType.sleepTimer:
        return SleepTimerButton(iconSize: iconSize);
      case PlayerButtonType.volume:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            VolumeControl(
              volume: widget.audioState.volume,
              onVolumeChanged: (value) {
                ref
                    .read(audioPlayerControllerProvider.notifier)
                    .setVolume(value);
              },
              iconSize: iconSize,
            ),
            if (!isLandscape) const SizedBox(height: 14),
          ],
        );
      case PlayerButtonType.speed:
        return SizedBox(
          height: isLandscape ? 40 : 62, // 固定高度确保对齐
          child: Align(
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: () {
                    _showSpeedDialog(context, ref, widget.audioState.speed);
                  },
                  icon: Icon(
                    Icons.speed,
                    color: widget.audioState.speed != 1.0
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  iconSize: iconSize,
                  padding: isLandscape ? EdgeInsets.zero : null,
                  constraints: isLandscape
                      ? const BoxConstraints(minWidth: 36, minHeight: 36)
                      : null,
                  visualDensity: isLandscape
                      ? VisualDensity.compact
                      : VisualDensity.standard,
                ),
                if (widget.audioState.speed != 1.0)
                  Text(
                    '${widget.audioState.speed.toStringAsFixed(1)}x',
                    style: TextStyle(
                      fontSize: 9,
                      height: 1.0,
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w500,
                      fontFeatures: const [
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                if (widget.audioState.speed == 1.0)
                  SizedBox(height: isLandscape ? 4 : 14),
              ],
            ),
          ),
        );
      case PlayerButtonType.repeat:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () {
                final nextMode = switch (widget.audioState.repeatMode) {
                  LoopMode.off => LoopMode.one,
                  LoopMode.one => LoopMode.all,
                  LoopMode.all => LoopMode.off,
                };
                ref
                    .read(audioPlayerControllerProvider.notifier)
                    .setRepeatMode(nextMode);
              },
              icon: Icon(
                switch (widget.audioState.repeatMode) {
                  LoopMode.off => Icons.repeat,
                  LoopMode.one => Icons.repeat_one,
                  LoopMode.all => Icons.repeat_on,
                },
                color: widget.audioState.repeatMode != LoopMode.off
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              iconSize: iconSize,
            ),
            if (!isLandscape) const SizedBox(height: 14),
          ],
        );
      case PlayerButtonType.mark:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: widget.onMarkPressed,
              icon: Icon(
                widget.currentProgress != null
                    ? Icons.bookmark
                    : Icons.bookmark_border,
                color: widget.currentProgress != null
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              iconSize: iconSize,
            ),
            if (!isLandscape) const SizedBox(height: 14),
          ],
        );
      case PlayerButtonType.detail:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: widget.onDetailPressed,
              icon: const Icon(Icons.info_outline),
              iconSize: iconSize,
            ),
            if (!isLandscape) const SizedBox(height: 14),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final iconSize = widget.isLandscape ? 24.0 : 48.0;
    final playButtonSize = widget.isLandscape ? 64.0 : 72.0;
    final playIconSize = widget.isLandscape ? 32.0 : 36.0;

    return Column(
      children: [
        // Progress slider
        Column(
          children: [
            Consumer(
              builder: (context, ref, child) {
                final pos = widget.position.value ?? Duration.zero;
                final dur = widget.duration.value ?? Duration.zero;

                return Slider(
                  value: (widget.isSeekingManually
                          ? widget.seekValue
                          : dur.inMilliseconds > 0
                              ? pos.inMilliseconds / dur.inMilliseconds
                              : 0.0)
                      .clamp(0.0, 1.0),
                  onChanged: widget.onSeekChanged,
                  onChangeEnd: widget.onSeekEnd,
                );
              },
            ),
            // Time labels
            Consumer(
              builder: (context, ref, child) {
                final pos = widget.position.value ?? Duration.zero;
                final dur = widget.duration.value ?? Duration.zero;

                final displayPos = widget.isSeekingManually
                    ? Duration(
                        milliseconds:
                            (widget.seekValue * dur.inMilliseconds).round())
                    : pos;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDuration(displayPos),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        _formatDuration(dur),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
        SizedBox(height: widget.isLandscape ? 20 : 16),
        // Main controls
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
              iconSize: iconSize,
            ),
            Container(
              width: playButtonSize,
              height: playButtonSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.primary,
              ),
              child: IconButton(
                onPressed: () {
                  if (widget.isPlaying) {
                    ref.read(audioPlayerControllerProvider.notifier).pause();
                  } else {
                    ref.read(audioPlayerControllerProvider.notifier).play();
                  }
                },
                icon: Icon(
                  widget.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
                iconSize: playIconSize,
              ),
            ),
            IconButton(
              onPressed: () {
                ref.read(audioPlayerControllerProvider.notifier).skipToNext();
              },
              icon: const Icon(Icons.skip_next),
              iconSize: iconSize,
            ),
          ],
        ),
        SizedBox(height: widget.isLandscape ? 16 : 12),
        // Additional controls
        Consumer(
          builder: (context, ref, child) {
            final isDesktop = !Platform.isAndroid && !Platform.isIOS;
            final config = isDesktop
                ? ref.watch(playerButtonsConfigDesktopProvider)
                : ref.watch(playerButtonsConfigMobileProvider);
            final visibleButtons = config.getVisibleButtons(isDesktop);

            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ...visibleButtons
                    .map((type) =>
                        _buildButton(context, ref, type, widget.isLandscape))
                    .toList(),
                // More menu button (always visible)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () {
                        _showMoreMenu(context, ref);
                      },
                      icon: Builder(
                        builder: (context) {
                          final moreButtons = config.getMoreButtons(isDesktop);
                          final hasSpeedInMore =
                              moreButtons.contains(PlayerButtonType.speed);
                          final hasRepeatInMore =
                              moreButtons.contains(PlayerButtonType.repeat);
                          final hasSleepTimerInMore =
                              moreButtons.contains(PlayerButtonType.sleepTimer);
                          final timerState = ref.watch(sleepTimerProvider);

                          final shouldShowBadge = (hasSpeedInMore &&
                                  widget.audioState.speed != 1.0) ||
                              (hasRepeatInMore &&
                                  widget.audioState.repeatMode !=
                                      LoopMode.off) ||
                              (hasSleepTimerInMore && timerState.isActive);

                          return Badge(
                            isLabelVisible: shouldShowBadge,
                            backgroundColor:
                                Theme.of(context).colorScheme.primary,
                            child: const Icon(Icons.more_horiz),
                          );
                        },
                      ),
                      iconSize: widget.isLandscape ? 24 : null,
                    ),
                    if (!widget.isLandscape) const SizedBox(height: 14),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
