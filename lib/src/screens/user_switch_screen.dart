import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../widgets/responsive_dialog.dart';
import 'main_screen.dart';
import 'login_screen.dart';

class UserSwitchScreen extends ConsumerStatefulWidget {
  const UserSwitchScreen({super.key});

  @override
  ConsumerState<UserSwitchScreen> createState() => _UserSwitchScreenState();
}

class _UserSwitchScreenState extends ConsumerState<UserSwitchScreen> {
  List<User> _savedUsers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSavedUsers();
  }

  Future<void> _loadSavedUsers() async {
    setState(() => _isLoading = true);
    try {
      final users = await ref.read(authProvider.notifier).getSavedUsers();
      setState(() {
        _savedUsers = users;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _switchUser(User user) async {
    await ref.read(authProvider.notifier).switchUser(user);
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const MainScreen()),
      );
    }
  }

  Future<void> _deleteUser(User user) async {
    await ref.read(authProvider.notifier).removeUser(user);
    await _loadSavedUsers();
  }

  void _showDeleteConfirmation(User user) {
    showDialog(
      context: context,
      builder: (context) => ResponsiveAlertDialog(
        title: const Text('删除账户'),
        content: Text('确定要删除账户 "${user.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteUser(user);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: const Text('选择账户'),
            backgroundColor: Theme.of(context).colorScheme.surface,
            actions: [
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: () {
                  Navigator.of(context)
                      .push(
                        MaterialPageRoute(
                          builder: (context) => const LoginScreen(),
                        ),
                      )
                      .then((_) => _loadSavedUsers());
                },
              ),
            ],
          ),
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_savedUsers.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.person_add,
                      size: 80,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '没有保存的账户',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '请添加一个新账户开始使用',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context)
                            .push(
                              MaterialPageRoute(
                                builder: (context) => const LoginScreen(),
                              ),
                            )
                            .then((_) => _loadSavedUsers());
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('添加账户'),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final user = _savedUsers[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: CircleAvatar(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        child: Text(
                          user.name.isNotEmpty
                              ? user.name[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(
                        user.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(
                            user.host ?? '未知主机',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '最后使用: ${user.lastUpdateTime != null ? _formatDateTime(user.lastUpdateTime!) : '未知'}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                          ),
                        ],
                      ),
                      trailing: PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert),
                        onSelected: (value) {
                          if (value == 'delete') {
                            _showDeleteConfirmation(user);
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'delete',
                            child: ListTile(
                              leading: Icon(Icons.delete),
                              title: Text('删除账户'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ),
                      onTap: () => _switchUser(user),
                    ),
                  );
                }, childCount: _savedUsers.length),
              ),
            ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays}天前';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}小时前';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}分钟前';
    } else {
      return '刚刚';
    }
  }
}
