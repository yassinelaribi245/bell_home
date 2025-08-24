import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:hive/hive.dart';
import 'package:bellui/models/models.dart'; // Import ApiResponse from models.dart
import 'package:flutter/foundation.dart'; // For debugPrint

/**
 * API Service Class
 * 
 * This service class provides a centralized interface for all API communications
 * with the backend server. It handles:
 * 
 * - Authentication and token management
 * - Camera CRUD operations and control
 * - Home management and configuration
 * - Real-time status updates
 * - Error handling and retry logic
 * - Request/response logging
 * - Data caching and offline support
 * 
 * The service uses HTTP requests for standard operations and provides
 * methods for all camera and home management functionality.
 */
class ApiService {
  // API configuration
  static const String baseUrl = 'https://e39ad83dbdb5.ngrok-free.app/bellapp/public/api';
  /// Node.js server URL for Socket.IO (set your actual Node.js server URL here)
  static const String nodeServerUrl = 'https://538ea5f38580.ngrok-free.app';
  static const Duration _timeout = Duration(seconds: 30);
  static const int _maxRetries = 3;
  
  // Singleton pattern
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();
  
  // HTTP client
  final http.Client _client = http.Client();
  
  // Authentication token
  String? _authToken;
  int? _currentUserId;
  
  /**
   * Initialize API Service
   * 
   * Sets up the API service with authentication token and user information
   * from local storage. Should be called when the app starts.
   */
  Future<void> initialize() async {
    try {
      final box = Hive.box('authBox');
      final user = box.get('user');
      final token = box.get('auth_token');
      
      if (user != null && token != null) {
        _currentUserId = user['id'];
        _authToken = token;
        debugPrint('API Service initialized for user ${user['nom']}'); // Use debugPrint
      } else {
        debugPrint('API Service initialized without authentication'); // Use debugPrint
      }
    } catch (e) {
      debugPrint('Error initializing API service: $e'); // Use debugPrint
    }
  }
  
  /**
   * Get Headers
   * 
   * Returns HTTP headers with authentication token and content type.
   */
  Map<String, String> _getHeaders() {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    
    if (_authToken != null) {
      headers['Authorization'] = 'Bearer $_authToken';
    }
    
    return headers;
  }
  
  /**
   * Make HTTP Request
   * 
   * Generic method for making HTTP requests with error handling,
   * retries, and logging.
   */
  Future<http.Response> _makeRequest(
    String method,
    String endpoint, {
    Map<String, dynamic>? body,
    int retryCount = 0,
  }) async {
    final url = Uri.parse('$baseUrl$endpoint');
    final headers = _getHeaders();
    
    try {
      debugPrint('API Request: $method $endpoint'); // Use debugPrint
      if (body != null) {
        debugPrint('Request Body: ${json.encode(body)}'); // Use debugPrint
      }
      
      http.Response response;
      
      switch (method.toUpperCase()) {
        case 'GET':
          response = await _client.get(url, headers: headers).timeout(_timeout);
          break;
        case 'POST':
          response = await _client.post(
            url,
            headers: headers,
            body: body != null ? json.encode(body) : null,
          ).timeout(_timeout);
          break;
        case 'PUT':
          response = await _client.put(
            url,
            headers: headers,
            body: body != null ? json.encode(body) : null,
          ).timeout(_timeout);
          break;
        case 'DELETE':
          response = await _client.delete(url, headers: headers).timeout(_timeout);
          break;
        default:
          throw Exception('Unsupported HTTP method: $method');
      }
      
      debugPrint('API Response: ${response.statusCode} ${response.reasonPhrase}'); // Use debugPrint
      
      // Handle authentication errors
      if (response.statusCode == 401) {
        await _handleAuthenticationError();
        throw ApiException('Authentication failed', 401);
      }
      
      // Retry on server errors
      if (response.statusCode >= 500 && retryCount < _maxRetries) {
        debugPrint('Server error, retrying... (${retryCount + 1}/$_maxRetries)'); // Use debugPrint
        await Future.delayed(Duration(seconds: (retryCount + 1) * 2));
        return _makeRequest(method, endpoint, body: body, retryCount: retryCount + 1);
      }
      
      return response;
      
    } catch (e) {
      debugPrint('API Request Error: $e'); // Use debugPrint
      
      // Retry on network errors
      if (retryCount < _maxRetries && e is! ApiException) {
        debugPrint('Network error, retrying... (${retryCount + 1}/$_maxRetries)'); // Use debugPrint
        await Future.delayed(Duration(seconds: (retryCount + 1) * 2));
        return _makeRequest(method, endpoint, body: body, retryCount: retryCount + 1);
      }
      
      rethrow;
    }
  }
  
