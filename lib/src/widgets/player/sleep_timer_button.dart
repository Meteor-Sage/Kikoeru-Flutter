import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/audio_provider.dart';
import 'sleep_timer_dialog.dart';

/// 睡眠定时器按钮/指示器
class SleepTimerButton extends ConsumerWidget {
  final double? iconSize;

  const SleepTimerButton({
    super.key,
    this.iconSize,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timerState = ref.watch(sleepTimerProvider);

    if (timerState.isActive) {
      // 定时器激活时显示带倒计时的按钮
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: () => SleepTimerDialog.show(context),
            icon: Icon(
              Icons.timer,
              color: Theme.of(context).colorScheme.primary,
            ),
            iconSize: iconSize,
            tooltip: '睡眠定时器',
          ),
          if (timerState.remainingTime != null)
            Text(
              timerState.formattedTime,
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
        ],
      );
    } else {
      // 定时器未激活时显示普通按钮
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: () => SleepTimerDialog.show(context),
            icon: const Icon(Icons.timer_outlined),
            iconSize: iconSize,
            tooltip: '睡眠定时器',
          ),
          SizedBox(height: iconSize == null ? 14 : 0),
        ],
      );
    }
  }
}
