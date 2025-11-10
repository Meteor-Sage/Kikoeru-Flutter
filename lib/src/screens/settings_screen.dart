import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'account_management_screen.dart';
import 'downloads_screen.dart';
import 'theme_settings_screen.dart';
import '../services/cache_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // 保持状态不被销毁

  String _cacheSize = '计算中...';

  @override
  void initState() {
    super.initState();
    _updateCacheSize();
  }

  Future<void> _updateCacheSize() async {
    final size = await CacheService.getFormattedCacheSize();
    if (mounted) {
      setState(() {
        _cacheSize = size;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // 必须调用以保持状态
    _updateCacheSize(); // 每次 build 时更新缓存大小
    return Scaffold(
      appBar: AppBar(title: const Text('设置', style: TextStyle(fontSize: 18))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Account Management section
          Card(
            child: ListTile(
              leading: const Icon(Icons.manage_accounts),
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
          ),

          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.download),
                  title: const Text('下载管理'),
                  subtitle: const Text('查看和管理下载任务'),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const DownloadsScreen(),
                      ),
                    );
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.storage),
                  title: const Text('缓存管理', style: TextStyle(fontSize: 18)),
                  subtitle: Text('当前缓存: $_cacheSize'),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () {
                    _showCacheManagementDialog();
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.palette),
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
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.language),
                  title: const Text('语言设置'),
                  subtitle: const Text('界面语言'),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () {
                    // TODO: Navigate to language settings
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('关于'),
                  subtitle: const Text('版本信息、许可证等'),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () {
                    // TODO: Navigate to about page
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 显示缓存管理对话框
  Future<void> _showCacheManagementDialog() async {
    final currentSize = await CacheService.getCacheSize();
    final formattedSize = await CacheService.getFormattedCacheSize();
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

        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('缓存管理'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 当前缓存大小
                  Card(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
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
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: currentLimit > 0
                                ? (currentSize / (currentLimit * 1024 * 1024))
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
                          await CacheService.setCacheSizeLimit(finalLimit);
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

                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('缓存已清除'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        Navigator.of(context).pop(); // 关闭加载指示器
                        ScaffoldMessenger.of(context).showSnackBar(
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
