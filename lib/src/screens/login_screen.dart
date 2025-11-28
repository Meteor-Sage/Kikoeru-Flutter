import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../services/kikoeru_api_service.dart';
import '../utils/snackbar_util.dart';
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

    if (!_isLogin) {
      if (username.length < 5) {
        SnackBarUtil.showError(context, '用户名不能少于5个字符');
        setState(() => _isLoading = false);
        return;
      }
      if (password.length < 5) {
        SnackBarUtil.showError(context, '密码不能少于5个字符');
        setState(() => _isLoading = false);
        return;
      }
    }

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
          SnackBarUtil.showSuccess(context, '账户 "$username" 已添加');
        } else {
          // Normal login - go to main screen
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const MainScreen()),
            (route) => false, // Remove all previous routes
          );
        }
      } else if (mounted) {
        final error = ref.read(authProvider).error;
        SnackBarUtil.showError(
          context,
          error ?? (_isLogin ? '登录失败' : '注册失败'),
        );
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtil.showError(
          context,
          _isLogin ? '登录失败' : '注册失败',
        );
      }
    }

    setState(() => _isLoading = false);
  }

  // 游客登录
  Future<void> _loginAsGuest() async {
    // 验证服务器地址
    if (_hostValue.trim().isEmpty) {
      SnackBarUtil.showError(context, '请先输入服务器地址');
      return;
    }

    // 显示二次确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('游客模式确认'),
          content: const Text(
            '您将使用公用游客账户登录。\n\n'
            '请注意：\n'
            '• 收藏、评论等功能会与其他游客用户共享\n'
            '• 访问速率可能会受到限制\n'
            '• 数据不保证安全性和持久性\n\n'
            '建议注册专属账户以获得更好的使用体验。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('继续使用游客模式'),
            ),
          ],
        );
      },
    );

    // 用户取消了操作
    if (confirmed != true) {
      return;
    }

    setState(() => _isLoading = true);

    final host = _hostValue.trim();
    const guestUsername = 'guest';
    const guestPassword = 'guest';

    try {
      final success = await ref
          .read(authProvider.notifier)
          .login(guestUsername, guestPassword, host);

      if (success && mounted) {
        if (widget.isAddingAccount) {
          // Adding account mode - just go back
          Navigator.pop(context, true);
          SnackBarUtil.showSuccess(context, '游客账户已添加');
        } else {
          // Normal login - go to main screen
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const MainScreen()),
            (route) => false,
          );
        }
      } else if (mounted) {
        final error = ref.read(authProvider).error;
        SnackBarUtil.showError(
          context,
          error ?? '游客登录失败',
        );
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtil.showError(context, '游客登录失败');
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

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
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
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            statusText,
            style:
                Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
            textAlign: TextAlign.right,
          ),
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
      String baseUrl;
      if (trimmedHost.startsWith('http://') ||
          trimmedHost.startsWith('https://')) {
        baseUrl = trimmedHost;
      } else {
        if (normalized.contains('localhost') ||
            normalized.startsWith('127.0.0.1') ||
            normalized.startsWith('192.168.')) {
          baseUrl = 'http://$normalized';
        } else {
          baseUrl = 'https://$normalized';
        }
      }

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
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

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
        child: isLandscape ? _buildLandscapeLayout() : _buildPortraitLayout(),
      ),
    );
  }

  // 竖屏布局
  Widget _buildPortraitLayout() {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
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
                    Image.asset(
                      'assets/icons/app_icon.ico',
                      width: 64,
                      height: 64,
                      errorBuilder: (context, error, stackTrace) {
                        // 如果图片加载失败，显示默认图标
                        return Icon(
                          Icons.audiotrack,
                          size: 64,
                          color: Theme.of(context).colorScheme.primary,
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'KikoFlu',
                      style:
                          Theme.of(context).textTheme.headlineMedium?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                    ),
                  ],
                ),
              ),
              ..._buildFormFields(),
            ],
          ),
        ),
      ),
    );
  }

  // 横屏布局
  Widget _buildLandscapeLayout() {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Row(
        children: [
          // 左侧：Logo区域
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/icons/app_icon.ico',
                    width: 80,
                    height: 80,
                    errorBuilder: (context, error, stackTrace) {
                      // 如果图片加载失败，显示默认图标
                      return Icon(
                        Icons.audiotrack,
                        size: 80,
                        color: Theme.of(context).colorScheme.primary,
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'KikoFlu',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
            ),
          ),
          // 右侧：表单区域
          Expanded(
            flex: 3,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _buildFormFields(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 表单字段列表
  List<Widget> _buildFormFields() {
    return [
      // Username field
      TextFormField(
        controller: _usernameController,
        autofillHints: const [AutofillHints.username],
        decoration: const InputDecoration(
          labelText: '用户名',
          prefixIcon: Icon(Icons.person),
          border: OutlineInputBorder(),
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return '请输入用户名';
          }
          if (!_isLogin && value.trim().length < 5) {
            return '用户名至少需要5个字符';
          }
          return null;
        },
        textInputAction: TextInputAction.next,
      ),

      const SizedBox(height: 16),

      // Password field
      TextFormField(
        controller: _passwordController,
        autofillHints: const [AutofillHints.password],
        obscureText: _obscurePassword,
        decoration: InputDecoration(
          labelText: '密码',
          prefixIcon: const Icon(Icons.lock),
          suffixIcon: IconButton(
            icon: Icon(
              _obscurePassword ? Icons.visibility : Icons.visibility_off,
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
          if (!_isLogin && value.length < 5) {
            return '密码至少需要5个字符';
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
          // 始终显示所有推荐选项
          return _hostOptions;
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

      const SizedBox(height: 15),

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

      const SizedBox(height: 12),

      // Guest login button (only show in login mode)
      if (_isLogin)
        OutlinedButton.icon(
          onPressed: _isLoading ? null : _loginAsGuest,
          icon: const Icon(Icons.person_outline),
          label: const Text('游客模式'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.secondary,
          ),
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
    ];
  }
}
