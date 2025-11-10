import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  static final Uri _repoUri =
      Uri.parse('https://github.com/Meteor-Sage/Kikoeru-Flutter');
  late final Future<_AboutData> _aboutFuture;

  @override
  void initState() {
    super.initState();
    _aboutFuture = _loadAboutData();
  }

  Future<_AboutData> _loadAboutData() async {
    var version = '未知';
    var buildNumber = '';
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version;
      buildNumber = info.buildNumber;
    } catch (error, stackTrace) {
      debugPrint('AboutScreen: failed to load app version: $error');
      debugPrint(stackTrace.toString());
    }

    var licenseText = '未能加载 LICENSE 文件';
    try {
      final raw = await rootBundle.loadString('LICENSE');
      licenseText = raw.trim().isEmpty ? 'LICENSE 内容为空' : raw.trim();
    } catch (error, stackTrace) {
      debugPrint('AboutScreen: failed to load license: $error');
      debugPrint(stackTrace.toString());
    }

    return _AboutData(
      version: version,
      buildNumber: buildNumber,
      license: licenseText,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: FutureBuilder<_AboutData>(
        future: _aboutFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.sentiment_dissatisfied, size: 48),
                    const SizedBox(height: 12),
                    const Text('无法加载关于信息'),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _aboutFuture = _loadAboutData();
                        });
                      },
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            );
          }

          final data = snapshot.data!;
          final versionLabel = data.buildNumber.isNotEmpty
              ? '${data.version} (${data.buildNumber})'
              : data.version;

          final primaryColor = Theme.of(context).colorScheme.primary;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: Icon(Icons.verified, color: primaryColor),
                  title: const Text('版本信息'),
                  subtitle: Text('当前版本：$versionLabel'),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: Icon(Icons.person_outline, color: primaryColor),
                  title: const Text('作者'),
                  subtitle: const Text('Meteor-Sage'),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: Icon(Icons.link, color: primaryColor),
                  title: const Text('项目仓库'),
                  subtitle: Text(_repoUri.toString()),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _openRepository(),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: Icon(Icons.gavel_outlined, color: primaryColor),
                  title: const Text('开源协议'),
                  subtitle: const Text('LICENSE'),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () => _showLicenseDialog(data.license),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openRepository() async {
    try {
      final launched = await launchUrl(
        _repoUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法打开仓库链接')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('打开链接失败：$error')),
      );
    }
  }

  void _showLicenseDialog(String license) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('开源协议'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(license),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }
}

class _AboutData {
  final String version;
  final String buildNumber;
  final String license;

  const _AboutData({
    required this.version,
    required this.buildNumber,
    required this.license,
  });
}