  /**
   * Handle Authentication Error
   * 
   * Handles authentication failures by clearing stored tokens
   * and redirecting to login if necessary.
   */
  Future<void> _handleAuthenticationError() async {
    try {
      final box = Hive.box('authBox');
      await box.delete('auth_token');
      _authToken = null;
      _currentUserId = null;
      debugPrint('Authentication token cleared due to auth error'); // Use debugPrint
    } catch (e) {
      debugPrint('Error handling authentication error: $e'); // Use debugPrint
    }
  }
  
  // ==================== USER AUTHENTICATION ====================
  
  /**
   * Login User
   * 
   * Authenticates user with email and password, stores token and user info.
   */
  Future<ApiResponse<Map<String, dynamic>>> login(String email, String password) async {
    final response = await _makeRequest('POST', '/auth/login', body: {
      'email': email,
      'password': password,
    });
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      
      // Store authentication data
      final box = Hive.box('authBox');
      await box.put('auth_token', data['token']);
      await box.put('user', data['user']);
      
      _authToken = data['token'];
      _currentUserId = data['user']['id'];
      
      return ApiResponse.success(data, response.statusCode);
    } else {
      final error = json.decode(response.body);
      return ApiResponse.error(error['message'] ?? 'Login failed', response.statusCode);
    }
  }
  
  /**
   * Register User
   * 
   * Creates a new user account with the provided information.
   */
  Future<ApiResponse<Map<String, dynamic>>> register(Map<String, dynamic> userData) async {
    final response = await _makeRequest('POST', '/auth/register', body: userData);
    
    if (response.statusCode == 201) {
      return ApiResponse.success(json.decode(response.body), response.statusCode);
    } else {
      final error = json.decode(response.body);
      return ApiResponse.error(error['message'] ?? 'Registration failed', response.statusCode);
    }
  }
  
  /// Save user data to Hive
  Future<void> saveUserData(Map<String, dynamic> user) async {
    final box = Hive.box('authBox');
    await box.put('user', user);
  }

  /// Logout and clear all user info
  Future<void> logout() async {
    final box = Hive.box('authBox');
    final user = box.get('user');
    if (user != null && user['email'] != null) {
      try {
        await _makeRequest('POST', '/delete-fcm-token', body: {'email': user['email']});
      } catch (e) {
        debugPrint('Error removing FCM token from backend: $e');
      }
    }
    await box.clear();
    _authToken = null;
    _currentUserId = null;
  }
  
  // ==================== HOME MANAGEMENT ====================
  
  /**
   * Get User Homes
   * 
   * Retrieves all homes associated with the current user by email.
   */
  Future<ApiResponse<List<Home>>> getUserHomes() async {
    final box = Hive.box('authBox');
    final user = box.get('user');
    if (user == null || user['email'] == null) {
      return ApiResponse.error('User not authenticated', 401);
    }
    final response = await _makeRequest('POST', '/homes_user', body: {
      'email': user['email'],
    });
    if (response.statusCode == 200) {
      final Map<String, dynamic> data = json.decode(response.body);
      final List<dynamic> homesJson = data['homes'] ?? [];
      final homes = homesJson.map((json) => Home.fromJson(json)).toList();
      return ApiResponse.success(homes, response.statusCode);
    } else {
      return ApiResponse.error('Failed to load homes', response.statusCode);
    }
  }

  // NEW: Alias for getUserHomes to fix build error
  Future<ApiResponse<List<Home>>> getHomes() async {
    return getUserHomes();
  }
  
  /**
   * Get Home Details
   * 
   * Retrieves detailed information about a specific home.
   */
  Future<ApiResponse<Home>> getHomeDetails(int homeId) async {
    final response = await _makeRequest('GET', '/homes/$homeId');
    
    if (response.statusCode == 200) {
      return ApiResponse.success(Home.fromJson(json.decode(response.body)), response.statusCode);
    } else {
      return ApiResponse.error('Failed to load home details', response.statusCode);
    }
  }
  
  /**
   * Create Home
   * 
   * Creates a new home with the provided information, using email.
   */
  Future<ApiResponse<Home>> createHome(Map<String, dynamic> homeData) async {
    final box = Hive.box('authBox');
    final user = box.get('user');
    if (user == null || user['email'] == null) {
      return ApiResponse.error('User not authenticated', 401);
    }
    homeData['email'] = user['email'];
    final response = await _makeRequest('POST', '/homes', body: homeData);
    if (response.statusCode == 201) {
      return ApiResponse.success(Home.fromJson(json.decode(response.body)), response.statusCode);
    } else {
      final error = json.decode(response.body);
      return ApiResponse.error(error['message'] ?? 'Failed to create home', response.statusCode);
    }
  }
  
  /**
   * Update Home
   * 
   * Updates an existing home with new information.
   */
  Future<ApiResponse<Home>> updateHome(int homeId, Map<String, dynamic> homeData) async {
    final response = await _makeRequest('PUT', '/homes/$homeId', body: homeData);
    
    if (response.statusCode == 200) {
      return ApiResponse.success(Home.fromJson(json.decode(response.body)), response.statusCode);
    } else {
      final error = json.decode(response.body);
      return ApiResponse.error(error['message'] ?? 'Failed to update home', response.statusCode);
    }
  }
  
  /**
   * Delete Home
   * 
   * Deletes a home and all associated cameras.
   */
  Future<ApiResponse<User>> getUserInfo(String email) async {
    final response = await _makeRequest('GET', '/userinfo/$email');
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final userInfoList = data['userinfo'] as List;
      
      if (userInfoList.isNotEmpty) {
        final userJson = userInfoList[0] as Map<String, dynamic>;
        final user = User.fromJson(userJson);
        return ApiResponse.success(user, response.statusCode);
      } else {
        return ApiResponse.error('User not found', 404);
      }
    } else {
      return ApiResponse.error('Failed to load user info', response.statusCode);
    }
  }
  Future<ApiResponse<void>> deleteHome(int homeId) async {
    final response = await _makeRequest('DELETE', '/deletehome/$homeId');
    
    if (response.statusCode == 200) {
      return ApiResponse.success(null, response.statusCode);
    } else {
      return ApiResponse.error('Failed to delete home', response.statusCode);
    }
  }
  
  /**
   * Get Home Status
   * 
   * Retrieves current status and health information for a home.
   */
  Future<ApiResponse<Map<String, dynamic>>> getHomeStatus(int homeId) async {
    final response = await _makeRequest('GET', '/homes/$homeId/status');
    
    if (response.statusCode == 200) {
      return ApiResponse.success(json.decode(response.body), response.statusCode);
    } else {
      return ApiResponse.error('Failed to get home status', response.statusCode);
    }
  }
  
  /**
   * Get Home Settings
   * 
   * Retrieves security settings and configuration for a home.
   */
  Future<ApiResponse<Map<String, dynamic>>> getHomeSettings(int homeId) async {
    final response = await _makeRequest('GET', '/homes/$homeId/settings');
    
    if (response.statusCode == 200) {
      return ApiResponse.success(json.decode(response.body), response.statusCode);
    } else {
      return ApiResponse.error('Failed to get home settings', response.statusCode);
    }
  }
  
  /**
   * Update Home Settings
   * 
   * Updates security settings and configuration for a home.
   */
  Future<ApiResponse<void>> updateHomeSettings(int homeId, Map<String, dynamic> settings) async {
    final response = await _makeRequest('PUT', '/homes/$homeId/settings', body: settings);
    
    if (response.statusCode == 200) {
      return ApiResponse.success(null, response.statusCode);
    } else {
      final error = json.decode(response.body);
      return ApiResponse.error(error['message'] ?? 'Failed to update settings', response.statusCode);
    }
  }
  
  /**
   * Arm Security System
   * 
   * Arms the home security system with the specified mode.
   */
  Future<ApiResponse<void>> armSecuritySystem(int homeId, String mode) async {
    final response = await _makeRequest('POST', '/homes/$homeId/arm', body: {
      'mode': mode,
    });
    
    if (response.statusCode == 200) {
      return ApiResponse.success(null, response.statusCode);
    } else {
      final error = json.decode(response.body);
      return ApiResponse.error(error['message'] ?? 'Failed to arm security system', response.statusCode);
    }
  }
  
  /**
   * Disarm Security System
   * 
   * Disarms the home security system.
   */
  Future<ApiResponse<void>> disarmSecuritySystem(int homeId) async {
    final response = await _makeRequest('POST', '/homes/$homeId/disarm');
    
    if (response.statusCode == 200) {
      return ApiResponse.success(null, response.statusCode);
    } else {
      final error = json.decode(response.body);
      return ApiResponse.error(error['message'] ?? 'Failed to disarm security system', response.statusCode);
    }
  }

  Future<ApiResponse<bool>> armHomeSecurity(int homeId, String mode) async {
    // Simulate arming home security
    await Future.delayed(Duration(milliseconds: 500));
    return ApiResponse.success(true, 200);
  }

  Future<ApiResponse<bool>> disarmHomeSecurity(int homeId) async {
    // Simulate disarming home security
    await Future.delayed(Duration(milliseconds: 500));
    return ApiResponse.success(true, 200);
  }

  Future<void> saveAuthToken(String token) async {
    final box = Hive.box('authBox');
    await box.put('auth_token', token);
    _authToken = token;
  }
  
  /**
   * Get Home Activities
   * 
   * Retrieves recent activities and events for a home.
   */
  Future<ApiResponse<List<HomeActivity>>> getHomeActivities(int homeId, {int limit = 50}) async {
    final response = await _makeRequest('GET', '/homes/$homeId/activities?limit=$limit');
    
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      final activities = data.map((json) => HomeActivity.fromJson(json)).toList();
      return ApiResponse.success(activities, response.statusCode);
    } else {
      return ApiResponse.error('Failed to load activities', response.statusCode);
    }
  }
  
  /**
   * Get Home Statistics
   * 
   * Retrieves analytics and statistics for a home.
   */
  Future<ApiResponse<Map<String, dynamic>>> getHomeStatistics(int homeId) async {
    final response = await _makeRequest('GET', '/homes/$homeId/statistics');
    
    if (response.statusCode == 200) {
      return ApiResponse.success(json.decode(response.body), response.statusCode);
    } else {
      return ApiResponse.error('Failed to load statistics', response.statusCode);
    }
  }
  
  // ==================== CAMERA MANAGEMENT ====================
  
  /**
   * Get User Cameras
   * 
   * Retrieves all cameras owned by the current user.
   */
  Future<ApiResponse<List<Camera>>> getUserCameras() async {
    try {
      final response = await _makeRequest('POST', '/cameras_user', body: {
        'email': _getCurrentUserEmail(),
      });
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['cameras'] != null) {
          final cameras = (data['cameras'] as List)
              .map((json) => Camera.fromJson(json))
              .toList();
          return ApiResponse.success(cameras, response.statusCode);
        }
        return ApiResponse.error('No cameras found', response.statusCode);
      } else {
        return ApiResponse.error('Failed to load cameras: ${response.statusCode}', response.statusCode);
      }
    } catch (e) {
      return ApiResponse.error('Error loading cameras: $e', 500);
    }
  }

  // NEW: Alias for getCameras to fix build error
  Future<ApiResponse<List<Camera>>> getCameras() async {
    return getUserCameras();
  }

  /**
   * Get Home Cameras
   * 
   * Retrieves all cameras for a specific home.
   */
  Future<ApiResponse<List<Camera>>> getHomeCameras(int homeId) async {
    try {
      final response = await _makeRequest('GET', '/homecameras/$homeId');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['cameras'] != null) {
          final cameras = (data['cameras'] as List)
              .map((json) => Camera.fromJson(json))
              .toList();
          return ApiResponse.success(cameras, response.statusCode);
        }
        return ApiResponse.error('No cameras found for this home', response.statusCode);
      } else {
        return ApiResponse.error('Failed to load home cameras: ${response.statusCode}', response.statusCode);
      }
    } catch (e) {
      return ApiResponse.error('Error loading home cameras: $e', 500);
    }
  }
  
  /**
   * Get Camera Details
   * 
   * Retrieves detailed information about a specific camera.
   */
  Future<ApiResponse<Camera>> getCameraDetails(int cameraId) async {
    final response = await _makeRequest('GET', '/cameras/$cameraId');
    
    if (response.statusCode == 200) {
      return ApiResponse.success(Camera.fromJson(json.decode(response.body)), response.statusCode);
    } else {
      return ApiResponse.error('Failed to load camera details', response.statusCode);
    }
  }
  
  /**
   * Create Camera
   * 
   * Creates a new camera with the provided information.
   */
  Future<ApiResponse<Camera>> createCamera(Map<String, dynamic> cameraData) async {
    final response = await _makeRequest('POST', '/cameras', body: cameraData);
    
    if (response.statusCode == 201) {
      return ApiResponse.success(Camera.fromJson(json.decode(response.body)), response.statusCode);
    } else {
      final error = json.decode(response.body);
      return ApiResponse.error(error['message'] ?? 'Failed to create camera', response.statusCode);
    }
  }
  
  /**
   * Update Camera
   * 
   * Updates an existing camera with new information.
   */
  Future<ApiResponse<Camera>> updateCamera(int cameraId, Map<String, dynamic> cameraData) async {
    final response = await _makeRequest('PUT', '/cameras/$cameraId', body: cameraData);
    
    if (response.statusCode == 200) {
      return ApiResponse.success(Camera.fromJson(json.decode(response.body)), response.statusCode);
    } else {
      final error = json.decode(response.body);
      return ApiResponse.error(error['message'] ?? 'Failed to update camera', response.statusCode);
    }
  }
  
  /**
   * Delete Camera
   * 
   * Deletes a camera and all associated data.
   */
  Future<ApiResponse<void>> deleteCamera(int cameraId) async {
    final response = await _makeRequest('DELETE', '/deletecamera/$cameraId');
    
    if (response.statusCode == 200) {
      return ApiResponse.success(null, response.statusCode);
    } else {
      return ApiResponse.error('Failed to delete camera', response.statusCode);
    }
  }
  
  /**
   * Get Camera Status
   * 
   * Retrieves current status and health information for a camera.
   */
  Future<ApiResponse<Map<String, dynamic>>> getCameraStatus(int cameraId) async {
    final response = await _makeRequest('GET', '/cameras/$cameraId/status');
    
    if (response.statusCode == 200) {
      return ApiResponse.success(json.decode(response.body), response.statusCode);
    } else {
      return ApiResponse.error('Failed to get camera status', response.statusCode);
    }
  }
  
  /**
   * Toggle Camera Recording
   * 
   * Starts or stops recording for a camera.
   */
  Future<ApiResponse<Map<String, dynamic>>> toggleCameraRecording(int cameraId) async {
    final response = await _makeRequest('POST', '/cameras/$cameraId/toggle-recording');
    
    if (response.statusCode == 200) {
      return ApiResponse.success(json.decode(response.body), response.statusCode);
    } else {
      final error = json.decode(response.body);
      return ApiResponse.error(error['message'] ?? 'Failed to toggle recording', response.statusCode);
    }
  }
  
  /**
   * Start Camera Stream
   * 
   * Initiates a video stream for a camera.
   */
  Future<ApiResponse<Map<String, dynamic>>> startCameraStream(int cameraId) async {
    final response = await _makeRequest('POST', '/cameras/$cameraId/start-stream');
    
    if (response.statusCode == 200) {
      return ApiResponse.success(json.decode(response.body), response.statusCode);
    } else {
      final error = json.decode(response.body);
      return ApiResponse.error(error['message'] ?? 'Failed to start stream', response.statusCode);
    }
  }
  
  /**
   * Stop Camera Stream
   * 
   * Stops a video stream for a camera.
   */
  Future<ApiResponse<void>> stopCameraStream(int cameraId) async {
    final response = await _makeRequest('POST', '/cameras/$cameraId/stop-stream');
    
    if (response.statusCode == 200) {
      return ApiResponse.success(null, response.statusCode);
    } else {
      final error = json.decode(response.body);
      return ApiResponse.error(error['message'] ?? 'Failed to stop stream', response.statusCode);
    }
  }
  
  /**
   * Get Camera Settings
   * 
   * Retrieves configuration settings for a camera.
   */
  Future<ApiResponse<Map<String, dynamic>>> getCameraSettings(int cameraId) async {
    final response = await _makeRequest('GET', '/cameras/$cameraId/settings');
    
    if (response.statusCode == 200) {
      return ApiResponse.success(json.decode(response.body), response.statusCode);
    } else {
      return ApiResponse.error('Failed to get camera settings', response.statusCode);
    }
  }
  
  /**
   * Update Camera Settings
   * 
   * Updates configuration settings for a camera.
   */
  Future<ApiResponse<void>> updateCameraSettings(int cameraId, Map<String, dynamic> settings) async {
    final response = await _makeRequest('PUT', '/cameras/$cameraId/settings', body: settings);
    
    if (response.statusCode == 200) {
      return ApiResponse.success(null, response.statusCode);
    } else {
      final error = json.decode(response.body);
      return ApiResponse.error(error['message'] ?? 'Failed to update settings', response.statusCode);
    }
  }
  
  /**
   * Restart Camera
   * 
   * Sends a restart command to a camera.
   */
  Future<ApiResponse<void>> restartCamera(int cameraId) async {
    final response = await _makeRequest('POST', '/cameras/$cameraId/restart');
    
    if (response.statusCode == 200) {
      return ApiResponse.success(null, response.statusCode);
    } else {
      final error = json.decode(response.body);
      return ApiResponse.error(error['message'] ?? 'Failed to restart camera', response.statusCode);
    }
  }
  
  /**
   * Get Camera Activities
   * 
   * Retrieves recent activities and events for a camera.
   */
  Future<ApiResponse<List<CameraActivity>>> getCameraActivities(int cameraId, {int limit = 50}) async {
    final response = await _makeRequest('GET', '/cameras/$cameraId/activities?limit=$limit');
    
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      final activities = data.map((json) => CameraActivity.fromJson(json)).toList();
      return ApiResponse.success(activities, response.statusCode);
    } else {
      return ApiResponse.error('Failed to load activities', response.statusCode);
    }
  }
  
  /**
   * Get Camera Recordings
   * 
   * Retrieves a list of recorded videos for a camera.
   */
  Future<ApiResponse<List<Recording>>> getCameraRecordings(int cameraId, {int limit = 20}) async {
    final response = await _makeRequest('GET', '/cameras/$cameraId/recordings?limit=$limit');
    
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      final recordings = data.map((json) => Recording.fromJson(json)).toList();
      return ApiResponse.success(recordings, response.statusCode);
    } else {
      return ApiResponse.error('Failed to load recordings', response.statusCode);
    }
  }
  
  // ==================== NOTIFICATION MANAGEMENT ====================
  
  /**
   * Register FCM Token
   * 
   * Registers a Firebase Cloud Messaging token for push notifications using email.
   */
  Future<ApiResponse<void>> registerFCMToken(String token) async {
    final box = Hive.box('authBox');
    final user = box.get('user');
    if (user == null || user['email'] == null) {
      return ApiResponse.error('User not authenticated', 401);
    }
    final response = await _makeRequest('POST', '/notifications/register-token', body: {
      'email': user['email'],
      'fcm_token': token,
      'platform': 'android', // or 'ios'
    });
    if (response.statusCode == 200) {
      return ApiResponse.success(null, response.statusCode);
    } else {
      final error = json.decode(response.body);
      return ApiResponse.error(error['message'] ?? 'Failed to register FCM token', response.statusCode);
    }
  }
  
  /**
   * Update Notification Preferences
   * 
   * Updates user notification preferences and settings using email.
   */
  Future<ApiResponse<void>> updateNotificationPreferences(Map<String, dynamic> preferences) async {
    final box = Hive.box('authBox');
    final user = box.get('user');
    if (user == null || user['email'] == null) {
      return ApiResponse.error('User not authenticated', 401);
    }
    final response = await _makeRequest('PUT', '/users/notification-preferences', body: {
      'email': user['email'],
      ...preferences,
    });
    if (response.statusCode == 200) {
      return ApiResponse.success(null, response.statusCode);
    } else {
      final error = json.decode(response.body);
      return ApiResponse.error(error['message'] ?? 'Failed to update preferences', response.statusCode);
    }
  }
  
  // ==================== UTILITY METHODS ====================
  
  /**
   * Check API Health
   * 
   * Performs a health check on the API server.
   */
  Future<bool> checkApiHealth() async {
    try {
      final response = await _makeRequest('GET', '/health');
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
  
  /**
   * Get Server Time
   * 
   * Retrieves the current server time for synchronization.
   */
  Future<ApiResponse<DateTime>> getServerTime() async {
    final response = await _makeRequest('GET', '/time');
    
    if (response.statusCode == 200) {
      // Assuming the API returns a JSON object with a 'time' field
      final data = json.decode(response.body);
      return ApiResponse.success(DateTime.parse(data['time']), response.statusCode);
    } else {
      return ApiResponse.error('Failed to get server time', response.statusCode);
    }
  }
  
  /**
   * Upload File
   * 
   * Uploads a file to the server (for camera images, recordings, etc.).
   */
  Future<ApiResponse<Map<String, dynamic>>> uploadFile(String filePath, String endpoint) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse('$baseUrl$endpoint'));
      request.headers.addAll(_getHeaders());
      request.files.add(await http.MultipartFile.fromPath('file', filePath));
      
      final streamedResponse = await request.send().timeout(_timeout);
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 200) {
        return ApiResponse.success(json.decode(response.body), response.statusCode);
      } else {
        final error = json.decode(response.body);
        return ApiResponse.error(error['message'] ?? 'Failed to upload file', response.statusCode);
      }
    } catch (e) {
      return ApiResponse.error('File upload failed: $e', 500);
    }
  }

  // Add generic HTTP methods for compatibility
  Future<http.Response> get(String endpoint) async {
    return _makeRequest('GET', endpoint);
  }

  Future<http.Response> post(String endpoint, {Map<String, dynamic>? body}) async {
    return _makeRequest('POST', endpoint, body: body);
  }

  Future<http.Response> put(String endpoint, {Map<String, dynamic>? body}) async {
    return _makeRequest('PUT', endpoint, body: body);
  }
  
  /// Triggers a notification via the Node.js signaling server
  static Future<bool> triggerNotification(String cameraCode) async {
    final url = Uri.parse(nodeServerUrl + '/notify');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'camera_code': cameraCode}),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error triggering notification: $e');
      return false;
    }
  }
  
  /**
   * Dispose
   * 
   * Cleans up resources when the service is no longer needed.
   */
  void dispose() {
    _client.close();
  }

  static void init() {}

  String _getCurrentUserEmail() {
    final box = Hive.box('authBox');
    final user = box.get('user');
    return user?['email'] ?? '';
  }
}

