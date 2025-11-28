import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:equatable/equatable.dart';

import '../models/user.dart';
import '../models/account.dart';
import '../services/kikoeru_api_service.dart';
import '../services/storage_service.dart';
import '../services/account_database.dart';

// Kikoeru API Service Provider
final kikoeruApiServiceProvider = Provider<KikoeruApiService>((ref) {
  return KikoeruApiService();
});

// Auth state
class AuthState extends Equatable {
  final User? currentUser;
  final String? token;
  final String? host;
  final bool isLoading;
  final String? error;
  final bool isLoggedIn;

  const AuthState({
    this.currentUser,
    this.token,
    this.host,
    this.isLoading = false,
    this.error,
    this.isLoggedIn = false,
  });

  AuthState copyWith({
    User? currentUser,
    String? token,
    String? host,
    bool? isLoading,
    String? error,
    bool? isLoggedIn,
  }) {
    return AuthState(
      currentUser: currentUser ?? this.currentUser,
      token: token ?? this.token,
      host: host ?? this.host,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
    );
  }

  @override
  List<Object?> get props =>
      [currentUser, token, host, isLoading, error, isLoggedIn];
}


/// 检查是否为asmr.one的官方服务器，要求地址包含 api.asmr 
bool _isOfficialServer(String? host) {
  if (host == null || host.isEmpty) return false;
  return host.contains('api.asmr');
}

// Auth notifier
class AuthNotifier extends StateNotifier<AuthState> {
  final KikoeruApiService _apiService;

  AuthNotifier(this._apiService) : super(const AuthState()) {
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    try {
      print('[Auth] Loading current user...');

      // First try to load from storage (faster)
      final token = StorageService.getString('auth_token');
      final host = StorageService.getString('server_host');
      final userJson = StorageService.getMap('current_user');

      print('[Auth] Stored token: ${token != null ? "exists" : "null"}');
      print('[Auth] Stored host: $host');

      if (token != null && host != null) {
        _apiService.init(token, host);

        User? user;
        if (userJson != null) {
          user = User.fromJson(userJson);
          print('[Auth] Loaded user from storage: ${user.name}');
        }

        state = state.copyWith(
          token: token,
          host: host,
          currentUser: user,
          isLoggedIn: true,
        );

        // Validate token by fetching user info
        try {
          print('[Auth] Validating token...');
          await _refreshUserInfo();
          print('[Auth] Token is valid, user logged in successfully');
          return; // Token is valid, we're done
        } catch (e) {
          print('[Auth] Token validation failed: $e');
          // Token is invalid, try to re-login with saved account
        }
      }

      // If no valid token, try to load from database and re-login
      print('[Auth] Checking database for active account...');
      final activeAccount = await AccountDatabase.instance.getActiveAccount();

      if (activeAccount != null) {
        // Silently re-login with saved credentials
        print(
            '[Auth] Found active account in database: ${activeAccount.username}');
        print('[Auth] Re-logging in with saved account...');

        _apiService.init('', activeAccount.host);

        final success = await login(
          activeAccount.username,
          activeAccount.password,
          activeAccount.host,
          silent: true, // Don't show loading state
        );

        if (success) {
          print('[Auth] Re-login successful');
          return;
        } else {
          print('[Auth] Re-login failed due to network or server issue');
          // 网络问题导致登录失败，但我们有缓存的账户信息
          // 允许用户以离线模式进入应用（可以使用本地下载内容）
          print('[Auth] Entering offline mode with cached account');

          // 使用缓存的账户信息设置基本状态
          _apiService.init('', activeAccount.host);

          state = state.copyWith(
            currentUser: User(
              name: activeAccount.username,
              group: 'guest',
              loggedIn: false, // 标记为未完全登录（离线模式）
              host: activeAccount.host,
              password: activeAccount.password,
              token: '',
              lastUpdateTime: DateTime.now(),
            ),
            host: activeAccount.host,
            token: '',
            isLoggedIn: false, // 离线模式
            error: '网络连接失败，以离线模式启动',
          );

          print('[Auth] Offline mode activated');
          return;
        }
      } else {
        print('[Auth] No active account found in database');
      }

      // If all fails, logout
      print('[Auth] No valid authentication found, logging out');
      await logout();
    } catch (e) {
      print('[Auth] Failed to load saved auth: $e');

      // 在异常情况下，也尝试检查是否有缓存账户
      try {
        final activeAccount = await AccountDatabase.instance.getActiveAccount();
        if (activeAccount != null) {
          print(
              '[Auth] Exception occurred but found cached account, entering offline mode');

          _apiService.init('', activeAccount.host);

          state = state.copyWith(
            currentUser: User(
              name: activeAccount.username,
              group: 'guest',
              loggedIn: false,
              host: activeAccount.host,
              password: activeAccount.password,
              token: '',
              lastUpdateTime: DateTime.now(),
            ),
            host: activeAccount.host,
            token: '',
            isLoggedIn: false,
            error: '网络连接失败，以离线模式启动',
          );

          return;
        }
      } catch (dbError) {
        print('[Auth] Failed to check database: $dbError');
      }

      await logout();
    }
  }

