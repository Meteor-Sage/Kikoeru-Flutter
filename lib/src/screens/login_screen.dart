import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../services/kikoeru_api_service.dart';
import '../widgets/scrollable_appbar.dart';
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

enum _LatencyState { idle, testing, success, failure }

class _LatencyResult {
  const _LatencyResult(
    this.state, {
    this.latencyMs,
    this.statusCode,
    this.error,
  });

  final _LatencyState state;
  final int? latencyMs;
  final int? statusCode;
  final String? error;
}

String _normalizedHostString(String host) {
  var value = host.trim();
  if (value.isEmpty) {
    return '';
  }

  if (value.startsWith('http://')) {
    value = value.substring(7);
  } else if (value.startsWith('https://')) {
    value = value.substring(8);
  }

  while (value.endsWith('/')) {
    value = value.substring(0, value.length - 1);
  }

  return value;
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLogin = true; // true for login, false for register
  bool _obscurePassword = true;
  bool _isLoading = false;
  late final List<String> _hostOptions;
  String _hostValue = '';
  final Map<String, _LatencyResult> _latencyResults = {};

  @override
  void initState() {
    super.initState();
    _initializeHostOptions();

    final defaultHost = _normalizedHostString(KikoeruApiService.remoteHost);
    _hostValue = defaultHost;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final host = _hostValue.trim();

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

  void _initializeHostOptions() {
    final options = <String>[];

    void addOption(String host) {
      final normalized = _normalizedHostString(host);
      if (normalized.isEmpty) {
        return;
      }
      if (!options.contains(normalized)) {
        options.add(normalized);
      }
    }

    const preferredHosts = [
      'api.asmr-200.com',
      'api.asmr.one',
      'api.asmr-100.com',
      'api.asmr-300.com',
    ];

    for (final host in preferredHosts) {
      addOption(host);
    }

    final defaultHost = _normalizedHostString(KikoeruApiService.remoteHost);
    if (defaultHost.isNotEmpty) {
      options.remove(defaultHost);
      options.insert(0, defaultHost);
    }

    _hostOptions = options;
  }

  Widget _buildHostLatencyActions(BuildContext context) {
    final normalized = _normalizedHostString(_hostValue);
    final result = normalized.isEmpty ? null : _latencyResults[normalized];
    final isTesting = result?.state == _LatencyState.testing;
    final statusText = normalized.isEmpty
        ? '请输入服务器地址后测试连接'
        : _describeLatencyResult(result, includePlaceholder: true);
    final color = normalized.isEmpty
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : _latencyColorForResult(context, result);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        TextButton.icon(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            minimumSize: const Size(0, 36),
          ),
          onPressed: normalized.isEmpty || isTesting
              ? null
              : () => _testLatencyForHost(_hostValue),
          icon: isTesting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.network_ping_outlined),
          label: Text(isTesting ? '测试中...' : '测试连接'),
        ),
        const SizedBox(height: 4),
        Text(
          statusText,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
          textAlign: TextAlign.right,
        ),
      ],
    );
  }

  Future<void> _testLatencyForHost(String host) async {
    final normalized = _normalizedHostString(host);
    if (normalized.isEmpty) {
      return;
    }

    setState(() {
      _latencyResults[normalized] = const _LatencyResult(_LatencyState.testing);
    });

    final stopwatch = Stopwatch()..start();

    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
          sendTimeout: const Duration(seconds: 5),
        ),
      );

      final trimmedHost = host.trim();
      final baseUrl = (trimmedHost.startsWith('http://') ||
              trimmedHost.startsWith('https://'))
          ? trimmedHost
          : 'https://$normalized';

      final response = await dio.get(
        '$baseUrl/api/health',
        options: Options(
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      stopwatch.stop();

      if (!mounted) {
        return;
      }

      final statusCode = response.statusCode;
      final latency = stopwatch.elapsedMilliseconds;
      final success =
          statusCode != null && statusCode >= 200 && statusCode < 300;

      setState(() {
        _latencyResults[normalized] = _LatencyResult(
          success ? _LatencyState.success : _LatencyState.failure,
          latencyMs: latency,
          statusCode: statusCode,
          error: success ? null : 'HTTP ${statusCode ?? '-'}',
        );
      });
    } catch (e) {
      stopwatch.stop();

      if (!mounted) {
        return;
      }

      final statusCode = e is DioException ? e.response?.statusCode : null;
      final message = e is DioException
          ? (e.message ?? e.error?.toString() ?? '未知错误')
          : e.toString();

      setState(() {
        _latencyResults[normalized] = _LatencyResult(
          _LatencyState.failure,
          statusCode: statusCode,
          error: _shortenMessage(message),
        );
      });
    }
  }

  String _describeLatencyResult(_LatencyResult? result,
      {bool includePlaceholder = false}) {
    if (result == null) {
      return includePlaceholder ? '尚未测试' : '';
    }

    switch (result.state) {
      case _LatencyState.idle:
        return includePlaceholder ? '尚未测试' : '';
      case _LatencyState.testing:
        return '测试中...';
      case _LatencyState.success:
        final latency = result.latencyMs;
        final statusCode = result.statusCode;
        final latencyText = latency != null ? '$latency ms' : '- ms';
        final statusText = statusCode != null ? 'HTTP $statusCode' : 'HTTP -';
        return '延迟 $latencyText ($statusText)';
      case _LatencyState.failure:
        final statusCode = result.statusCode;
        final error = result.error;
        final statusSuffix = statusCode != null ? ' (HTTP $statusCode)' : '';
        if (error != null && error.isNotEmpty) {
          return '连接失败: ${_shortenMessage(error)}';
        }
        return '连接失败$statusSuffix';
    }
  }

  Color _latencyColorForResult(BuildContext context, _LatencyResult? result) {
    final scheme = Theme.of(context).colorScheme;

    if (result == null || result.state == _LatencyState.idle) {
      return scheme.onSurfaceVariant;
    }

    switch (result.state) {
      case _LatencyState.idle:
        return scheme.onSurfaceVariant;
      case _LatencyState.testing:
        return scheme.primary;
      case _LatencyState.success:
        return scheme.secondary;
      case _LatencyState.failure:
        return scheme.error;
    }
  }

  String _shortenMessage(String message, {int maxLength = 60}) {
    if (message.length <= maxLength) {
      return message;
    }
    return '${message.substring(0, maxLength)}...';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ScrollableAppBar(
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
                // Host field with dropdown/autocomplete
                Autocomplete<String>(
                  initialValue: TextEditingValue(text: _hostValue),
                  optionsBuilder: (textEditingValue) {
                    final query = textEditingValue.text.trim().toLowerCase();
                    if (query.isEmpty) {
                      return _hostOptions;
                    }
                    return _hostOptions.where(
                      (option) => option.toLowerCase().contains(query),
                    );
                  },
                  fieldViewBuilder: (
                    context,
                    textEditingController,
                    focusNode,
                    onFieldSubmitted,
                  ) {
                    return TextFormField(
                      controller: textEditingController,
                      focusNode: focusNode,
                      decoration: const InputDecoration(
                        labelText: '服务器地址',
                        prefixIcon: Icon(Icons.dns),
                        border: OutlineInputBorder(),
                        helperText: '支持自定义，如: localhost:8888 或 api.example.com',
                      ),
                      keyboardType: TextInputType.url,
                      onChanged: (value) {
                        setState(() {
                          _hostValue = value;
                        });
                      },
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return '请输入服务器地址';
                        }
                        return null;
                      },
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                    );
                  },
                  onSelected: (selection) {
                    setState(() {
                      _hostValue = selection;
                    });
                  },
                ),

                const SizedBox(height: 8),
                _buildHostLatencyActions(context),

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
