import 'package:flutter/material.dart';
import '../services/download_service.dart';
import '../models/download_task.dart';
import '../screens/downloads_screen.dart';

/// 下载任务浮动按钮
/// 只在有活跃下载任务时显示
class DownloadFab extends StatelessWidget {
  const DownloadFab({super.key});

  void _navigateToDownloads(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const DownloadsScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DownloadTask>>(
      stream: DownloadService.instance.tasksStream,
      builder: (context, snapshot) {
        final activeCount = DownloadService.instance.activeDownloadCount;

        // 没有活跃任务时不显示
        if (activeCount == 0) {
          return const SizedBox.shrink();
        }

        return Badge(
          isLabelVisible: true,
          label: Text('$activeCount'),
          child: FloatingActionButton(
            onPressed: () => _navigateToDownloads(context),
            tooltip: '下载任务',
            child: const Icon(Icons.download),
          ),
        );
      },
    );
  }
}