  Future<bool> login(
    String username,
    String password,
    String host, {
    bool silent = false,
  }) async {
    if (!silent) {
      state = state.copyWith(isLoading: true, error: null);
    }

    try {
      print(
          '[Auth] Login attempt - username: $username, host: $host, silent: $silent');

      // Initialize API service with empty token first
      _apiService.init('', host);

      // Attempt login
      final response = await _apiService.login(username, password, host);

      final token = response['token'] as String?;
      if (token == null) {
        throw Exception('No token received from server');
      }

      print('[Auth] Login successful, received token');

      // Normalize host URL to include protocol
      String normalizedHost;
      if (host.startsWith('http://') || host.startsWith('https://')) {
        normalizedHost = host;
      } else {
        // For remote hosts, use HTTPS; for localhost, use HTTP
        if (host.contains('localhost') ||
            host.startsWith('127.0.0.1') ||
            host.startsWith('192.168.')) {
          normalizedHost = 'http://$host';
        } else {
          normalizedHost = 'https://$host';
        }
      }

      print('[Auth] Normalized host: $normalizedHost');

      // Update API service with real token and normalized host
      _apiService.init(token, normalizedHost);

      // Get user info from login response or fetch it separately
      Map<String, dynamic> userInfo;
      if (response['user'] != null) {
        // Use user info from login response
        userInfo = response;
      } else {
        // Fetch user info separately
        userInfo = await _apiService.getUserInfo();
      }

      final user = User.fromJson(userInfo);

      // For official servers, verify the loggedIn field to ensure proper authentication
      // For self-hosted servers, skip this check as they may not return this field
      if (_isOfficialServer(normalizedHost) && !user.loggedIn) {
        throw Exception('Login failed: User not logged in');
      }

      // Create complete user object with credentials and token (using normalized host)
      final authenticatedUser = user.copyWith(
        password: password,
        host: normalizedHost,
        token: token,
        lastUpdateTime: DateTime.now(),
      );

      // Save to storage (using normalized host)
      await StorageService.setString('auth_token', token);
      await StorageService.setString('server_host', normalizedHost);
      await StorageService.setMap('current_user', authenticatedUser.toJson());

      // Save or update account in database
      try {
        final existingAccounts =
            await AccountDatabase.instance.getAllAccounts();
        final existingAccount = existingAccounts.firstWhere(
          (acc) => acc.username == username && acc.host == normalizedHost,
          orElse: () => Account(
            username: username,
            password: password,
            host: normalizedHost,
            isActive: true,
            createdAt: DateTime.now(),
          ),
        );

        if (existingAccount.id != null) {
          // Update existing account
          await AccountDatabase.instance.updateAccount(
            existingAccount.copyWith(
              password: password,
              isActive: true,
              lastUsedAt: DateTime.now(),
            ),
          );
        } else {
          // Create new account
          await AccountDatabase.instance.createAccount(
            Account(
              username: username,
              password: password,
              host: normalizedHost,
              isActive: true,
              createdAt: DateTime.now(),
              lastUsedAt: DateTime.now(),
            ),
          );
        }
        print('[Auth] Account saved to database');
      } catch (e) {
        print('[Auth] Failed to save account to database: $e');
      }

      state = state.copyWith(
        currentUser: authenticatedUser,
        token: token,
        host: normalizedHost,
        isLoading: false,
        isLoggedIn: true,
      );

      print('[Auth] Login completed, state updated');
      return true;
    } catch (e) {
      print('[Auth] Login error: $e');

      if (!silent) {
        state = state.copyWith(
          isLoading: false,
          error: 'Login failed: ${e.toString()}',
        );
      }
      return false;
    }
  }

