import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../services/kikoeru_api_service.dart';
import 'main_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  final bool isAddingAccount; // true when adding from account management

  const LoginScreen({
    super.key,
    this.isAddingAccount = false,
  });

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _hostController = TextEditingController();

  bool _isLogin = true; // true for login, false for register
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Set default remote host
    _hostController.text = KikoeruApiService.remoteHost
        .replaceAll('https://', '')
        .replaceAll('http://', '');
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _hostController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final host = _hostController.text.trim();

    try {
      bool success;
      if (_isLogin) {
        success = await ref
            .read(authProvider.notifier)
            .login(username, password, host);
      } else {
        success = await ref
            .read(authProvider.notifier)
            .register(username, password, host);
      }

      if (success && mounted) {
        if (widget.isAddingAccount) {
          // Adding account mode - just go back
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('账户 "$username" 已添加')),
          );
        } else {
          // Normal login - go to main screen
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const MainScreen()),
            (route) => false, // Remove all previous routes
          );
        }
      } else if (mounted) {
        final error = ref.read(authProvider).error;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error ?? (_isLogin ? '登录失败' : '注册失败')),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isLogin ? '登录失败' : '注册失败'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }

    setState(() => _isLoading = false);
  }

  void _toggleMode() {
    setState(() {
      _isLogin = !_isLogin;
    });
    ref.read(authProvider.notifier).clearError();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isAddingAccount
            ? (_isLogin ? '添加账户' : '注册账户')
            : (_isLogin ? '登录' : '注册')),
        centerTitle: true,
        // Show back button in adding account mode
        automaticallyImplyLeading: widget.isAddingAccount,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Logo/Header
                Container(
                  height: 120,
                  margin: const EdgeInsets.only(bottom: 48),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.audiotrack,
                        size: 64,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Kikoeru',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                ),

                // Username field
                TextFormField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: '用户名',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '请输入用户名';
                    }
                    if (!_isLogin && value.trim().length < 3) {
                      return '用户名至少需要3个字符';
                    }
                    return null;
                  },
                  textInputAction: TextInputAction.next,
                ),

                const SizedBox(height: 16),

                // Password field
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: '密码',
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '请输入密码';
                    }
                    if (!_isLogin && value.length < 6) {
                      return '密码至少需要6个字符';
                    }
                    return null;
                  },
                  textInputAction: TextInputAction.next,
                ),

                const SizedBox(height: 16),

                // Host field
                TextFormField(
                  controller: _hostController,
                  decoration: const InputDecoration(
                    labelText: '服务器地址',
                    prefixIcon: Icon(Icons.dns),
                    border: OutlineInputBorder(),
                    helperText: '例如: localhost:8888 或 api.example.com',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '请输入服务器地址';
                    }
                    return null;
                  },
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                ),

                const SizedBox(height: 32),

                // Submit button
                FilledButton(
                  onPressed: _isLoading ? null : _submit,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_isLogin ? '登录' : '注册'),
                ),

                const SizedBox(height: 16),

                // Toggle mode button
                TextButton(
                  onPressed: _toggleMode,
                  child: Text(
                    _isLogin ? '没有账号？点击注册' : '已有账号？点击登录',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Help text
                Text(
                  '请确保 Kikoeru 服务器正在运行并且网络连接正常',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
