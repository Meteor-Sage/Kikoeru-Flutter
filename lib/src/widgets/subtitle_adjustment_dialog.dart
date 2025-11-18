import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;

import '../providers/lyric_provider.dart';
import '../providers/audio_provider.dart';
import '../services/subtitle_library_service.dart';
import '../utils/snackbar_util.dart';

/// 字幕轴调整对话框
class SubtitleAdjustmentDialog extends ConsumerStatefulWidget {
  const SubtitleAdjustmentDialog({super.key});

  @override
  ConsumerState<SubtitleAdjustmentDialog> createState() =>
      _SubtitleAdjustmentDialogState();
}

class _SubtitleAdjustmentDialogState
    extends ConsumerState<SubtitleAdjustmentDialog> {
  late TextEditingController _offsetController;
  Duration _currentOffset = Duration.zero;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _currentOffset = ref.read(lyricControllerProvider).timelineOffset;
    _offsetController = TextEditingController(
      text: _currentOffset.inMilliseconds.toString(),
    );
  }

  @override
  void dispose() {
    _offsetController.dispose();
    super.dispose();
  }

  void _updateOffset(Duration offset) {
    setState(() {
      _currentOffset = offset;
      _offsetController.text = offset.inMilliseconds.toString();
    });
    ref.read(lyricControllerProvider.notifier).adjustTimelineOffset(offset);
  }

  void _adjustByMilliseconds(int milliseconds) {
    final newOffset = _currentOffset + Duration(milliseconds: milliseconds);
    _updateOffset(newOffset);
  }

  void _resetOffset() {
    _updateOffset(Duration.zero);
  }

  Future<void> _saveToLocal() async {
    setState(() => _isSaving = true);

    try {
      final currentTrack = await ref.read(currentTrackProvider.future);
      if (currentTrack == null) {
        throw Exception('没有正在播放的音频');
      }

      // 选择保存目录
      final selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择保存目录',
      );

      if (selectedDirectory == null) {
        setState(() => _isSaving = false);
        return;
      }

      // 生成文件名
      final trackTitle = currentTrack.title;
      final audioNameWithoutExt = _removeAudioExtension(trackTitle);

      // 获取导出内容
      final lyricController = ref.read(lyricControllerProvider.notifier);
      final lrcContent = lyricController.exportLyrics(format: 'lrc');
      final vttContent = lyricController.exportLyrics(format: 'vtt');

      if (lrcContent.isEmpty && vttContent.isEmpty) {
        throw Exception('没有可保存的字幕内容');
      }

      // 保存文件 (默认LRC格式)
      final filePath = path.join(selectedDirectory, '$audioNameWithoutExt.lrc');
      final file = File(filePath);
      await file.writeAsString(lrcContent);

      if (mounted) {
        Navigator.pop(context);
        SnackBarUtil.showSuccess(context, '已保存到: $filePath',
            duration: const Duration(seconds: 3));
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtil.showError(context, '保存失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _saveToLibrary() async {
    setState(() => _isSaving = true);

    try {
      final currentTrack = await ref.read(currentTrackProvider.future);
      if (currentTrack == null) {
        throw Exception('没有正在播放的音频');
      }

      // 获取字幕库目录
      final libraryDir =
          await SubtitleLibraryService.getSubtitleLibraryDirectory();
      final savedDir = Directory('${libraryDir.path}/已保存');
      if (!await savedDir.exists()) {
        await savedDir.create(recursive: true);
      }

      // 生成文件名
      final trackTitle = currentTrack.title;
      final audioNameWithoutExt = _removeAudioExtension(trackTitle);

      // 获取导出内容
      final lyricController = ref.read(lyricControllerProvider.notifier);
      final lrcContent = lyricController.exportLyrics(format: 'lrc');

      if (lrcContent.isEmpty) {
        throw Exception('没有可保存的字幕内容');
      }

      // 保存到字幕库
      final filePath = path.join(savedDir.path, '$audioNameWithoutExt.lrc');
      final file = File(filePath);
      await file.writeAsString(lrcContent);

      if (mounted) {
        Navigator.pop(context);
        SnackBarUtil.showSuccess(context, '已保存到字幕库');
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtil.showError(context, '保存失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  String _removeAudioExtension(String fileName) {
    final audioExtensions = [
      '.mp3',
      '.m4a',
      '.wav',
      '.flac',
      '.ogg',
      '.aac',
      '.wma'
    ];
    final lowerName = fileName.toLowerCase();
    for (final ext in audioExtensions) {
      if (lowerName.endsWith(ext)) {
        return fileName.substring(0, fileName.length - ext.length);
      }
    }
    return fileName;
  }

  void _showSaveOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('保存到本地'),
              subtitle: const Text('选择目录保存文件'),
              onTap: () {
                Navigator.pop(context);
                _saveToLocal();
              },
            ),
            ListTile(
              leading: const Icon(Icons.library_books),
              title: const Text('保存到字幕库'),
              subtitle: const Text('保存到字幕库的"已保存"目录'),
              onTap: () {
                Navigator.pop(context);
                _saveToLibrary();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final offsetSeconds =
        (_currentOffset.inMilliseconds / 1000).toStringAsFixed(2);
    final isAdjusted = _currentOffset != Duration.zero;
    final mediaQuery = MediaQuery.of(context);
    final isLandscape = mediaQuery.orientation == Orientation.landscape;
    final floatingCard = _buildFloatingCard(
      context,
      colorScheme,
      offsetSeconds,
      isAdjusted,
      isLandscape,
    );

    return Stack(
      children: [
        // 点击背景关闭
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            behavior: HitTestBehavior.translucent,
            child: Container(color: Colors.transparent),
          ),
        ),
        if (isLandscape)
          Positioned(
            top: mediaQuery.padding.top + 170,
            left: 10,
            child: floatingCard,
          )
        else
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(child: floatingCard),
          ),
      ],
    );
  }

  Widget _buildFloatingCard(
    BuildContext context,
    ColorScheme colorScheme,
    String offsetSeconds,
    bool isAdjusted,
    bool isLandscape,
  ) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      color: colorScheme.surface,
      child: Container(
        width: isLandscape ? 360 : null,
        constraints: isLandscape ? null : const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 标题行
            Row(
              children: [
                Icon(
                  Icons.tune,
                  color: colorScheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '字幕轴调整',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                // 当前偏移显示
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isAdjusted
                        ? colorScheme.primaryContainer
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$offsetSeconds s',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isAdjusted
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 滑块调整
            Row(
              children: [
                Icon(
                  Icons.fast_rewind,
                  size: 10,
                  color: colorScheme.onSurfaceVariant,
                ),
                Expanded(
                  child: Slider(
                    value: _currentOffset.inMilliseconds
                        .toDouble()
                        .clamp(-5000, 5000),
                    min: -5000,
                    max: 5000,
                    divisions: 200,
                    label: '${_currentOffset.inMilliseconds}ms',
                    onChanged: (value) {
                      _updateOffset(Duration(milliseconds: value.round()));
                    },
                  ),
                ),
                Icon(
                  Icons.fast_forward,
                  size: 20,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 快速调整按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _CompactButton(
                  label: '-500',
                  onPressed: () => _adjustByMilliseconds(-500),
                ),
                const SizedBox(width: 8),
                _CompactButton(
                  label: '-100',
                  onPressed: () => _adjustByMilliseconds(-100),
                ),
                const SizedBox(width: 8),
                _CompactButton(
                  label: '+100',
                  onPressed: () => _adjustByMilliseconds(100),
                ),
                const SizedBox(width: 8),
                _CompactButton(
                  label: '+500',
                  onPressed: () => _adjustByMilliseconds(500),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 操作按钮
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isAdjusted ? _resetOffset : null,
                    icon: const Icon(Icons.restore, size: 18),
                    label: const Text('重置'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('确认'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: isAdjusted && !_isSaving ? _showSaveOptions : null,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save, size: 20),
                  tooltip: '保存到文件',
                  style: IconButton.styleFrom(
                    backgroundColor: isAdjusted && !_isSaving
                        ? Theme.of(context).colorScheme.primaryContainer
                        : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 紧凑按钮组件
class _CompactButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _CompactButton({
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        minimumSize: const Size(60, 32),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 13),
      ),
    );
  }
}