  Future<bool> register(String username, String password, String host) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      // Initialize API service
      _apiService.init('', host);

      // Attempt registration
      final response = await _apiService.register(username, password, host);

      final token = response['token'] as String?;
      if (token == null) {
        throw Exception('No token received from server');
      }

      // Normalize host URL to include protocol
      String normalizedHost;
      if (host.startsWith('http://') || host.startsWith('https://')) {
        normalizedHost = host;
      } else {
        // For remote hosts, use HTTPS; for localhost, use HTTP
        if (host.contains('localhost') ||
            host.startsWith('127.0.0.1') ||
            host.startsWith('192.168.')) {
          normalizedHost = 'http://$host';
        } else {
          normalizedHost = 'https://$host';
        }
      }

      // Update API service with token and normalized host
      _apiService.init(token, normalizedHost);

      // Get user info from registration response or fetch it separately
      Map<String, dynamic> userInfo;
      if (response['user'] != null) {
        // Use user info from registration response
        userInfo = response;
      } else {
        // Fetch user info separately
        userInfo = await _apiService.getUserInfo();
      }

      final user = User.fromJson(userInfo);

      // For official servers, verify the loggedIn field to ensure proper authentication
      // For self-hosted servers, skip this check as they may not return this field
      if (_isOfficialServer(normalizedHost) && !user.loggedIn) {
        throw Exception('Registration failed: User not logged in');
      }

      // Create complete user object with credentials and token (using normalized host)
      final authenticatedUser = user.copyWith(
        password: password,
        host: normalizedHost,
        token: token,
        lastUpdateTime: DateTime.now(),
      );

      // Save to storage (using normalized host)
      await StorageService.setString('auth_token', token);
      await StorageService.setString('server_host', normalizedHost);
      await StorageService.setMap('current_user', authenticatedUser.toJson());

      // Save account to database
      try {
        await AccountDatabase.instance.createAccount(
          Account(
            username: username,
            password: password,
            host: normalizedHost,
            isActive: true,
            createdAt: DateTime.now(),
            lastUsedAt: DateTime.now(),
          ),
        );
        print('[Auth] Registered account saved to database');
      } catch (e) {
        print('[Auth] Failed to save registered account to database: $e');
      }

      state = state.copyWith(
        currentUser: authenticatedUser,
        token: token,
        host: normalizedHost,
        isLoading: false,
        isLoggedIn: true,
      );

