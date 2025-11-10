import 'package:dio/dio.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import '../models/work.dart';
import 'cache_service.dart';

class KikoeruApiService {
  static const String remoteHost = 'https://api.asmr-200.com'; //api.asmr.one
  static const String localHost = 'localhost:8888';

  late Dio _dio;
  String? _token;
  String? _host;
  int _subtitle = 0; // 1: 带字幕, 0: 不限制 (默认显示所有作品)
  String _order = 'create_date';
  String _sort = 'desc'; // 默认降序排列
  int _seed = 35; // 随机种子

  KikoeruApiService() {
    _dio = Dio();
    _setupInterceptors();
  }

  void _setupInterceptors() {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          // Add Authorization header if token exists
          // Only exclude for POST requests to auth endpoints (login/register)
          if (_token != null && _token!.isNotEmpty) {
            final isLoginRequest = options.method == 'POST' &&
                options.path.contains('/api/auth/me');
            final isSignupRequest = options.method == 'POST' &&
                (options.path.contains('/api/auth/signup') ||
                    options.path.contains('/api/auth/reg'));

            if (!isLoginRequest && !isSignupRequest) {
              options.headers['Authorization'] = 'Bearer $_token';
            }
          }

          options.connectTimeout = const Duration(seconds: 15);
          options.receiveTimeout = const Duration(seconds: 15);
          handler.next(options);
        },
        onError: (error, handler) async {
          // Handle errors globally
          print('API Error: ${error.message}');

          // 自动重试连接超时错误（仅重试一次）
          if (error.type == DioExceptionType.connectionTimeout &&
              error.requestOptions.extra['retried'] != true) {
            print('Connection timeout detected, retrying once...');

            // 标记已重试，避免无限循环
            error.requestOptions.extra['retried'] = true;

            try {
              // 重试请求
              final response = await _dio.fetch(error.requestOptions);
              return handler.resolve(response);
            } catch (e) {
              // 重试也失败，返回错误
              return handler.next(error);
            }
          }

          handler.next(error);
        },
      ),
    );

    _dio.interceptors.add(
      LogInterceptor(
        requestBody: true,
        responseBody: true,
        logPrint: (object) {
          // Custom logging if needed
          print(object);
        },
      ),
    );
  }

  void init(String token, String host) {
    _token = token;
    // Handle host configuration properly
    if (host.startsWith('http://') || host.startsWith('https://')) {
      _host = host;
    } else {
      // For remote hosts, use HTTPS; for localhost, use HTTP
      if (host.contains('localhost') ||
          host.startsWith('127.0.0.1') ||
          host.startsWith('192.168.')) {
        _host = 'http://$host';
      } else {
        _host = 'https://$host';
      }
    }
    _dio.options.baseUrl = _host!;

    print(
        '[API] Initialized - host: $_host, token: ${token.isEmpty ? "empty" : "exists (${token.length} chars)"}');
  }

  // Setters for configuration
  void setOrder(String order) {
    if (_order == order) {
      // Toggle sort direction
      _sort = _sort == 'asc' ? 'desc' : 'asc';
    } else {
      _order = order;
    }
  }

  void setSubtitle(int subtitle) {
    _subtitle = subtitle;
  }

  void setSeed(int seed) {
    _seed = seed;
  }

  // Check network connectivity
  Future<bool> isConnected() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    return connectivityResult != ConnectivityResult.none;
  }

  // Test if a host is reachable
  Future<bool> testHostConnection(String host) async {
    try {
      final testDio = Dio();
      testDio.options.connectTimeout = const Duration(seconds: 3);
      testDio.options.receiveTimeout = const Duration(seconds: 3);

      final testHost = host.startsWith('http') ? host : 'https://$host';

      await testDio.get(
        '$testHost/api/health',
        options: Options(
          validateStatus: (status) => status! < 500, // Accept any status < 500
        ),
      );
      return true;
    } catch (e) {
      print('Host connection test failed for $host: $e');
      return false;
    }
  }

  // Authentication APIs
  Future<Map<String, dynamic>> login(
      String username, String password, String host) async {
    // Set up host first without token
    if (host.startsWith('http://') || host.startsWith('https://')) {
      _host = host;
    } else {
      // For remote hosts, use HTTPS; for localhost, use HTTP
      if (host.contains('localhost') ||
          host.startsWith('127.0.0.1') ||
          host.startsWith('192.168.')) {
        _host = 'http://$host';
      } else {
        _host = 'https://$host';
      }
    }
    _dio.options.baseUrl = _host!;

    try {
      final response = await _dio.post(
        '/api/auth/me',
        data: {'name': username, 'password': password},
      );

      // If login successful, extract and store token
      if (response.data is Map && response.data['token'] != null) {
        _token = response.data['token'];
      }

      return response.data;
    } catch (e) {
      throw KikoeruApiException('Login failed', e);
    }
  }

  Future<Map<String, dynamic>> register(
      String username, String password, String host) async {
    // Save the original token at the very beginning
    // This ensures we can restore it if registration fails
    final originalToken = _token;

    // Set up host first without token
    if (host.startsWith('http://') || host.startsWith('https://')) {
      _host = host;
    } else {
      // For remote hosts, use HTTPS; for localhost, use HTTP
      if (host.contains('localhost') ||
          host.startsWith('127.0.0.1') ||
          host.startsWith('192.168.')) {
        _host = 'http://$host';
      } else {
        _host = 'https://$host';
      }
    }
    _dio.options.baseUrl = _host!;

    try {
      // Step 1: Get recommender UUID
      String recommenderUuid =
          '766cc58d-7f1e-4958-9a93-913400f378dc'; // Default recommender

      try {
        // Clear token to get registration info
        // (with token, this endpoint returns recommendations; without token, returns registration info)
        _token = null;

        final recommenderResponse = await _dio.post(
          '/api/recommender/recommend-for-user',
          data: {
            'keyword': ' ',
            'page': 1,
            'pageSize': 20,
          },
        );

        // Try to get recommender UUID from response
        if (recommenderResponse.data is Map) {
          if (recommenderResponse.data['uuid'] != null) {
            recommenderUuid = recommenderResponse.data['uuid'];
          } else if (recommenderResponse.data['recommenderUuid'] != null) {
            recommenderUuid = recommenderResponse.data['recommenderUuid'];
          }
        }
      } catch (e) {
        // If getting recommender fails, use default UUID
        print('Failed to get recommender, using default: $e');
      }

      // Step 2: Register with recommender UUID
      // Token is already cleared from step 1
      final response = await _dio.post(
        '/api/auth/reg',
        data: {
          'name': username,
          'password': password,
          'recommenderUuid': recommenderUuid,
        },
      );

      // If registration successful, extract and store token
      if (response.data is Map && response.data['token'] != null) {
        _token = response.data['token'];
      } else {
        // If no token returned, restore original token
        _token = originalToken;
      }

      return response.data;
    } catch (e) {
      // IMPORTANT: Restore original token on failure
      // This prevents logged-in users from losing their session
      _token = originalToken;
      throw KikoeruApiException('Registration failed', e);
    }
  }

  Future<Map<String, dynamic>> getUserInfo() async {
    try {
      final response = await _dio.get('/api/auth/me');
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to get user info', e);
    }
  }

  // Works APIs
  Future<Map<String, dynamic>> getWorks({
    int page = 1,
    String? order,
    String? sort,
    int? subtitle,
    int? seed,
  }) async {
    try {
      final queryParams = {
        'page': page,
        'order': order ?? _order,
        'sort': sort ?? _sort,
        'subtitle': subtitle ?? _subtitle,
        'seed': seed ?? _seed,
      };

      final response = await _dio.get(
        '/api/works',
        queryParameters: queryParams,
      );
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to get works', e);
    }
  }

  // Get popular recommended works (max 100 items, no sorting)
  Future<Map<String, dynamic>> getPopularWorks({
    int page = 1,
    int pageSize = 20,
    String? keyword,
    int? subtitle,
    List<String>? withPlaylistStatus,
  }) async {
    try {
      final data = {
        'keyword': keyword ?? ' ',
        'page': page,
        'pageSize': pageSize,
        'subtitle': subtitle ?? 0,
        'localSubtitledWorks': [],
        'withPlaylistStatus': withPlaylistStatus ?? [],
      };

      final response = await _dio.post(
        '/api/recommender/popular',
        data: data,
      );
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to get popular works', e);
    }
  }

  // Get recommended works for user (max 100 items, no sorting)
  // This endpoint returns registration info when not logged in,
  // and returns recommended works when logged in with token
  Future<Map<String, dynamic>> getRecommendedWorks({
    required String recommenderUuid,
    int page = 1,
    int pageSize = 20,
    String? keyword,
    int? subtitle,
    List<String>? withPlaylistStatus,
  }) async {
    try {
      final data = {
        'keyword': keyword ?? ' ',
        'recommenderUuid': recommenderUuid,
        'page': page,
        'pageSize': pageSize,
        'subtitle': subtitle ?? 0,
        'localSubtitledWorks': [],
        'withPlaylistStatus': withPlaylistStatus ?? [],
      };

      final response = await _dio.post(
        '/api/recommender/recommend-for-user',
        data: data,
      );
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to get recommended works', e);
    }
  }

  Future<Map<String, dynamic>> getWork(int workId) async {
    try {
      // 1. 先检查缓存
      final cachedData = await CacheService.getCachedWorkDetail(workId);
      if (cachedData != null) {
        print('[API] 作品详情缓存命中: $workId');
        return cachedData;
      }

      // 2. 缓存未命中，从网络获取
      print('[API] 作品详情缓存未命中，从网络获取: $workId');
      final response = await _dio.get('/api/work/$workId');
      final data = response.data as Map<String, dynamic>;

      // 3. 保存到缓存
      await CacheService.cacheWorkDetail(workId, data);

      return data;
    } catch (e) {
      throw KikoeruApiException('Failed to get work', e);
    }
  }

  Future<Map<String, dynamic>> getWorksByTag({
    required int tagId,
    int page = 1,
    String? order,
    String? sort,
    int? subtitle,
    int? seed,
  }) async {
    try {
      final queryParams = {
        'page': page,
        'order': order ?? _order,
        'sort': sort ?? _sort,
        'subtitle': subtitle ?? _subtitle,
        'seed': seed ?? (21),
      };

      final response = await _dio.get(
        '/api/tags/$tagId/works',
        queryParameters: queryParams,
      );
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to get works by tag', e);
    }
  }

  Future<Map<String, dynamic>> getWorksByVa({
    required String vaId,
    int page = 1,
    String? order,
    String? sort,
    int? subtitle,
    int? seed,
  }) async {
    try {
      final queryParams = {
        'page': page,
        'order': order ?? _order,
        'sort': sort ?? _sort,
        'subtitle': subtitle ?? _subtitle,
        'seed': seed ?? (21),
      };

      final response = await _dio.get(
        '/api/vas/$vaId/works',
        queryParameters: queryParams,
      );
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to get works by VA', e);
    }
  }

  // Search API - 新版搜索接口
  Future<Map<String, dynamic>> searchWorks({
    required String keyword, // 搜索关键词（可以是组合的搜索条件）
    int page = 1,
    int pageSize = 20,
    String? order,
    String? sort,
    int? subtitle,
    bool includeTranslationWorks = true,
  }) async {
    try {
      // URL编码关键词
      final encodedKeyword = Uri.encodeComponent(keyword);

      final queryParams = <String, dynamic>{
        'page': page,
        'pageSize': pageSize,
        'order': order ?? _order,
        'sort': sort ?? _sort,
        'subtitle': subtitle ?? _subtitle,
        'includeTranslationWorks': includeTranslationWorks,
      };

      final response = await _dio.get(
        '/api/search/$encodedKeyword',
        queryParameters: queryParams,
      );
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to search works', e);
    }
  }

  // Tags API
  Future<List<dynamic>> getAllTags() async {
    try {
      final response = await _dio.get('/api/tags/');
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to get tags', e);
    }
  }

  Future<List<Tag>> searchTags(String query) async {
    try {
      final tags = await getAllTags();
      final filteredTags = tags
          .where((tag) => tag['name']
              .toString()
              .toLowerCase()
              .contains(query.toLowerCase()))
          .map((tag) => Tag.fromJson(tag))
          .toList();
      return filteredTags;
    } catch (e) {
      throw KikoeruApiException('Failed to search tags', e);
    }
  }

  // VAs API
  Future<List<dynamic>> getAllVas() async {
    try {
      final response = await _dio.get('/api/vas/');
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to get VAs', e);
    }
  }

  Future<List<Va>> searchVas(String query) async {
    try {
      final vas = await getAllVas();
      final filteredVas = vas
          .where((va) =>
              va['name'].toString().toLowerCase().contains(query.toLowerCase()))
          .map((va) => Va.fromJson(va))
          .toList();
      return filteredVas;
    } catch (e) {
      throw KikoeruApiException('Failed to search VAs', e);
    }
  }

  // Circles API
  Future<List<dynamic>> getAllCircles() async {
    try {
      final response = await _dio.get('/api/circles/');
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to get circles', e);
    }
  }

  // Tracks API
  Future<List<dynamic>> getWorkTracks(int workId) async {
    try {
      // 1. 尝试从缓存获取
      final cachedJson = await CacheService.getCachedWorkTracks(workId);
      if (cachedJson != null) {
        print('[API] 从缓存加载作品文件列表: $workId');
        return jsonDecode(cachedJson) as List<dynamic>;
      }

      // 2. 缓存未命中，从网络获取
      final response = await _dio.get('/api/tracks/$workId');
      final tracks = response.data as List<dynamic>;

      // 3. 保存到缓存
      await CacheService.cacheWorkTracks(workId, jsonEncode(tracks));
      print('[API] 已缓存作品文件列表: $workId');

      return tracks;
    } catch (e) {
      throw KikoeruApiException('Failed to get tracks', e);
    }
  }

  // Reviews API
  Future<Map<String, dynamic>> getWorkReviews(int workId,
      {int page = 1}) async {
    try {
      final response = await _dio.get(
        '/api/review/$workId',
        queryParameters: {'page': page},
      );
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to get reviews', e);
    }
  }

  /// 获取当前账户的 Review/收藏状态列表
  /// 支持的 filter: marked, listening, listened, replay, postponed
  /// 传入 null 或空字符串时为全部
  Future<Map<String, dynamic>> getMyReviews({
    int page = 1,
    String? filter,
    String order = 'updated_at',
    String sort = 'desc',
  }) async {
    try {
      final query = <String, dynamic>{
        'page': page,
        'order': order,
        'sort': sort,
      };
      if (filter != null && filter.isNotEmpty) {
        query['filter'] = filter;
      }
      final response = await _dio.get(
        '/api/review',
        queryParameters: query,
      );
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to get my reviews', e);
    }
  }

  Future<Map<String, dynamic>> submitReview(
    int workId, {
    String? text,
    int? rating,
    bool? recommend,
  }) async {
    try {
      final data = <String, dynamic>{};
      if (text != null) data['text'] = text;
      if (rating != null) data['rating'] = rating;
      if (recommend != null) data['recommend'] = recommend;

      final response = await _dio.put(
        '/api/review/$workId',
        data: data,
      );
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to submit review', e);
    }
  }

  /// 更新作品的收藏/进度状态
  Future<Map<String, dynamic>> updateReviewProgress(
    int workId, {
    required String progress,
    int? rating,
    String? reviewText,
  }) async {
    try {
      final data = <String, dynamic>{
        'work_id': workId,
        'progress': progress,
      };
      if (rating != null) data['rating'] = rating;
      if (reviewText != null) data['review_text'] = reviewText;

      final response = await _dio.put(
        '/api/review',
        data: data,
      );

      // 更新成功后清除该作品的详情缓存，确保下次获取最新状态
      await CacheService.invalidateWorkDetailCache(workId);

      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to update review progress', e);
    }
  }

  /// 删除作品的评论/收藏状态
  Future<void> deleteReview(int workId) async {
    try {
      await _dio.delete(
        '/api/review',
        queryParameters: {'work_id': workId},
      );

      // 删除成功后清除该作品的详情缓存，确保下次获取最新状态
      await CacheService.invalidateWorkDetailCache(workId);
    } catch (e) {
      throw KikoeruApiException('Failed to delete review', e);
    }
  }

  // Favorites API
  Future<Map<String, dynamic>> getFavorites({int page = 1}) async {
    try {
      final response = await _dio.get(
        '/api/favourites',
        queryParameters: {'page': page},
      );
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to get favorites', e);
    }
  }

  Future<void> addToFavorites(int workId) async {
    try {
      await _dio.put('/api/favourites/$workId');
    } catch (e) {
      throw KikoeruApiException('Failed to add to favorites', e);
    }
  }

  Future<void> removeFromFavorites(int workId) async {
    try {
      await _dio.delete('/api/favourites/$workId');
    } catch (e) {
      throw KikoeruApiException('Failed to remove from favorites', e);
    }
  }

  // Playlists API
  Future<List<dynamic>> getPlaylists() async {
    try {
      final response = await _dio.get('/api/playlists');
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to get playlists', e);
    }
  }

  Future<Map<String, dynamic>> createPlaylist(String name) async {
    try {
      final response = await _dio.post(
        '/api/playlists',
        data: {'name': name},
      );
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to create playlist', e);
    }
  }

  // Progress API
  Future<void> updateProgress(int workId, double progress) async {
    try {
      await _dio.put(
        '/api/progress/$workId',
        data: {'progress': progress},
      );
    } catch (e) {
      throw KikoeruApiException('Failed to update progress', e);
    }
  }

  Future<Map<String, dynamic>> getProgress(int workId) async {
    try {
      final response = await _dio.get('/api/progress/$workId');
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to get progress', e);
    }
  }

  // Download API
  String getDownloadUrl(String hash, String fileName) {
    return '$_host/api/media/download/$hash/$fileName';
  }

  String getStreamUrl(String hash, String fileName) {
    return '$_host/api/media/stream/$hash/$fileName';
  }

  String getCoverUrl(int workId) {
    return '$_host/api/cover/$workId';
  }

  // Cleanup
  void dispose() {
    _dio.close();
  }
}

// Provider
final kikoeruApiServiceProvider = Provider<KikoeruApiService>((ref) {
  return KikoeruApiService();
});

class KikoeruApiException implements Exception {
  final String message;
  final dynamic originalError;

  KikoeruApiException(this.message, this.originalError);

  @override
  String toString() => 'KikoeruApiException: $message';
}
