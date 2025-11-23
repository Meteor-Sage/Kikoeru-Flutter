import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/player_lyric_style_provider.dart';
import '../widgets/scrollable_appbar.dart';

class PlayerLyricStyleScreen extends ConsumerWidget {
  const PlayerLyricStyleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(playerLyricSettingsProvider);
    final notifier = ref.read(playerLyricSettingsProvider.notifier);

    return Scaffold(
      appBar: const ScrollableAppBar(
        title: Text('播放器歌词样式'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSection(
            context,
            title: '迷你播放器',
            children: [
              _buildSlider(
                context,
                label: '字体大小',
                value: settings.miniFontSize,
                min: 8,
                max: 20,
                onChanged: notifier.updateMiniFontSize,
              ),
              _buildSlider(
                context,
                label: '行高',
                value: settings.miniLineHeight,
                min: 0.8,
                max: 2.0,
                divisions: 12,
                onChanged: notifier.updateMiniLineHeight,
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildSection(
            context,
            title: '竖屏播放器 (封面下方)',
            children: [
              _buildSlider(
                context,
                label: '字体大小',
                value: settings.smallFontSize,
                min: 10,
                max: 24,
                onChanged: notifier.updateSmallFontSize,
              ),
              _buildSlider(
                context,
                label: '行高',
                value: settings.smallLineHeight,
                min: 0.8,
                max: 2.0,
                divisions: 12,
                onChanged: notifier.updateSmallLineHeight,
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildSection(
            context,
            title: '全屏歌词 (竖屏/横屏)',
            children: [
              _buildSlider(
                context,
                label: '当前歌词大小',
                value: settings.fullActiveFontSize,
                min: 14,
                max: 32,
                onChanged: notifier.updateFullActiveFontSize,
              ),
              _buildSlider(
                context,
                label: '其他歌词大小',
                value: settings.fullInactiveFontSize,
                min: 12,
                max: 28,
                onChanged: notifier.updateFullInactiveFontSize,
              ),
              _buildSlider(
                context,
                label: '行高',
                value: settings.fullLineHeight,
                min: 1.0,
                max: 3.0,
                divisions: 20,
                onChanged: notifier.updateFullLineHeight,
              ),
            ],
          ),
          const SizedBox(height: 32),
          Center(
            child: TextButton.icon(
              onPressed: () => notifier.reset(),
              icon: const Icon(Icons.restore),
              label: const Text('恢复默认设置'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context,
      {required String title, required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: children),
          ),
        ),
      ],
    );
  }

  Widget _buildSlider(
    BuildContext context, {
    required String label,
    required double value,
    required double min,
    required double max,
    int? divisions,
    required Function(double) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text(value.toStringAsFixed(1)),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