      return true;
    } catch (e) {
      String errorMessage = 'Registration failed: ${e.toString()}';

      if (e is KikoeruApiException && e.originalError is DioException) {
        final dioError = e.originalError as DioException;
        if (dioError.response != null && dioError.response?.statusCode == 403) {
          final data = dioError.response?.data;
          if (data is Map && data['error'] != null) {
            errorMessage = data['error'];
          } else if (data is String) {
            try {
              final json = jsonDecode(data);
              if (json is Map && json['error'] != null) {
                errorMessage = json['error'];
              }
            } catch (_) {
              // Ignore json decode error
            }
          }
        }
      }

      state = state.copyWith(
        isLoading: false,
        error: errorMessage,
      );
      return false;
    }
  }

  Future<void> _refreshUserInfo() async {
    try {
      final userInfo = await _apiService.getUserInfo();
      final user = User.fromJson(userInfo);

      // For official servers, verify the loggedIn field
      // For self-hosted servers, skip this check as they may not return this field
      if (_isOfficialServer(state.host) && !user.loggedIn) {
        throw Exception('User not logged in');
      }

      await StorageService.setMap('current_user', user.toJson());

      state = state.copyWith(currentUser: user);
    } catch (e) {
      print('Failed to refresh user info: $e');
      // Rethrow the exception so caller can handle it
      rethrow;
    }
  }

  Future<void> updateHost(String host) async {
    if (state.token != null) {
      // Normalize host URL to include protocol
      String normalizedHost;
      if (host.startsWith('http://') || host.startsWith('https://')) {
        normalizedHost = host;
      } else {
        // For remote hosts, use HTTPS; for localhost, use HTTP
        if (host.contains('localhost') ||
            host.startsWith('127.0.0.1') ||
            host.startsWith('192.168.')) {
          normalizedHost = 'http://$host';
        } else {
          normalizedHost = 'https://$host';
        }
      }

      _apiService.init(state.token!, normalizedHost);
      await StorageService.setString('server_host', normalizedHost);
      state = state.copyWith(host: normalizedHost);
    }
  }

  Future<void> logout() async {
    try {
      await StorageService.remove('auth_token');
      await StorageService.remove('server_host');
      await StorageService.remove('current_user');
    } catch (e) {
      print('Failed to clear storage: $e');
    }

    state = const AuthState();
  }

  Future<void> switchUser(User user) async {
    final token = user.token;
    final host = user.host;

    if (token != null && host != null) {
      print('[Auth] Switching user - username: ${user.name}, host: $host');

      _apiService.init(token, host);
      await StorageService.setString('auth_token', token);
      await StorageService.setString('server_host', host);
      await StorageService.setMap('current_user', user.toJson());

      state = state.copyWith(
        currentUser: user,
        token: token,
        host: host,
        isLoggedIn: true,
      );

      print('[Auth] User switched successfully');
    } else {
      throw Exception('Invalid user data: missing token or host');
    }
  }

  Future<List<User>> getSavedUsers() async {
    final userKeys = StorageService.getAllUserKeys();
    final users = <User>[];

    for (final key in userKeys) {
      if (key != 'current_user' &&
          key != 'auth_token' &&
          key != 'server_host') {
        final userData = StorageService.getUser<Map<String, dynamic>>(key);
        if (userData != null) {
          try {
            users.add(User.fromJson(userData));
          } catch (e) {
            // Invalid user data, remove it
            await StorageService.removeUser(key);
          }
        }
      }
    }

    return users;
  }

  Future<void> saveUser(User user) async {
    final key = 'user_${user.name}_${user.host}';
    await StorageService.setUser(key, user.toJson());
  }

  Future<void> removeUser(User user) async {
    final key = 'user_${user.name}_${user.host}';
    await StorageService.removeUser(key);

    // If removing current user, logout
    if (state.currentUser == user) {
      await logout();
    }
  }

  /// 重新尝试连接（用于从离线模式恢复）
  Future<void> retryConnection() async {
    print('[Auth] Retrying connection...');
    await _loadCurrentUser();
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

// Providers
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final apiService = ref.watch(kikoeruApiServiceProvider);
  return AuthNotifier(apiService);
});

// Convenience providers
final isLoggedInProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).isLoggedIn;
});

final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(authProvider).currentUser;
});

final authTokenProvider = Provider<String?>((ref) {
  return ref.watch(authProvider).token;
});

final serverHostProvider = Provider<String?>((ref) {
  return ref.watch(authProvider).host;
});
