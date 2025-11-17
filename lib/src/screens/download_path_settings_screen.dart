import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/download_path_service.dart';
import '../services/download_service.dart';
import '../providers/settings_provider.dart';
import '../widgets/scrollable_appbar.dart';

class DownloadPathSettingsScreen extends ConsumerStatefulWidget {
  const DownloadPathSettingsScreen({super.key});

  @override
  ConsumerState<DownloadPathSettingsScreen> createState() =>
      _DownloadPathSettingsScreenState();
}

class _DownloadPathSettingsScreenState
    extends ConsumerState<DownloadPathSettingsScreen> {
  String? _currentPath;
  bool _isLoading = false;
  bool _isMigrating = false;

  @override
  void initState() {
    super.initState();
    _loadPaths();
  }

  Future<void> _loadPaths() async {
    setState(() => _isLoading = true);

    try {
      final current = await DownloadPathService.getDownloadDirectory();

      setState(() {
        _currentPath = current.path;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        _showSnackBar('加载路径失败: $e', isError: true);
      }
    }
  }

  Future<void> _selectCustomPath() async {
    if (!DownloadPathService.isPlatformSupported()) {
      _showSnackBar('当前平台不支持自定义下载路径', isError: true);
      return;
    }

    // 检查是否有下载任务正在进行
    if (DownloadService.instance.hasActiveDownloads) {
      final count = DownloadService.instance.activeDownloadCount;
      _showSnackBar('有 $count 个下载任务正在进行中，请先取消或完成下载后再切换路径', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final selectedPath = await DownloadPathService.pickCustomDirectory();

      if (selectedPath == null) {
        setState(() => _isLoading = false);
        return; // 用户取消选择
      }

      // 显示确认对话框
      if (mounted) {
        final confirmed = await _showMigrationConfirmDialog(selectedPath);
        if (!confirmed) {
          setState(() => _isLoading = false);
          return;
        }
      }

      // 开始迁移
      setState(() {
        _isLoading = false;
        _isMigrating = true;
      });

      final result = await DownloadPathService.setCustomPath(selectedPath);

      if (!mounted) return;
      setState(() => _isMigrating = false);

      if (result.success) {
        await _loadPaths();

        // 触发 DownloadService 重新加载
        await DownloadService.instance.reloadMetadataFromDisk();

        // 触发字幕库刷新（路径已更改）
        ref.read(subtitleLibraryRefreshTriggerProvider.notifier).state++;

        // 延迟显示成功消息
        if (mounted) {
          Future.microtask(() {
            if (mounted) {
              _showSnackBar(result.message);
            }
          });
        }
      } else {
        // 延迟显示错误消息
        if (mounted) {
          Future.microtask(() {
            if (mounted) {
              _showSnackBar(result.message, isError: true);
            }
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isMigrating = false;
      });

      // 延迟显示错误消息
      Future.microtask(() {
        if (mounted) {
          _showSnackBar('设置路径失败: $e', isError: true);
        }
      });
    }
  }

  Future<bool> _showMigrationConfirmDialog(String newPath) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认迁移下载文件'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('将把现有下载文件迁移到新目录：'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                newPath,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '此操作可能需要一些时间，具体取决于文件数量和大小。',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认迁移'),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  Future<void> _resetToDefault() async {
    // 检查是否有下载任务正在进行
    if (DownloadService.instance.hasActiveDownloads) {
      final count = DownloadService.instance.activeDownloadCount;
      _showSnackBar('有 $count 个下载任务正在进行中，请先取消或完成下载后再切换路径', isError: true);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复默认路径'),
        content: const Text('将下载路径恢复为默认位置，并迁移所有文件。\n\n是否继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isMigrating = true);

    try {
      final result = await DownloadPathService.migrateToDefaultPath();

      if (!result.success) {
        if (mounted) {
          _showSnackBar(result.message, isError: true);
        }
        return;
      }

      await _loadPaths();

      // 触发重新加载
      await DownloadService.instance.reloadMetadataFromDisk();

      // 延迟显示成功消息
      if (mounted) {
        final message = result.message.isNotEmpty ? result.message : '已恢复默认路径';
        Future.microtask(() {
          if (mounted) {
            _showSnackBar(message);
          }
        });
      }
    } catch (e) {
      // 延迟显示错误消息
      if (mounted) {
        Future.microtask(() {
          if (mounted) {
            _showSnackBar('恢复默认路径失败: $e', isError: true);
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isMigrating = false);
      }
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;

    try {
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) {
        print('[DownloadPathSettings] 无法显示 SnackBar: $message');
        return;
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
          duration: Duration(seconds: isError ? 4 : 2),
        ),
      );
    } catch (e) {
      print('[DownloadPathSettings] 无法显示 SnackBar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasCustomPath = DownloadPathService.hasCustomPath();

    return Scaffold(
      appBar: const ScrollableAppBar(
        title: Text('下载路径设置', style: TextStyle(fontSize: 18)),
      ),
      body: _isMigrating
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 24),
                  Text(
                    '正在迁移文件...',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '请勿关闭应用',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 平台提示
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            DownloadPathService.getPlatformHint(),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // 当前路径
                Text(
                  '当前下载路径',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    hasCustomPath
                                        ? Icons.folder_special
                                        : Icons.folder,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    hasCustomPath ? '自定义路径' : '默认路径',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: SelectableText(
                                  _currentPath ?? '加载中...',
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 24),

                // 操作按钮
                if (DownloadPathService.isPlatformSupported()) ...[
                  FilledButton.icon(
                    onPressed:
                        _isLoading || _isMigrating ? null : _selectCustomPath,
                    icon: const Icon(Icons.folder_open),
                    label: Text(hasCustomPath ? '更改自定义路径' : '设置自定义路径'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                  if (hasCustomPath) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed:
                          _isLoading || _isMigrating ? null : _resetToDefault,
                      icon: const Icon(Icons.restore),
                      label: const Text('恢复默认路径'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ],
                ] else ...[
                  Card(
                    color: Theme.of(context)
                        .colorScheme
                        .errorContainer
                        .withOpacity(0.3),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        '当前平台不支持自定义下载路径',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // 说明文本
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.help_outline,
                              size: 20,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '使用说明',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '• 自定义路径后，所有现有文件将自动迁移到新位置\n'
                          '• 迁移过程中请勿关闭应用\n'
                          '• 建议选择空间充足的目录\n'
                          '• 恢复默认路径时，文件也会自动迁移回去',
                          style: TextStyle(fontSize: 12, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
