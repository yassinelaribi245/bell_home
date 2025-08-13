import 'package:bellui/pages/add_camera_page.dart';
import 'package:bellui/pages/add_home_page.dart';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive/hive.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:bellui/services/api_service.dart';
import 'package:bellui/models/models.dart';
import 'package:bellui/utils/utils.dart';
import 'dart:async';

// Import the detail pages
import 'package:bellui/pages/camera_detail_page.dart';
import 'package:bellui/pages/home_detail_page.dart';
import 'package:bellui/pages/login_register_page.dart';
import 'package:bellui/pages/video_call_page.dart';
import 'package:bellui/pages/settings_page.dart';

/**
 * Enhanced Main Dashboard
 * 
 * This is the main dashboard that provides a comprehensive interface for
 * managing multiple cameras and homes. Features include:
 * 
 * - Toggle between Cameras and Homes view
 * - Real-time status monitoring for all cameras
 * - Home management with camera counts
 * - Search and filter functionality
 * - Bottom navigation with quick actions
 * - API integration for data management
 * - Responsive design for different screen sizes
 * 
 * The dashboard serves as the central hub for the entire security system,
 * allowing users to monitor, control, and manage their smart security setup.
 */
class EnhancedMainDashboard extends StatefulWidget {
  const EnhancedMainDashboard({super.key});

  @override
  State<EnhancedMainDashboard> createState() => _EnhancedMainDashboardState();
}

