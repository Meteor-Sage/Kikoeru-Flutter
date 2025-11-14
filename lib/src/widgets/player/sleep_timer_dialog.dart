import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/audio_provider.dart';
import '../responsive_dialog.dart';

/// 睡眠定时器对话框
class SleepTimerDialog extends ConsumerWidget {
  const SleepTimerDialog({super.key});

  static void show(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: !Platform.isIOS,
      builder: (context) => const SleepTimerDialog(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timerState = ref.watch(sleepTimerProvider);

    return ResponsiveAlertDialog(
      title: const Text('睡眠定时器'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (timerState.isActive) ...[
              // 当前定时器状态
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.timer,
                      size: 48,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '剩余时间',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      timerState.formattedTime,
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        fontFeatures: const [
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // 快捷调整按钮
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _buildAdjustButton(
                    context,
                    ref,
                    icon: Icons.add,
                    label: '+5分钟',
                    onTap: () {
                      ref
                          .read(sleepTimerProvider.notifier)
                          .addTime(const Duration(minutes: 5));
                    },
                  ),
                  _buildAdjustButton(
                    context,
                    ref,
                    icon: Icons.add,
                    label: '+10分钟',
                    onTap: () {
                      ref
                          .read(sleepTimerProvider.notifier)
                          .addTime(const Duration(minutes: 10));
                    },
                  ),
                  _buildAdjustButton(
                    context,
                    ref,
                    icon: Icons.cancel_outlined,
                    label: '取消定时',
                    color: Theme.of(context).colorScheme.error,
                    onTap: () {
                      ref.read(sleepTimerProvider.notifier).cancelTimer();
                    },
                  ),
                ],
              ),
            ] else ...[
              // 设置新定时器
              Text(
                '选择定时时长',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              _buildTimeGrid(context, ref),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _buildTimeGrid(BuildContext context, WidgetRef ref) {
    final presetTimes = [
      (const Duration(minutes: 5), '5分钟', Icons.timer),
      (const Duration(minutes: 10), '10分钟', Icons.timer),
      (const Duration(minutes: 15), '15分钟', Icons.timer_outlined),
      (const Duration(minutes: 20), '20分钟', Icons.timer_outlined),
      (const Duration(minutes: 30), '30分钟', Icons.bedtime),
      (const Duration(minutes: 45), '45分钟', Icons.bedtime),
      (const Duration(hours: 1), '1小时', Icons.bedtime_outlined),
      (const Duration(hours: 2), '2小时', Icons.bedtime_outlined),
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.center,
      children: presetTimes.map((preset) {
        final (duration, label, icon) = preset;
        return _buildTimeCard(
          context,
          ref,
          duration: duration,
          label: label,
          icon: icon,
        );
      }).toList(),
    );
  }

  Widget _buildTimeCard(
    BuildContext context,
    WidgetRef ref, {
    required Duration duration,
    required String label,
    required IconData icon,
  }) {
    return InkWell(
      onTap: () {
        ref.read(sleepTimerProvider.notifier).setTimer(duration);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 100,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 32,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdjustButton(
    BuildContext context,
    WidgetRef ref, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(
          color: color ?? Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }
}
