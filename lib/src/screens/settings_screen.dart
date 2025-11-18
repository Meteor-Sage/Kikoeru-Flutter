import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';

import 'account_management_screen.dart';
import 'download_path_settings_screen.dart';
import 'theme_settings_screen.dart';
import 'ui_settings_screen.dart';
import 'preferences_screen.dart';
import 'about_screen.dart';
import 'permissions_screen.dart';
import 'privacy_mode_settings_screen.dart';
import '../providers/settings_provider.dart';
import '../providers/update_provider.dart';
import '../services/cache_service.dart';
import '../widgets/scrollable_appbar.dart';
import '../widgets/download_fab.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _cacheSize = '计算中...';
  bool _isUpdatingCacheSize = false;
  ScaffoldMessengerState? _scaffoldMessenger;

  @override
  void initState() {
    super.initState();
    // 延迟执行，确保 ref 可用
    Future.microtask(() {
      if (mounted) {
        _updateCacheSize();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 缓存 ScaffoldMessenger 以避免在 dispose 后访问
    _scaffoldMessenger = ScaffoldMessenger.of(context);
  }

  @override
  void dispose() {
    super.dispose();
  }

  // 安全显示 SnackBar 的辅助方法
  void _showSnackBar(SnackBar snackBar) {
    if (!mounted) return;
    final messenger = _scaffoldMessenger ?? ScaffoldMessenger.of(context);
    messenger.showSnackBar(snackBar);
  }

  Future<void> _updateCacheSize() async {
    if (_isUpdatingCacheSize) return;
    _isUpdatingCacheSize = true;

    if (mounted) {
      setState(() {
        _cacheSize = '计算中...';
      });
    }

    try {
      final size = await CacheService.getFormattedCacheSize();
      if (mounted) {
        setState(() {
          _cacheSize = size;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _cacheSize = '获取失败';
        });
      }
    } finally {
      _isUpdatingCacheSize = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 监听缓存刷新触发器（只在 build 中设置一次监听）
    ref.listen<int>(
      settingsCacheRefreshTriggerProvider,
      (_, __) {
        _updateCacheSize();
      },
    );

    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final cards = [
      _buildAccountCard(context),
      _buildDownloadAndCacheCard(context),
      _buildAppearanceAndAboutCard(context),
    ];

    return Scaffold(
      floatingActionButton: const DownloadFab(),
      appBar: const ScrollableAppBar(
        title: Text('设置', style: TextStyle(fontSize: 18)),
      ),
      body: isLandscape
          ? _buildLandscapeLayout(cards)
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemBuilder: (context, index) => cards[index],
              separatorBuilder: (context, index) => const SizedBox(height: 16),
              itemCount: cards.length,
            ),
    );
  }

  Widget _buildLandscapeLayout(List<Widget> cards) {
    final column1 = <Widget>[];
    final column2 = <Widget>[];

    void addToColumn(List<Widget> column, Widget card) {
      if (column.isNotEmpty) {
        column.add(const SizedBox(height: 16));
      }
      column.add(card);
    }

    for (var i = 0; i < cards.length; i++) {
      if (i.isEven) {
        addToColumn(column1, cards[i]);
      } else {
        addToColumn(column2, cards[i]);
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: column1,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: column2.isEmpty ? [const SizedBox.shrink()] : column2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountCard(BuildContext context) {
    final privacySettings = ref.watch(privacyModeSettingsProvider);

    return Card(
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.manage_accounts,
                color: Theme.of(context).colorScheme.primary),
            title: const Text('账户管理'),
            subtitle: const Text('多账户管理,切换账户'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const AccountManagementScreen(),
                ),
              );
            },
          ),
          Divider(color: Theme.of(context).colorScheme.outlineVariant),
          ListTile(
            leading: Icon(Icons.privacy_tip_outlined,
                color: Theme.of(context).colorScheme.primary),
            title: const Text('防社死模式'),
            subtitle: Text(
              privacySettings.enabled ? '已启用 - 播放信息已隐藏' : '未启用',
            ),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const PrivacyModeSettingsScreen(),
                ),
              );
            },
          ),
          // 仅在安卓平台显示权限管理
          if (Platform.isAndroid) ...[
            Divider(color: Theme.of(context).colorScheme.outlineVariant),
            ListTile(
              leading: Icon(Icons.security,
                  color: Theme.of(context).colorScheme.primary),
              title: const Text('权限管理'),
              subtitle: const Text('通知权限、后台运行权限'),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const PermissionsScreen(),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDownloadAndCacheCard(BuildContext context) {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.folder_outlined,
                color: Theme.of(context).colorScheme.primary),
            title: const Text('下载路径'),
            subtitle: const Text('自定义下载文件保存位置'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const DownloadPathSettingsScreen(),
                ),
              );
            },
          ),
          Divider(color: Theme.of(context).colorScheme.outlineVariant),
          ListTile(
            leading: Icon(Icons.storage,
                color: Theme.of(context).colorScheme.primary),
            title: const Text('缓存管理'),
            subtitle: Text('当前缓存: $_cacheSize'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
              _showCacheManagementDialog();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAppearanceAndAboutCard(BuildContext context) {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.palette,
                color: Theme.of(context).colorScheme.primary),
            title: const Text('主题设置'),
            subtitle: const Text('深色模式、主题色等'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const ThemeSettingsScreen(),
                ),
              );
            },
          ),
          Divider(color: Theme.of(context).colorScheme.outlineVariant),
          ListTile(
            leading: Icon(Icons.dashboard_customize,
                color: Theme.of(context).colorScheme.primary),
            title: const Text('界面设置'),
            subtitle: const Text('播放器、详情页、卡片界面'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const UiSettingsScreen(),
                ),
              );
            },
          ),
          Divider(color: Theme.of(context).colorScheme.outlineVariant),
          ListTile(
            leading:
                Icon(Icons.tune, color: Theme.of(context).colorScheme.primary),
            title: const Text('偏好设置'),
            subtitle: const Text('字幕库优先级、音频格式偏好'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const PreferencesScreen(),
                ),
              );
            },
          ),
          Divider(color: Theme.of(context).colorScheme.outlineVariant),
          Consumer(
            builder: (context, ref, _) {
              final showRedDot = ref.watch(showUpdateRedDotProvider);
              final hasNewVersion = ref.watch(hasNewVersionProvider);

              return ListTile(
                leading: Stack(
                  children: [
                    Icon(Icons.info_outline,
                        color: Theme.of(context).colorScheme.primary),
                    // Red dot indicator for updates (only when not notified)
                    if (showRedDot)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Theme.of(context).colorScheme.surface,
                              width: 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                title: const Text('关于'),
                subtitle: const Text('检查更新、许可证等'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasNewVersion)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Theme.of(context).colorScheme.primaryContainer,
                              Theme.of(context).colorScheme.secondaryContainer,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.new_releases,
                              size: 14,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '有新版本',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward_ios),
                  ],
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const AboutScreen(),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  // 显示缓存管理对话框
  Future<void> _showCacheManagementDialog() async {
    // 直接使用已经获取的 _cacheSize，避免重复调用
    final currentSize = await CacheService.getCacheSize();
    final formattedSize = _cacheSize; // 使用已缓存的格式化字符串
    int currentLimit = await CacheService.getCacheSizeLimit();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        // 使用独立的状态变量控制滑动条
        int tempLimit = currentLimit;

        // 非线性刻度映射函数
        // 滑动条值 0-100 映射到实际缓存大小
        // 0-50: 100MB-1000MB (每档约18MB)
        // 50-75: 1000MB-3000MB (每档约80MB)
        // 75-90: 3000MB-5000MB (每档约133MB)
        // 90-100: 5000MB-10240MB (每档约524MB)
        int sliderValueToMB(double sliderValue) {
          if (sliderValue <= 50) {
            // 100MB to 1000MB
            return 100 + ((sliderValue / 50) * 900).toInt();
          } else if (sliderValue <= 75) {
            // 1000MB to 3000MB
            return 1000 + (((sliderValue - 50) / 25) * 2000).toInt();
          } else if (sliderValue <= 90) {
            // 3000MB to 5000MB
            return 3000 + (((sliderValue - 75) / 15) * 2000).toInt();
          } else {
            // 5000MB to 10240MB
            return 5000 + (((sliderValue - 90) / 10) * 5240).toInt();
          }
        }

        // MB值反向映射到滑动条值
        double mbToSliderValue(int mb) {
          if (mb <= 1000) {
            return ((mb - 100) / 900.0) * 50;
          } else if (mb <= 3000) {
            return 50 + (((mb - 1000) / 2000.0) * 25);
          } else if (mb <= 5000) {
            return 75 + (((mb - 3000) / 2000.0) * 15);
          } else {
            return 90 + (((mb - 5000) / 5240.0) * 10);
          }
        }

        double currentSliderValue = mbToSliderValue(tempLimit);

        final isLandscape =
            MediaQuery.of(context).orientation == Orientation.landscape;

        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Row(
              children: [
                const Expanded(
                  child: Text('缓存管理', style: TextStyle(fontSize: 18)),
                ),
                if (isLandscape)
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: '关闭',
                  ),
              ],
            ),
            content: SingleChildScrollView(
              child: isLandscape
                  ? SizedBox(
                      width: MediaQuery.of(context).size.width * 0.65,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 左列：缓存信息
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 当前缓存大小
                                Card(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          '当前缓存大小',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          formattedSize,
                                          style: TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        LinearProgressIndicator(
                                          value: currentLimit > 0
                                              ? (currentSize /
                                                      (currentLimit *
                                                          1024 *
                                                          1024))
                                                  .clamp(0.0, 1.0)
                                              : 0.0,
                                          backgroundColor: Colors.grey[300],
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                            currentSize >
                                                    currentLimit * 1024 * 1024
                                                ? Colors.red
                                                : Theme.of(context)
                                                    .colorScheme
                                                    .primary,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '上限: ${currentLimit}MB',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                // 使用量详情
                                Card(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          '使用率',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              '${currentLimit > 0 ? ((currentSize / (currentLimit * 1024 * 1024)) * 100).clamp(0.0, 100.0).toStringAsFixed(1) : "0.0"}%',
                                              style: TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold,
                                                color: currentSize >
                                                        currentLimit *
                                                            1024 *
                                                            1024
                                                    ? Colors.red
                                                    : Theme.of(context)
                                                        .colorScheme
                                                        .primary,
                                              ),
                                            ),
                                            Icon(
                                              currentSize >
                                                      currentLimit * 1024 * 1024
                                                  ? Icons.warning_amber_rounded
                                                  : Icons.check_circle_outline,
                                              color: currentSize >
                                                      currentLimit * 1024 * 1024
                                                  ? Colors.red
                                                  : Colors.green,
                                              size: 28,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          const VerticalDivider(width: 1),
                          const SizedBox(width: 16),
                          // 右列：设置和说明
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 缓存大小上限设置
                                const Text(
                                  '缓存大小上限',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Column(
                                  children: [
                                    Slider(
                                      value: currentSliderValue,
                                      min: 0,
                                      max: 100,
                                      divisions: 20,
                                      label: tempLimit < 1024
                                          ? '${tempLimit}MB'
                                          : '${(tempLimit / 1024).toStringAsFixed(1)}GB',
                                      onChanged: (value) {
                                        setDialogState(() {
                                          currentSliderValue = value;
                                          tempLimit = sliderValueToMB(value);
                                        });
                                      },
                                      onChangeEnd: (value) async {
                                        final finalLimit =
                                            sliderValueToMB(value);
                                        await CacheService.setCacheSizeLimit(
                                            finalLimit);
                                        if (mounted) {
                                          setState(() {}); // 刷新主界面
                                        }
                                      },
                                    ),
                                    Text(
                                      tempLimit < 1024
                                          ? '${tempLimit}MB'
                                          : '${(tempLimit / 1024).toStringAsFixed(1)}GB',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),

                                // 说明文本
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.info_outline,
                                              size: 16, color: Colors.blue),
                                          SizedBox(width: 8),
                                          Text(
                                            '自动清理说明',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w500,
                                              color: Colors.blue,
                                            ),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: 8),
                                      Text(
                                        '• 当缓存超过上限时，会自动执行清理\n'
                                        '• 删除直到缓存降低到上限的80%\n'
                                        '• 按最近最少使用(LRU)策略删除',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 当前缓存大小
                        Card(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '当前缓存大小',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  formattedSize,
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                LinearProgressIndicator(
                                  value: currentLimit > 0
                                      ? (currentSize /
                                              (currentLimit * 1024 * 1024))
                                          .clamp(0.0, 1.0)
                                      : 0.0,
                                  backgroundColor: Colors.grey[300],
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    currentSize > currentLimit * 1024 * 1024
                                        ? Colors.red
                                        : Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '上限: ${currentLimit}MB',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // 缓存大小上限设置
                        const Text(
                          '缓存大小上限',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Column(
                          children: [
                            Slider(
                              value: currentSliderValue,
                              min: 0,
                              max: 100,
                              divisions: 20,
                              label: tempLimit < 1024
                                  ? '${tempLimit}MB'
                                  : '${(tempLimit / 1024).toStringAsFixed(1)}GB',
                              onChanged: (value) {
                                setDialogState(() {
                                  currentSliderValue = value;
                                  tempLimit = sliderValueToMB(value);
                                });
                              },
                              onChangeEnd: (value) async {
                                final finalLimit = sliderValueToMB(value);
                                await CacheService.setCacheSizeLimit(
                                    finalLimit);
                                if (mounted) {
                                  setState(() {}); // 刷新主界面
                                }
                              },
                            ),
                            Text(
                              tempLimit < 1024
                                  ? '${tempLimit}MB'
                                  : '${(tempLimit / 1024).toStringAsFixed(1)}GB',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // 说明文本
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.info_outline,
                                      size: 16, color: Colors.blue),
                                  SizedBox(width: 8),
                                  Text(
                                    '自动清理说明',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 8),
                              Text(
                                '• 当缓存超过上限时，会自动执行清理\n'
                                '• 删除直到缓存降低到上限的80%\n',
                                style: TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
            actions: [
              if (!isLandscape)
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text('关闭'),
                ),
              ElevatedButton.icon(
                onPressed: () async {
                  // 确认清除缓存
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('确认清除'),
                      content: const Text('确定要清除所有缓存吗？此操作无法撤销。'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('取消'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('确认清除'),
                        ),
                      ],
                    ),
                  );

                  if (confirmed == true && mounted) {
                    // 显示加载指示器
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (context) => const Center(
                        child: CircularProgressIndicator(),
                      ),
                    );

                    try {
                      await CacheService.clearAllCache();

                      if (mounted) {
                        Navigator.of(context).pop(); // 关闭加载指示器
                        Navigator.of(context).pop(); // 关闭缓存管理对话框
                        await _updateCacheSize(); // 更新缓存大小

                        _showSnackBar(
                          const SnackBar(
                            content: Text('缓存已清除'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        Navigator.of(context).pop(); // 关闭加载指示器
                        _showSnackBar(
                          SnackBar(
                            content: Text('清除缓存失败: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  }
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('清除缓存'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