class _EnhancedMainDashboardState extends State<EnhancedMainDashboard>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  
  // Navigation and UI state
  int _selectedIndex = 0; // 0 = Cameras, 1 = Homes
  String _searchQuery = '';
  bool _isLoading = true;
  String? _errorMessage;
  
  // User and authentication
  User? currentUser; // Changed to User object
  
  // Data collections
  List<Camera> _cameras = [];
  List<Home> _homes = [];
  List<Camera> _filteredCameras = [];
  List<Home> _filteredHomes = [];
  
  // Real-time communication
  io.Socket? socket;
  bool isSocketConnected = false;
  Map<String, bool> cameraStatuses = {}; // Track online status of each camera
  String? _lastSocketError;
  String? _pendingCameraCode;
  
  // Notification system
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  
  // Animation controllers
  late AnimationController _refreshController;
  late AnimationController _fabController;
  
  // API service instance
  final ApiService _apiService = ApiService();
  
  // Search controller
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkLoginStatus();
    _initializeAnimations();
    _initializeNotifications();
    _setupSearchListener();
    _addDebugLog('🔗 Initializing persistent socket connection on app open...');
    _initializeSocket(); // Always connect to Node.js server when app opens
    _loadData(); // Automatically load cameras and homes on app open
    _startPeriodicRefresh(); // Start periodic refresh
  }

  void _addDebugLog(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    debugPrint('[Socket] $message');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.resumed:
        _addDebugLog('📱 App resumed - refreshing data');
        _loadData(); // Refresh data when app comes back to foreground
        break;
      case AppLifecycleState.paused:
        _addDebugLog('📱 App paused');
        break;
      case AppLifecycleState.detached:
        _addDebugLog('📱 App detached');
        break;
      case AppLifecycleState.inactive:
        _addDebugLog('📱 App inactive');
        break;
      case AppLifecycleState.hidden:
        _addDebugLog('📱 App hidden');
        break;
    }
  }

  // NEW: Refresh camera data from database
  Future<void> _refreshCameraData() async {
    _addDebugLog('🔄 Refreshing camera data from database...');
    
    try {
      setState(() {
        _isLoading = true;
      });

      // Reload cameras from API
      final cameraResponse = await _apiService.getCameras();
      if (cameraResponse.success) {
        setState(() {
          _cameras = cameraResponse.data!;
          _filteredCameras = _cameras;
        });
        _addDebugLog('✅ Camera data refreshed from database');
      } else {
        _addDebugLog('❌ Failed to refresh camera data: ${cameraResponse.error}');
      }

      // Reload homes from API
      final homeResponse = await _apiService.getHomes();
      if (homeResponse.success) {
        setState(() {
          _homes = homeResponse.data!;
          _filteredHomes = _homes;
        });
        _addDebugLog('✅ Home data refreshed from database');
      } else {
        _addDebugLog('❌ Failed to refresh home data: ${homeResponse.error}');
      }

    } catch (e) {
      _addDebugLog('❌ Error refreshing data: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Timer? _connectionStatusTimer;

  void _startConnectionStatusTimer() {
    _connectionStatusTimer?.cancel();
    _connectionStatusTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (socket == null) {
        print('[Socket] Not initialized');
      } else if (socket!.connected) {
        print('[Socket] ✅ Connected to Node.js server at: ${ApiService.nodeServerUrl}');
        print('[Socket] 📱 Mobile app is ready for calls');
      } else {
        print('[Socket] ❌ Not connected to Node.js server at: ${ApiService.nodeServerUrl}');
        if (_lastSocketError != null && _lastSocketError!.isNotEmpty) {
          print('[Socket] Last error: ${_lastSocketError}');
        } else {
          print('[Socket] Last error: No error reported');
        }
      }
    });
  }

  /**
   * Check Login Status
   * 
   * Checks if a user is logged in. If not, navigates to the login page.
   */
  void _checkLoginStatus() async {
    final box = Hive.box('authBox');
    final token = box.get('auth_token');

    if (token == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const LoginRegisterPage()),
            (route) => false,
          );
        }
      });
    } else {
      _loadUserData();
      _loadData();
      // _initializeSocket(); // Moved to initState
      
      // Check if there's a pending camera code from notification
      if (_pendingCameraCode != null) {
        print('📱 Found pending camera code after login: $_pendingCameraCode');
        // Wait a bit for socket to connect and data to load
        Future.delayed(const Duration(seconds: 2), () {
          _ensureSocketConnectionAndJoinRoom(_pendingCameraCode!);
        });
      }
    }
  }

  /**
   * Initialize Animation Controllers
   * 
   * Sets up animation controllers for smooth UI transitions
   * and interactive elements like refresh and floating action buttons.
   */
  void _initializeAnimations() {
    _refreshController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    
    _fabController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _fabController.forward(); // Show FAB initially
  }

  /**
   * Initialize Notifications
   * 
   * Sets up local notifications for camera alerts and system notifications.
   */
  void _initializeNotifications() {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    
    flutterLocalNotificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        _handleNotificationTap(response.payload ?? '');
      },
    );
    
    _setupFirebaseMessaging();
  }

  /**
   * Setup Firebase Messaging
   * 
   * Configures Firebase push notifications for real-time alerts
   * from cameras and system events.
   */
  void _setupFirebaseMessaging() async {
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _handleIncomingNotification(message);
    });

    // Handle background message taps
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleNotificationTap(message.data['camera_code'] ?? '');
    });
    
    // Handle initial message when app is opened from notification
    FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        final cameraCode = message.data['camera_code'] ?? '';
        if (cameraCode.isNotEmpty) {
          print('📱 App opened from notification for camera: $cameraCode');
          
          // Store the camera code for later processing
          _pendingCameraCode = cameraCode;
          
          // Ensure socket is connected and join room
          _ensureSocketConnectionAndJoinRoom(cameraCode);
        }
      }
    });
  }

  /**
   * Ensure socket connection and join room
   * 
   * Makes sure the socket is connected and joins the specific camera room
   * when the app is opened from a notification.
   */
  void _ensureSocketConnectionAndJoinRoom(String cameraCode) async {
    print('🔗 Ensuring socket connection for camera: $cameraCode');
    
    // Ensure socket is ready
    final socketReady = await _ensureSocketReady();
    
    if (socketReady) {
      // Join the room once socket is connected
      print('📱 Joining room for camera: $cameraCode');
      socket!.emit('join_room', {
        'room': cameraCode,
        'client_type': 'mobile',
      });
      
      // Wait a bit for the join to complete
      await Future.delayed(const Duration(milliseconds: 1000));
      
      // Now try to handle the notification tap
      _handleNotificationTap(cameraCode);
    } else {
      print('❌ Failed to connect socket for camera: $cameraCode');
      // Store for later retry
      _pendingCameraCode = cameraCode;
      
      // Try again after a delay
      Future.delayed(const Duration(seconds: 3), () {
        if (_pendingCameraCode == cameraCode) {
          print('🔄 Retrying socket connection for camera: $cameraCode');
          _ensureSocketConnectionAndJoinRoom(cameraCode);
        }
      });
    }
  }

  /**
   * Handle Incoming Notification
   * 
   * Processes incoming Firebase notifications and displays appropriate
   * local notifications based on the message type.
   */
  void _handleIncomingNotification(RemoteMessage message) {
    final data = message.data;
    final notification = message.notification;
    
    if (notification != null) {
      flutterLocalNotificationsPlugin.show(
        notification.hashCode,
        notification.title,
        notification.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'security_channel',
            'Security Notifications',
            channelDescription: 'Notifications for security system events',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
        ),
        payload: data['camera_code'],
      );
    }
    
    // Handle different notification types
    switch (data['type']) {
      case 'camera_alert':
        _handleCameraAlert(data);
        break;
      case 'motion_detected':
        _handleMotionDetection(data);
        break;
      case 'camera_offline':
        _handleCameraOffline(data);
        break;
    }
  }

  /**
   * Handle Notification Tap
   * 
   * Processes notification taps and navigates to appropriate screens
   * or shows relevant dialogs.
   */
  void _handleNotificationTap(String cameraCode) {
    print('📱 Notification tapped with cameraCode: $cameraCode');
    if (cameraCode.isNotEmpty) {
      // Ensure we're in the correct room
      if (socket != null && socket!.connected) {
        print('📱 Joining room for camera: $cameraCode');
        socket!.emit('join_room', {
          'room': cameraCode,
          'client_type': 'mobile',
        });
      } else {
        print('❌ Socket not connected, trying to connect...');
        _ensureSocketConnectionAndJoinRoom(cameraCode);
        return;
      }
      
      // Try to find the camera in the loaded list
      final camera = _cameras.firstWhere(
        (c) => c.camCode == cameraCode,
        orElse: () => Camera.empty(),
      );
      
      print('📹 Camera found: ${camera.id != null ? 'YES' : 'NO'} - ${camera.name ?? 'unknown'}');
      
      if (camera.id != null) {
        // Camera found, show dialog
        _showJoinCallDialog(camera);
      } else {
        // Camera not found, store for later and try to load cameras
        print('📹 Camera not found, storing pending cameraCode: $cameraCode');
        _pendingCameraCode = cameraCode;
        
        // Try to load cameras if not already loaded
        if (_cameras.isEmpty) {
          print('📹 Loading cameras...');
          _loadCameras().then((_) {
            // After loading, try to find the camera again
            final loadedCamera = _cameras.firstWhere(
              (c) => c.camCode == cameraCode,
              orElse: () => Camera.empty(),
            );
            
            if (loadedCamera.id != null) {
              print('📹 Camera found after loading: ${loadedCamera.name}');
              _showJoinCallDialog(loadedCamera);
              _pendingCameraCode = null;
            } else {
              print('❌ Camera still not found after loading cameras');
            }
          });
        }
      }
    }
  }

  void _showJoinCallDialog(Camera camera) {
    print('📱 Showing join call dialog for camera: ${camera.name ?? 'unknown'}');
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Incoming Call'),
        content: Text('Do you want to join the call from ${camera.name} (Code: ${camera.camCode})?'),
        actions: [
          TextButton(
            onPressed: () {
              // Ensure socket is connected and send refused response
              _ensureSocketAndSendResponse(camera.camCode, 'refused');
              Navigator.of(context).pop();
            },
            child: const Text('Refuse'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              // Ensure socket is connected and send accepted response
              _ensureSocketAndSendResponse(camera.camCode, 'accepted');
              _startCameraStream(camera);
            },
            child: const Text('Accept'),
          ),
        ],
      ),
    );
  }

  /**
   * Ensure socket is connected and send camera response
   */
  void _ensureSocketAndSendResponse(String cameraCode, String response) async {
    print('📱 Ensuring socket connection for camera response: $response');
    
    // Ensure socket is ready
    final socketReady = await _ensureSocketReady();
    
    if (socketReady) {
      // Send the response if socket is connected
      print('📱 Sending camera_response: $response for room: $cameraCode');
      socket!.emit('camera_response', {
        'room': cameraCode,
        'response': response,
      });
    } else {
      print('❌ Failed to connect socket for camera response: $response');
      // Try one more time with a delay
      Future.delayed(const Duration(seconds: 2), () async {
        final retryReady = await _ensureSocketReady();
        if (retryReady) {
          print('📱 Retry sending camera_response: $response for room: $cameraCode');
          socket!.emit('camera_response', {
            'room': cameraCode,
            'response': response,
          });
        } else {
          print('❌ Still failed to send camera_response: $response');
        }
      });
    }
  }

  /**
   * Load User Data
   * 
   * Retrieves current user information from local storage
   * for personalization and API authentication.
   */
  void _loadUserData() {
    final box = Hive.box('authBox');
    final userData = box.get('user');
    
    if (userData != null) {
      setState(() {
        currentUser = User.fromJson(userData); // Convert to User object
      });
    }
  }

  /**
   * Load Data
   * 
   * Fetches cameras and homes data from the API and updates the UI.
   * Handles loading states and error conditions.
   */
  Future<void> _loadData() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await Future.wait([
        _loadCameras(),
        _loadHomes(),
      ]);
      
      _applyFilters(); // Apply current search filters
      
    } catch (e) {
      debugPrint('Failed to load data: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load data: $e';
        });
        UIUtils.showSnackBar(context, 'Failed to load data: $e', backgroundColor: Colors.red);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /**
   * Load Cameras
   * 
   * Fetches all cameras for the current user from the API.
   * Updates camera status information and sorts by priority.
   */
  Future<void> _loadCameras() async {
    // No need to check for user id, as we use email for API requests
    
    try {
      final response = await _apiService.getUserCameras();
      
      if (response.success) {
        if (mounted) {
          setState(() {
            _cameras = response.data!;
            // Sort cameras by status (online first) and then by name
            _cameras.sort((a, b) {
              if (a.isOnline != b.isOnline) {
                return b.isOnline ? -1 : 1; // Online cameras first
              }
              return a.name.compareTo(b.name);
            });
          });
          // Check for pending camera code after cameras are loaded
          if (_pendingCameraCode != null) {
            final camera = _cameras.firstWhere(
              (c) => c.camCode == _pendingCameraCode,
              orElse: () => Camera.empty(),
            );
            if (camera.id != null) {
              print('Pending camera found after load: ' + camera.camCode);
              _showJoinCallDialog(camera);
              _pendingCameraCode = null;
            }
          }
        }
      } else {
        throw Exception('Failed to load cameras: ${response.error}');
      }
    } catch (e) {
      debugPrint('Error loading cameras: $e');
      // Use mock data for development/testing
      _loadMockCameras();
    }
  }

  /**
   * Load Homes
   * 
   * Fetches all homes for the current user from the API.
   * Includes camera count information for each home.
   */
  Future<void> _loadHomes() async {
    // No need to check for user id, as we use email for API requests
    
    try {
      final response = await _apiService.getUserHomes();
      
      if (response.success) {
        if (mounted) {
          setState(() {
            _homes = response.data!;
            // Sort homes by name
            _homes.sort((a, b) => a.name.compareTo(b.name));
          });
        }
      } else {
        throw Exception('Failed to load homes: ${response.error}');
      }
    } catch (e) {
      debugPrint('Error loading homes: $e');
      // Use mock data for development/testing
      _loadMockHomes();
    }
  }

  /**
   * Load Mock Cameras (for development/testing)
   * 
   * Provides sample camera data when API is not available.
   * Useful for UI development and testing.
   */
  void _loadMockCameras() {
    if (mounted) {
      setState(() {
        _cameras = [];
      });
    }
  }

  /**
   * Load Mock Homes (for development/testing)
   * 
   * Provides sample home data when API is not available.
   */
  void _loadMockHomes() {
    if (mounted) {
      setState(() {
        _homes = [
          Home(
            id: 1,
            name: 'Main House',
            address: '123 Main Street',
            superficie: 150.0,
            numCameras: 2,
            idUser: 1,
            isActive: true,
            status: 'active',
          ),
          Home(
            id: 2,
            name: 'Garage Building',
            address: '123 Main Street (Garage)',
            superficie: 50.0,
            numCameras: 1,
            idUser: 1,
            isActive: true,
            status: 'active',
          ),
        ];
      });
    }
  }

  /**
   * Ensure socket is ready
   * 
   * Makes sure the socket is connected and ready for communication.
   * Returns true if socket is ready, false otherwise.
   */
  Future<bool> _ensureSocketReady() async {
    // If socket is not initialized, initialize it
    if (socket == null) {
      print('📡 Socket not initialized, initializing...');
      _initializeSocket();
      
      // Wait for socket to connect
      int attempts = 0;
      while ((socket == null || !socket!.connected) && attempts < 10) {
        await Future.delayed(const Duration(milliseconds: 500));
        attempts++;
        print('📡 Waiting for socket connection... attempt $attempts');
      }
    }
    
    // If socket is still not connected, try to reconnect
    if (socket != null && !socket!.connected) {
      print('📡 Socket not connected, trying to reconnect...');
      socket!.connect();
      
      // Wait for reconnection
      int attempts = 0;
      while (!socket!.connected && attempts < 10) {
        await Future.delayed(const Duration(milliseconds: 500));
        attempts++;
        print('📡 Waiting for socket reconnection... attempt $attempts');
      }
    }
    
    final isReady = socket != null && socket!.connected;
    print('📡 Socket ready: $isReady');
    return isReady;
  }

  /**
   * Initialize Socket Connection
   * 
   * Establishes real-time connection for camera status updates
   * and WebRTC signaling.
   */
  void _initializeSocket() {
    try {
      _addDebugLog('📡 Initializing socket connection to: ${ApiService.nodeServerUrl}');
      
      socket = io.io(ApiService.nodeServerUrl, <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': false,
        'timeout': 20000,
      });

      socket!.onConnect((_) {
        _addDebugLog('✅ Connected to Node.js server at: ${ApiService.nodeServerUrl}');
        setState(() {
          isSocketConnected = true;
          _lastSocketError = null;
        });
        
        // Start connection status timer
        _startConnectionStatusTimer();
      });

      socket!.onConnectError((err) {
        _addDebugLog('❌ Socket connect error: $err');
        setState(() {
          isSocketConnected = false;
          _lastSocketError = err.toString();
        });
      });

      socket!.onError((err) {
        _addDebugLog('❌ Socket error: $err');
        setState(() {
          _lastSocketError = err.toString();
        });
      });

      socket!.onDisconnect((reason) {
        _addDebugLog('⚠️ Disconnected from Node.js server: $reason');
        setState(() {
          isSocketConnected = false;
        });
      });

      // Listen for room joining confirmation
      socket!.on('joined_room', (data) {
        _addDebugLog('📱 Successfully joined room: ${data['room']}');
        _addDebugLog('📱 Camera available: ${data['camera_available']}');
        _addDebugLog('📱 Mobile available: ${data['mobile_available']}');
      });
      
      // Listen for camera status updates
      socket!.on('camera_status_update', (data) {
        _handleCameraStatusUpdate(data);
      });

      socket!.connect();
    } catch (e) {
      _addDebugLog('❌ Socket initialization error: $e');
      setState(() {
        _lastSocketError = e.toString();
      });
    }
  }

  /**
   * Handle Camera Status Update
   * 
   * Processes real-time camera status updates from the socket server
   * and updates the UI accordingly.
   */
  void _handleCameraStatusUpdate(dynamic data) {
    final cameraCode = data['camera_code'];
    final isOnline = data['is_online'] ?? false;
    final isRecording = data['is_recording'] ?? false;
    final isStreaming = data['is_streaming'] ?? false;
    
    if (mounted) {
      setState(() {
        cameraStatuses[cameraCode] = isOnline;
        
        // Update camera in the list
        final cameraIndex = _cameras.indexWhere((c) => c.camCode == cameraCode);
        if (cameraIndex != -1) {
          _cameras[cameraIndex] = _cameras[cameraIndex].copyWith(
            isOnline: isOnline,
            isRecording: isRecording,
            isStreaming: isStreaming,
          );
        }
      });
    }
    
    _applyFilters(); // Refresh filtered lists
  }

  /**
   * Setup Search Listener
   * 
   * Configures the search functionality to filter cameras and homes
   * as the user types in the search field.
   */
  void _setupSearchListener() {
    _searchController.addListener(() {
      if (mounted) {
        setState(() {
          _searchQuery = _searchController.text;
        });
      }
      _applyFilters();
    });
  }

  /**
   * Apply Filters
   * 
   * Filters cameras and homes based on the current search query
   * and updates the filtered lists for display.
   */
  void _applyFilters() {
    if (mounted) {
      setState(() {
        if (_searchQuery.isEmpty) {
          _filteredCameras = List.from(_cameras);
          _filteredHomes = List.from(_homes);
        } else {
          final query = _searchQuery.toLowerCase();
          
          _filteredCameras = _cameras.where((camera) {
            return camera.homeId.toString().toLowerCase().contains(query);
          }).toList();
          
          _filteredHomes = _homes.where((home) {
            return home.id.toString().toLowerCase().contains(query);
          }).toList();
        }
      });
    }
  }


  /**
   * Handle Camera Alert
   * 
   * Processes camera alert notifications and updates the UI
   * to show alert status.
   */
  void _handleCameraAlert(Map<String, dynamic> data) {
    final cameraCode = data['camera_code'];
    // Update UI to show alert status
    // You can add visual indicators, sounds, or other alert handling here
    debugPrint('Camera alert from $cameraCode');
    if (mounted) {
      UIUtils.showSnackBar(context, 'Camera Alert: $cameraCode', backgroundColor: Colors.orange);
    }
  }

  /**
   * Handle Motion Detection
   * 
   * Processes motion detection events and can trigger
   * recordings or other automated responses.
   */
  void _handleMotionDetection(Map<String, dynamic> data) {
    final cameraCode = data['camera_code'];
    // Handle motion detection event
    debugPrint('Motion detected on $cameraCode');
    if (mounted) {
      UIUtils.showSnackBar(context, 'Motion Detected: $cameraCode', backgroundColor: Colors.orange);
    }
  }

  /**
   * Handle Camera Offline
   * 
   * Processes camera offline notifications and updates
   * the camera status in the UI.
   */
  void _handleCameraOffline(Map<String, dynamic> data) {
    final cameraCode = data['camera_code'];
    if (mounted) {
      setState(() {
        cameraStatuses[cameraCode] = false;
        
        final cameraIndex = _cameras.indexWhere((c) => c.camCode == cameraCode);
        if (cameraIndex != -1) {
          _cameras[cameraIndex] = _cameras[cameraIndex].copyWith(isOnline: false);
        }
      });
    }
    _applyFilters();
    if (mounted) {
      UIUtils.showSnackBar(context, 'Camera Offline: $cameraCode', backgroundColor: Colors.red);
    }
  }

  /**
   * Navigate to Camera Detail
   * 
   * Opens the detailed view for a specific camera with
   * streaming controls and settings.
   */
  void _navigateToCameraDetail(Camera camera) {
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CameraDetailPage(camera: camera),
        ),
      ).then((_) {
        // Refresh data when returning from detail page
        _loadData();
      });
    }
  }

  /**
   * Navigate to Home Detail
   * 
   * Opens the detailed view for a specific home with
   * camera management and settings.
   */
  void _navigateToHomeDetail(Home home) {
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => HomeDetailPage(home: home),
        ),
      ).then((_) {
        // Refresh data when returning from detail page
        _loadData();
      });
    }
  }

  /**
   * Start Camera Stream
   * 
   * Initiates a video call with the specified camera
   * and navigates to the video call page.
   */
  void _startCameraStream(Camera camera) {
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VideoCallPage(
            roomId: camera.camCode,
            cameraCode: camera.camCode,
            camera: camera,
            existingSocket: socket, // Pass the existing socket
          ),
        ),
      );
    }
  }

  /**
   * Toggle Camera Recording
   * 
   * Starts or stops recording for the specified camera
   * via API call and updates the UI.
   */
  Future<void> _toggleCameraRecording(Camera camera) async {
    try {
      final response = await _apiService.toggleCameraRecording(camera.id!); // Using ApiService method
      
      if (response.success) {
        // Update local state
        if (mounted) {
          setState(() {
            final index = _cameras.indexWhere((c) => c.id == camera.id);
            if (index != -1) {
              _cameras[index] = _cameras[index].copyWith(
                isRecording: !camera.isRecording,
              );
            }
          });
        }
        _applyFilters();
        
        if (mounted) {
          UIUtils.showSnackBar(
            context,
            camera.isRecording ? 'Recording stopped' : 'Recording started',
            backgroundColor: Colors.green,
          );
        }
      } else {
        throw Exception('Failed to toggle recording: ${response.error}');
      }
    } catch (e) {
      debugPrint('Error toggling recording: $e');
      if (mounted) {
        UIUtils.showSnackBar(context, 'Error: $e', backgroundColor: Colors.red);
      }
    }
  }

  /**
   * Refresh Data
   * 
   * Refreshes both cameras and homes data from the API
   * and updates the UI with the latest information.
   */
  Future<void> _refreshData() async {
    _addDebugLog('🔄 Manual refresh triggered');
    await _refreshCameraData();
  }

  // NEW: Periodic refresh to keep UI updated with database changes
  void _startPeriodicRefresh() {
    Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted && !_isLoading) {
        _addDebugLog('🔄 Periodic refresh triggered');
        _refreshCameraData();
      }
    });
  }

  /**
   * Logout User
   * 
   * Logs out the current user and navigates to the login screen.
   */
  Future<void> _logout() async {
    // Disconnect socket
    socket?.disconnect();
    
    // Clear stored data
    await _apiService.logout();
    
    // Navigate to login
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginRegisterPage()),
        (route) => false,
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshController.dispose();
    _fabController.dispose();
    _searchController.dispose();
    socket?.disconnect();
    _connectionStatusTimer?.cancel(); // Cancel timer
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: _buildBody(),
      bottomNavigationBar: _buildBottomNavigation(),
      floatingActionButton: _buildFloatingActionButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  /**
   * Build App Bar
   * 
   * Creates the top app bar with title, search, and menu options.
   */
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Text(_selectedIndex == 0 ? 'Cameras' : 'Homes'),
      backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
      foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
      elevation: 2,
      actions: [
        // Connection status indicator
        Icon(
          isSocketConnected ? Icons.wifi : Icons.wifi_off,
          color: isSocketConnected ? Colors.green : Colors.red,
          size: 20,
        ),
        const SizedBox(width: 8),
        // Refresh button
        IconButton(
          icon: RotationTransition(
            turns: _refreshController,
            child: const Icon(Icons.refresh),
          ),
          onPressed: _refreshData,
        ),
        // Menu button
        PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'settings':
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SettingsPage()),
                );
                break;
              case 'logout':
                _logout();
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'settings',
              child: Row(
                children: [
                  Icon(Icons.settings),
                  SizedBox(width: 8),
                  Text('Settings'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'logout',
              child: Row(
                children: [
                  const Icon(Icons.logout),
                  const SizedBox(width: 8),
                  Text('Logout ${currentUser?.nom ?? ''}'), // Use currentUser.nom
                ],
              ),
            ),
          ],
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: _selectedIndex == 0 ? 'Search cameras...' : 'Search homes...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(25),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /**
   * Build Body
   * 
   * Creates the main content area with loading states,
   * error handling, and data display.
   */
  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(_errorMessage!),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadData,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return _selectedIndex == 0 ? _buildCamerasView() : _buildHomesView();
  }

  /**
   * Build Cameras View
   * 
   * Creates the cameras list view with status indicators,
   * controls, and search functionality.
   */
  Widget _buildCamerasView() {
    if (_filteredCameras.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.videocam_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isEmpty ? 'No cameras found' : 'No cameras match your search',
              style: const TextStyle(fontSize: 18, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshData,
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: _filteredCameras.length,
        itemBuilder: (context, index) {
          final camera = _filteredCameras[index];
          return _buildCameraCard(camera);
        },
      ),
    );
  }

  /**
   * Build Camera Card
   * 
   * Creates an individual camera card with status, controls,
   * and quick action buttons.
   */
  Widget _buildCameraCard(Camera camera) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      elevation: 2,
      child: InkWell(
        onTap: () => _navigateToCameraDetail(camera),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Camera header with name and status
              Row(
                children: [
                  Icon(
                    Icons.videocam,
                    color: camera.isOnline ? Colors.green : Colors.red,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          camera.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Camera Code: ${camera.camCode}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.blueGrey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          camera.locationDescription,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Camera status - simplified to show only activity
              Row(
                children: [
                  Text(
                    'Status: ${camera.isActive ? 'Active' : 'Inactive'}',
                    style: TextStyle(
                      color: camera.isActive ? Colors.green : Colors.red,
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Last updated indicator
              Row(
                children: [
                  Icon(
                    Icons.access_time,
                    size: 12,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Updated: ${_formatLastUpdated(camera.updatedAt)}',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const Spacer(),
                  // Camera activity indicator
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: camera.isActive ? Colors.green : Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Home: ${camera.homeId}',
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /**
   * Build Homes View
   * 
   * Creates the homes list view with camera counts,
   * status information, and management options.
   */
  Widget _buildHomesView() {
    if (_filteredHomes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.home, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isEmpty ? 'No homes found' : 'No homes match your search',
              style: const TextStyle(fontSize: 18, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshData,
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: _filteredHomes.length,
        itemBuilder: (context, index) {
          final home = _filteredHomes[index];
          return _buildHomeCard(home);
        },
      ),
    );
  }

  /**
   * Build Home Card
   * 
   * Creates an individual home card with camera information,
   * status, and management options.
   */
  Widget _buildHomeCard(Home home) {
    // Get cameras for this home
    final homeCameras = _cameras.where((c) => c.homeId == home.id).toList();
    final onlineCameras = homeCameras.where((c) => c.isOnline).length;
    
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      elevation: 2,
      child: InkWell(
        onTap: () => _navigateToHomeDetail(home),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Home header
              Row(
                children: [
                  Icon(
                    Icons.home,
                    color: home.isActive ? Colors.blue : Colors.grey,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          home.name == 'Unnamed Home' ? 'Home ${home.id}' : home.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          home.address,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Status indicator
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: home.isActive ? Colors.green : Colors.grey,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      home.status.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Camera statistics
              Row(
                children: [
                  Icon(Icons.videocam, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    '$onlineCameras/${home.numCameras} cameras online',
                    style: TextStyle(
                      color: onlineCameras == home.numCameras ? Colors.green : Colors.orange,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // View cameras button
                  ElevatedButton.icon(
                    onPressed: () {
                      if (mounted) {
                        setState(() {
                          _selectedIndex = 0; // Switch to cameras view
                          _searchController.text = home.id.toString(); // Filter by home ID
                        });
                      }
                    },
                    icon: const Icon(Icons.videocam, size: 16),
                    label: const Text('Cameras'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(100, 32),
                    ),
                  ),
                  // Details button
                  OutlinedButton.icon(
                    onPressed: () => _navigateToHomeDetail(home),
                    icon: const Icon(Icons.info, size: 16),
                    label: const Text('Details'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(100, 32),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /**
   * Build Bottom Navigation
   * 
   * Creates the bottom navigation bar for switching between
   * cameras and homes views.
   */
  Widget _buildBottomNavigation() {
    return BottomAppBar(
      shape: const CircularNotchedRectangle(),
      notchMargin: 6.0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // Cameras tab
          InkWell(
            onTap: () {
              if (mounted) {
                setState(() {
                  _selectedIndex = 0;
                });
              }
            },
            child: SizedBox(
              height: kBottomNavigationBarHeight,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.videocam,
                      color: _selectedIndex == 0 ? Colors.blue : Colors.grey,
                      size: 24,
                    ),
                    Text(
                      'Cameras',
                      style: TextStyle(
                        color: _selectedIndex == 0 ? Colors.blue : Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 40), // Space for FAB
          // Homes tab
          InkWell(
            onTap: () {
              if (mounted) {
                setState(() {
                  _selectedIndex = 1;
                });
              }
            },
            child: SizedBox(
              height: kBottomNavigationBarHeight,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.home,
                      color: _selectedIndex == 1 ? Colors.blue : Colors.grey,
                      size: 24,
                    ),
                    Text(
                      'Homes',
                      style: TextStyle(
                        color: _selectedIndex == 1 ? Colors.blue : Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /**
   * Build Floating Action Button
   * 
   * Creates the central floating action button for quick actions
   * like adding new cameras or homes.
   */
  Widget _buildFloatingActionButton() {
    return ScaleTransition(
      scale: _fabController,
      child: FloatingActionButton(
        onPressed: () {
          // Show options for adding new camera or home
          showModalBottomSheet(
            context: context,
            builder: (context) => Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.add_a_photo),
                    title: const Text('Add Camera'),
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => AddCameraPage()));
                      // Navigate to add camera page
                      if (mounted) {
                        UIUtils.showSnackBar(context, 'Add Camera feature coming soon!', backgroundColor: Colors.blue);
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.add_home),
                    title: const Text('Add Home'),
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => AddHomePage()));
                      // Navigate to add home page
                      if (mounted) {
                        UIUtils.showSnackBar(context, 'Add Home feature coming soon!', backgroundColor: Colors.blue);
                      }
                    },
                  ),
                ],
              ),
            ),
          );
        },
        backgroundColor: Theme.of(context).floatingActionButtonTheme.backgroundColor,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Color _getHealthColor(String healthStatus) {
    switch (healthStatus) {
      case 'healthy':
        return Colors.green;
      case 'warning':
        return Colors.orange;
      case 'critical':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _formatLastUpdated(DateTime? updatedAt) {
    if (updatedAt == null) {
      return 'Never';
    }
    final now = DateTime.now();
    final difference = now.difference(updatedAt);

    if (difference.inSeconds < 60) {
      return '${difference.inSeconds}s ago';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }
}


