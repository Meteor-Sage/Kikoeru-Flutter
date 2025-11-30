import 'package:dio/dio.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import '../models/work.dart';
import '../utils/server_utils.dart';
import 'cache_service.dart';

class KikoeruApiService {
  static const String remoteHost = ServerUtils.defaultRemoteHost;
  static const String localHost = ServerUtils.defaultLocalHost;

  late Dio _dio;
  String? _token;
  String? _host;
  int _subtitle = 0; // 1: 带字幕, 0: 不限制 (默认显示所有作品)
  String _order = 'create_date';
  String _sort = 'desc'; // 默认降序排列

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

  // Helper to check if we are using the official server
  bool get _isOfficialServer => ServerUtils.isOfficialServer(_host);

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

    if (_isOfficialServer) {
      return _loginOfficial(username, password);
    } else {
      return _loginCustom(username, password);
    }
  }

  Future<Map<String, dynamic>> _loginOfficial(
      String username, String password) async {
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

  Future<Map<String, dynamic>> _loginCustom(
      String username, String password) async {
    try {
      // Custom/Local server login logic
      // Currently same endpoint but separated for future customization
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

    if (_isOfficialServer) {
      return _registerOfficial(username, password, originalToken);
    } else {
      return _registerCustom(username, password, originalToken);
    }
  }

  Future<Map<String, dynamic>> _registerOfficial(
      String username, String password, String? originalToken) async {
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

  Future<Map<String, dynamic>> _registerCustom(
      String username, String password, String? originalToken) async {
    try {
      // Custom server registration might be simpler or different
      // For now, we'll use a simplified version without recommender logic
      // assuming local servers might not have the recommender system set up same way

      // Clear token for registration
      _token = null;

      final response = await _dio.post(
        '/api/auth/reg',
        data: {
          'name': username,
          'password': password,
          // 'recommenderUuid': ... // Skip recommender for custom server if not needed
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
      _token = originalToken;
      throw KikoeruApiException('Registration failed', e);
    }
  }

  Future<Map<String, dynamic>> getUserInfo() async {
    if (_isOfficialServer) {
      return _getUserInfoOfficial();
    } else {
      return _getUserInfoCustom();
    }
  }

  Future<Map<String, dynamic>> _getUserInfoOfficial() async {
    try {
      final response = await _dio.get('/api/auth/me');
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to get user info', e);
    }
  }

  Future<Map<String, dynamic>> _getUserInfoCustom() async {
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
    int pageSize = 40,
    String? order,
    String? sort,
    int? subtitle,
    int? seed,
  }) async {
    if (_isOfficialServer) {
      return _getWorksOfficial(
        page: page,
        pageSize: pageSize,
        order: order,
        sort: sort,
        subtitle: subtitle,
        seed: seed,
      );
    } else {
      return _getWorksCustom(
        page: page,
        pageSize: pageSize,
        order: order,
        sort: sort,
        subtitle: subtitle,
        seed: seed,
      );
    }
  }

  Future<Map<String, dynamic>> _getWorksOfficial({
    int page = 1,
    int pageSize = 40,
    String? order,
    String? sort,
    int? subtitle,
    int? seed,
  }) async {
    try {
      final queryParams = {
        'page': page,
        'pageSize': pageSize,
        'order': order ?? _order,
        'sort': sort ?? _sort,
        'subtitle': subtitle ?? _subtitle,
        'seed': seed ?? (21),
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

  Future<Map<String, dynamic>> _getWorksCustom({
    int page = 1,
    int pageSize = 40,
    String? order,
    String? sort,
    int? subtitle,
    int? seed,
  }) async {
    try {
      // Handle local backend compatibility for sort order
      String effectiveOrder = order ?? _order;
      if (effectiveOrder == 'create_date') {
        effectiveOrder = 'release';
      }

      final queryParams = {
        'page': page,
        'pageSize': pageSize,
        'order': effectiveOrder,
        'sort': sort ?? _sort,
        'subtitle': subtitle ?? _subtitle,
        'seed': seed ?? (21),
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
    if (_isOfficialServer) {
      return _getPopularWorksOfficial(
        page: page,
        pageSize: pageSize,
        keyword: keyword,
        subtitle: subtitle,
        withPlaylistStatus: withPlaylistStatus,
      );
    } else {
      return _getPopularWorksCustom(
        page: page,
        pageSize: pageSize,
        keyword: keyword,
        subtitle: subtitle,
        withPlaylistStatus: withPlaylistStatus,
      );
    }
  }

  Future<Map<String, dynamic>> _getPopularWorksOfficial({
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

  Future<Map<String, dynamic>> _getPopularWorksCustom({
    int page = 1,
    int pageSize = 20,
    String? keyword,
    int? subtitle,
    List<String>? withPlaylistStatus,
  }) async {
    try {
      // Custom backend doesn't have recommender, use /api/works with dl_count sort
      final queryParams = {
        'page': page,
        'pageSize': pageSize,
        'order': 'dl_count',
        'sort': 'desc',
        'subtitle': subtitle ?? 0,
      };

      final response = await _dio.get(
        '/api/works',
        queryParameters: queryParams,
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
    if (_isOfficialServer) {
      return _getRecommendedWorksOfficial(
        recommenderUuid: recommenderUuid,
        page: page,
        pageSize: pageSize,
        keyword: keyword,
        subtitle: subtitle,
        withPlaylistStatus: withPlaylistStatus,
      );
    } else {
      return _getRecommendedWorksCustom(
        page: page,
        pageSize: pageSize,
        keyword: keyword,
        subtitle: subtitle,
        withPlaylistStatus: withPlaylistStatus,
      );
    }
  }

  Future<Map<String, dynamic>> _getRecommendedWorksOfficial({
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

  Future<Map<String, dynamic>> _getRecommendedWorksCustom({
    int page = 1,
    int pageSize = 20,
    String? keyword,
    int? subtitle,
    List<String>? withPlaylistStatus,
  }) async {
    try {
      // Custom backend doesn't have recommender, use /api/works with random sort
      final queryParams = {
        'page': page,
        'pageSize': pageSize,
        'order': 'random',
        'sort': 'desc',
        'subtitle': subtitle ?? 0,
        'seed': DateTime.now().millisecondsSinceEpoch % 1000, // Random seed
      };

      final response = await _dio.get(
        '/api/works',
        queryParameters: queryParams,
      );
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to get recommended works', e);
    }
  }

  Future<Map<String, dynamic>> getWork(int workId) async {
    if (_isOfficialServer) {
      return _getWorkOfficial(workId);
    } else {
      return _getWorkCustom(workId);
    }
  }

  Future<Map<String, dynamic>> _getWorkOfficial(int workId) async {
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

  Future<Map<String, dynamic>> _getWorkCustom(int workId) async {
    try {
      // 1. 先检查缓存
      final cachedData = await CacheService.getCachedWorkDetail(workId);
      if (cachedData != null) {
        print('[API] 作品详情缓存命中: $workId');
        return cachedData;
      }

      // 2. 缓存未命中，从网络获取
      print('[API] 作品详情缓存未命中，从网络获取: $workId');

      // Fetch metadata
      final metadataResponse = await _dio.get('/api/work/$workId');
      final data = metadataResponse.data as Map<String, dynamic>;

      // Fetch tracks (file tree)
      try {
        final tracksResponse = await _dio.get('/api/tracks/$workId');
        if (tracksResponse.data is List) {
          data['children'] = tracksResponse.data;
        }
      } catch (e) {
        print('Failed to get tracks for work $workId: $e');
        // Don't fail the whole request if tracks fail, just log it
      }

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
    int pageSize = 40,
    String? order,
    String? sort,
    int? subtitle,
    int? seed,
  }) async {
    try {
      final queryParams = {
        'page': page,
        'pageSize': pageSize,
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
    int pageSize = 40,
    String? order,
    String? sort,
    int? subtitle,
    int? seed,
  }) async {
    try {
      final queryParams = {
        'page': page,
        'pageSize': pageSize,
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
    int pageSize = 40,
    String? order,
    String? sort,
    int? subtitle,
    bool includeTranslationWorks = true,
  }) async {
    if (_isOfficialServer) {
      return _searchWorksOfficial(
        keyword: keyword,
        page: page,
        pageSize: pageSize,
        order: order,
        sort: sort,
        subtitle: subtitle,
        includeTranslationWorks: includeTranslationWorks,
      );
    } else {
      return _searchWorksCustom(
        keyword: keyword,
        page: page,
        pageSize: pageSize,
        order: order,
        sort: sort,
        subtitle: subtitle,
        includeTranslationWorks: includeTranslationWorks,
      );
    }
  }

  Future<Map<String, dynamic>> _searchWorksOfficial({
    required String keyword,
    int page = 1,
    int pageSize = 40,
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

  Future<Map<String, dynamic>> _searchWorksCustom({
    required String keyword,
    int page = 1,
    int pageSize = 40,
    String? order,
    String? sort,
    int? subtitle,
    bool includeTranslationWorks = true,
  }) async {
    try {
      // Handle local backend compatibility for sort order
      String effectiveOrder = order ?? _order;
      if (effectiveOrder == 'create_date') {
        effectiveOrder = 'release';
      }

      // Construct the JSON keyword structure for custom backend
      // t=1 means simple text keyword
      final keywordJson = jsonEncode([
        {
          't': 1,
          'd': keyword,
          'name': keyword,
        }
      ]);

      final queryParams = <String, dynamic>{
        'keyword': keywordJson,
        'page': page,
        'pageSize': pageSize,
        'order': effectiveOrder,
        'sort': sort ?? _sort,
        'subtitle': subtitle ?? _subtitle,
        'isAdvance': 1, // Enable advanced search mode
        // 'includeTranslationWorks': includeTranslationWorks, // Not supported by local backend
      };

      final response = await _dio.get(
        '/api/search',
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
    if (_isOfficialServer) {
      return _getWorkReviewsOfficial(workId, page: page);
    } else {
      return _getWorkReviewsCustom(workId, page: page);
    }
  }

  Future<Map<String, dynamic>> _getWorkReviewsOfficial(int workId,
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

  Future<Map<String, dynamic>> _getWorkReviewsCustom(int workId,
      {int page = 1}) async {
    // Local backend does not support getting reviews for a specific work
    // Return empty structure to avoid errors
    return {
      'reviews': [],
      'pagination': {
        'currentPage': 1,
        'pageSize': 20,
        'totalCount': 0,
      }
    };
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

  /// 更新作品的收藏/进度状态
  Future<Map<String, dynamic>> updateReviewProgress(
    int workId, {
    String? progress,
    int? rating,
    String? reviewText,
  }) async {
    if (_isOfficialServer) {
      return _updateReviewProgressOfficial(workId,
          progress: progress, rating: rating, reviewText: reviewText);
    } else {
      return _updateReviewProgressCustom(workId,
          progress: progress, rating: rating, reviewText: reviewText);
    }
  }

  Future<Map<String, dynamic>> _updateReviewProgressOfficial(
    int workId, {
    String? progress,
    int? rating,
    String? reviewText,
  }) async {
    try {
      final data = <String, dynamic>{
        'work_id': workId,
      };
      if (progress != null) data['progress'] = progress;
      if (rating != null) data['rating'] = rating;
      if (reviewText != null) data['review_text'] = reviewText;

      final response = await _dio.put(
        '/api/review',
        data: data,
      );

      await CacheService.invalidateWorkDetailCache(workId);
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to update review progress', e);
    }
  }

  Future<Map<String, dynamic>> _updateReviewProgressCustom(
    int workId, {
    String? progress,
    int? rating,
    String? reviewText,
  }) async {
    print(
        '[API] 更新评论状态: workId=$workId, progress=$progress, rating=$rating, reviewText=${reviewText != null ? "exists" : "null"}');
    try {
      final data = <String, dynamic>{
        'work_id': workId,
      };
      final queryParams = <String, dynamic>{};

      if (progress != null) {
        data['progress'] = progress;
      } else {
        queryParams['starOnly'] = true;
      }
      if (rating != null) {
        data['rating'] = rating;
      } else {
        queryParams['starOnly'] = false;
        queryParams['progressOnly'] = true;
      }
      if (reviewText != null) data['review_text'] = reviewText;
      if ((progress != null && rating != null) || reviewText != null) {
        queryParams['starOnly'] = false;
      }

      final response = await _dio.put(
        '/api/review',
        data: data,
        queryParameters: queryParams,
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
    if (_isOfficialServer) {
      await _deleteReviewOfficial(workId);
    } else {
      await _deleteReviewCustom(workId);
    }
  }

  Future<void> _deleteReviewOfficial(int workId) async {
    try {
      await _dio.delete(
        '/api/review',
        queryParameters: {'work_id': workId},
      );
      await CacheService.invalidateWorkDetailCache(workId);
    } catch (e) {
      throw KikoeruApiException('Failed to delete review', e);
    }
  }

  Future<void> _deleteReviewCustom(int workId) async {
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

  /// 投票作品标签
  /// status: 0=取消投票, 1=支持, 2=反对
  Future<Map<String, dynamic>> voteWorkTag({
    required int workId,
    required int tagId,
    required int status,
  }) async {
    try {
      final response = await _dio.post(
        '/api/vote/vote-work-tag',
        data: {
          'workID': workId,
          'tagID': tagId,
          'status': status,
        },
      );

      // 投票成功后清除该作品的详情缓存，确保下次获取最新状态
      await CacheService.invalidateWorkDetailCache(workId);

      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to vote work tag', e);
    }
  }

  /// 添加标签到作品
  /// tagIds: 要添加的标签ID数组
  Future<Map<String, dynamic>> attachTagsToWork({
    required int workId,
    required List<int> tagIds,
  }) async {
    try {
      final response = await _dio.post(
        '/api/vote/attach-tags-to-work',
        data: {
          'workID': workId,
          'tagIDs': tagIds,
        },
      );

      // 添加成功后清除该作品的详情缓存，确保下次获取最新状态
      await CacheService.invalidateWorkDetailCache(workId);

      return response.data;
    } on DioException catch (e) {
      // 检查是否是需要绑定邮箱的错误
      if (e.response?.statusCode == 400) {
        final errorData = e.response?.data;
        if (errorData is Map &&
            errorData['error'] == 'vote.mustBindEmailFirst') {
          throw KikoeruApiException(
            'Must bind email first',
            'vote.mustBindEmailFirst',
          );
        }
      }
      throw KikoeruApiException('Failed to attach tags to work', e);
    } catch (e) {
      throw KikoeruApiException('Failed to attach tags to work', e);
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

  /// 获取用户的播放列表（需要token）
  /// page: 页码（从1开始）
  /// pageSize: 每页数量
  /// filterBy: 筛选条件（固定为'all'）
  Future<Map<String, dynamic>> getUserPlaylists({
    int page = 1,
    int pageSize = 20,
    String filterBy = 'all',
  }) async {
    try {
      final response = await _dio.get(
        '/api/playlist/get-playlists',
        queryParameters: {
          'page': page,
          'pageSize': pageSize,
          'filterBy': filterBy,
        },
      );
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to get user playlists', e);
    }
  }

  /// 创建播放列表（需要token）
  /// name: 播放列表名称（必填）
  /// privacy: 隐私设置 0=私享(只有您可以观看), 1=不公开(知道链接的人才能观看), 2=公开(任何人都可以观看)
  /// locale: 语言区域，默认'zh-CN'
  /// description: 描述（可选）
  /// works: 作品ID列表，默认为空列表
  Future<Map<String, dynamic>> createPlaylist({
    required String name,
    int privacy = 0,
    String locale = 'zh-CN',
    String? description,
    List<int>? works,
  }) async {
    try {
      final data = {
        'name': name,
        'privacy': privacy,
        'locale': locale,
        'works': works ?? [],
      };

      if (description != null && description.isNotEmpty) {
        data['description'] = description;
      }

      final response = await _dio.post(
        '/api/playlist/create-playlist',
        data: data,
      );
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to create playlist', e);
    }
  }

  /// 添加(收藏)别人的播放列表
  Future<Map<String, dynamic>> likePlaylist(String playlistId) async {
    try {
      final response = await _dio.post(
        '/api/playlist/like-playlist',
        data: {'id': playlistId},
      );
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to like playlist', e);
    }
  }

  /// 取消收藏播放列表（删除不属于自己的播放列表）
  Future<Map<String, dynamic>> removeLikePlaylist(String playlistId) async {
    try {
      final response = await _dio.post(
        '/api/playlist/remove-like-playlist',
        data: {'id': playlistId},
      );
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to remove liked playlist', e);
    }
  }

  /// 删除自己创建的播放列表
  Future<Map<String, dynamic>> deletePlaylist(String playlistId) async {
    try {
      final response = await _dio.post(
        '/api/playlist/delete-playlist',
        data: {'id': playlistId},
      );
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to delete playlist', e);
    }
  }

  /// 编辑播放列表元数据
  Future<Map<String, dynamic>> editPlaylistMetadata({
    required String id,
    required String name,
    required int privacy,
    required String description,
  }) async {
    try {
      final response = await _dio.post(
        '/api/playlist/edit-playlist-metadata',
        data: {
          'id': id,
          'data': {
            'name': name,
            'privacy': privacy,
            'description': description,
          },
        },
      );
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to edit playlist metadata', e);
    }
  }

  /// 添加作品到播放列表
  Future<Map<String, dynamic>> addWorksToPlaylist({
    required String playlistId,
    required List<String> works,
  }) async {
    try {
      final response = await _dio.post(
        '/api/playlist/add-works-to-playlist',
        data: {
          'id': playlistId,
          'works': works,
        },
      );
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to add works to playlist', e);
    }
  }

  /// 从播放列表移除作品
  Future<Map<String, dynamic>> removeWorksFromPlaylist({
    required String playlistId,
    required List<int> works,
  }) async {
    try {
      final response = await _dio.post(
        '/api/playlist/remove-works-from-playlist',
        data: {
          'id': playlistId,
          'works': works,
        },
      );
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to remove works from playlist', e);
    }
  }

  /// 获取播放列表元数据
  Future<Map<String, dynamic>> getPlaylistMetadata(String playlistId) async {
    try {
      final response = await _dio.get(
        '/api/playlist/get-playlist-metadata',
        queryParameters: {'id': playlistId},
      );
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to get playlist metadata', e);
    }
  }

  /// 获取播放列表中的作品
  Future<Map<String, dynamic>> getPlaylistWorks({
    required String playlistId,
    int page = 1,
    int pageSize = 12,
  }) async {
    try {
      final response = await _dio.get(
        '/api/playlist/get-playlist-works',
        queryParameters: {
          'id': playlistId,
          'page': page,
          'pageSize': pageSize,
        },
      );
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to get playlist works', e);
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