/**
 * API Exception Class
 * 
 * Custom exception class for API-related errors with status codes
 * and detailed error messages.
 */
class ApiException implements Exception {
  final String message;
  final int statusCode;
  
  const ApiException(this.message, this.statusCode);
  
  @override
  String toString() => 'ApiException($statusCode): $message';
}

/**
 * API Cache Manager
 * 
 * Simple caching mechanism for API responses to improve performance
 * and reduce network requests.
 */
class ApiCacheManager {
  static final Map<String, CacheEntry> _cache = {};
  static const Duration _defaultTtl = Duration(minutes: 5);
  
  /**
   * Get Cached Data
   * 
   * Retrieves cached data if it exists and hasn't expired.
   */
  static T? get<T>(String key) {
    final entry = _cache[key];
    if (entry != null && !entry.isExpired) {
      return entry.data as T;
    }
    return null;
  }
  
  /**
   * Set Cached Data
   * 
   * Stores data in the cache with an optional TTL.
   */
  static void set<T>(String key, T data, {Duration? ttl}) {
    _cache[key] = CacheEntry(
      data: data,
      expiresAt: DateTime.now().add(ttl ?? _defaultTtl),
    );
  }
  
  /**
   * Clear Cache
   * 
   * Removes all cached data or specific entries.
   */
  static void clear([String? key]) {
    if (key != null) {
      _cache.remove(key);
    } else {
      _cache.clear();
    }
  }
  
  /**
   * Clean Expired Entries
   * 
   * Removes expired cache entries to free up memory.
   */
  static void cleanExpired() {
    _cache.removeWhere((key, entry) => entry.isExpired);
  }
}

/**
 * Cache Entry Class
 * 
 * Represents a single cache entry with data and expiration time.
 */
class CacheEntry {
  final dynamic data;
  final DateTime expiresAt;
  
  CacheEntry({
    required this.data,
    required this.expiresAt,
  });
  
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

abstract class BaseActivity {
  static BaseActivity fromJson(Map<String, dynamic> json) {
    throw UnimplementedError('BaseActivity.fromJson should not be called directly. Use a subclass.');
  }
}


