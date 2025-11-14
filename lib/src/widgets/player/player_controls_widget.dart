import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../providers/audio_provider.dart';
import '../responsive_dialog.dart';
import '../volume_control.dart';
import 'sleep_timer_button.dart';

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
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Repeat mode button
            Column(
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
                  iconSize: widget.isLandscape ? 24 : null,
                ),
                if (!widget.isLandscape) const SizedBox(height: 14),
              ],
            ),
            // Speed button
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: () {
                    _showSpeedDialog(context, ref, widget.audioState.speed);
                  },
                  icon: const Icon(Icons.speed),
                  padding: EdgeInsets.zero,
                  iconSize: widget.isLandscape ? 24 : null,
                ),
                SizedBox(
                    height: widget.audioState.speed == 1.0
                        ? (widget.isLandscape ? 0 : 14)
                        : 2),
                if (widget.audioState.speed != 1.0)
                  Text(
                    '${widget.audioState.speed.toStringAsFixed(1)}x',
                    style: TextStyle(
                      fontSize: widget.isLandscape ? 9 : 10,
                      height: 1.0,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            // Seek backward 10s
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: () {
                    ref
                        .read(audioPlayerControllerProvider.notifier)
                        .seekBackward(const Duration(seconds: 10));
                  },
                  icon: const Icon(Icons.replay_10),
                  iconSize: widget.isLandscape ? 24 : null,
                ),
                if (!widget.isLandscape) const SizedBox(height: 14),
              ],
            ),
            // Seek forward 10s
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: () {
                    ref
                        .read(audioPlayerControllerProvider.notifier)
                        .seekForward(const Duration(seconds: 10));
                  },
                  icon: const Icon(Icons.forward_10),
                  iconSize: widget.isLandscape ? 24 : null,
                ),
                if (!widget.isLandscape) const SizedBox(height: 14),
              ],
            ),
            // Sleep timer button
            SleepTimerButton(
              iconSize: widget.isLandscape ? 24 : null,
            ),
            // Volume control (desktop only)
            if (!Platform.isAndroid && !Platform.isIOS)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  VolumeControl(
                    volume: widget.audioState.volume,
                    onVolumeChanged: (value) {
                      ref
                          .read(audioPlayerControllerProvider.notifier)
                          .setVolume(value);
                    },
                    iconSize: widget.isLandscape ? 24 : null,
                  ),
                  if (!widget.isLandscape) const SizedBox(height: 14),
                ],
              ),
          ],
        ),
      ],
    );
  }
}
