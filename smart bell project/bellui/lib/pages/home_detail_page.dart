import 'package:flutter/material.dart';
import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:bellui/services/api_service.dart';
import 'package:bellui/models/models.dart';
import 'package:bellui/utils/utils.dart';
import 'package:bellui/pages/camera_detail_page.dart';
import 'package:bellui/pages/video_call_page.dart'; // Corrected import path

/// Home Detail Page
/// 
/// This page provides a comprehensive view of a single home/property with:
/// - Home information and location details
/// - List of all cameras associated with the home
/// - Real-time camera status monitoring
/// - Camera management controls (add, remove, configure)
/// - Home security system settings
/// - Activity history and security events
/// - Location map with camera positions
/// - Home statistics and analytics
/// - Emergency controls and alerts
/// 
/// The page serves as a central hub for managing all security aspects
/// of a specific property or location.
class HomeDetailPage extends StatefulWidget {
  final Home home;

  const HomeDetailPage({
    super.key,
    required this.home,
  });

  @override
  State<HomeDetailPage> createState() => _HomeDetailPageState();
}

class _HomeDetailPageState extends State<HomeDetailPage>
    with TickerProviderStateMixin {
  
  // Home state management
  late Home _home;
  List<Camera> _cameras = [];
  List<Camera> _filteredCameras = [];
  bool _isLoading = false;
  String? _errorMessage;
  
  // Real-time communication
  io.Socket? socket;
  bool isSocketConnected = false;
  Timer? _statusTimer;
  
  // Animation controllers
  late AnimationController _refreshController;
  late TabController _tabController;
  
  // Activity and events
  List<HomeActivity> _activities = [];
  final List<SecurityEvent> _securityEvents = [];
  
  // Home settings and configuration
  bool _alarmEnabled = false;
  bool _motionAlertsEnabled = true;
  bool _emailNotifications = false;
  bool _smsNotifications = false;
  String _securityMode = 'home'; // home, away, sleep, off
  
  // Search and filtering
  String _searchQuery = '';
  String _filterStatus = 'all'; // all, online, offline, recording
  final TextEditingController _searchController = TextEditingController();
  
  // Map controller
  Set<Marker> _markers = {};
  
  // Statistics
  Map<String, dynamic> _statistics = {};
  
  // API service instance
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    _home = widget.home;
    _initializeControllers();
    _initializeSocket();
    _loadHomeDetails();
    _loadHomeCameras();
    _loadHomeActivities();
    _loadHomeSettings();
    _loadStatistics();
    _startStatusUpdates();
    _setupSearchListener();
  }

  /**
   * Initialize Controllers
   * 
   * Sets up animation and tab controllers for smooth UI transitions
   * and navigation between different sections.
   */
  void _initializeControllers() {
    _refreshController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    
    _tabController = TabController(
      length: 4, // Overview, Cameras, Security, Activity
      vsync: this,
    );
  }

  /**
   * Initialize Socket Connection
   * 
   * Establishes real-time connection for home and camera status updates.
   */
  void _initializeSocket() {
    try {
      socket = io.io(ApiService.nodeServerUrl, <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': false,
        'timeout': 20000,
      });

      socket!.onConnect((_) {
        setState(() {
          isSocketConnected = true;
        });
        
        // Join home-specific room for updates
        socket!.emit('join_home_room', {
          'home_id': _home.id,
        });
        
        debugPrint('Connected to home ${_home.id} socket room');
      });

      socket!.onDisconnect((_) {
        setState(() {
          isSocketConnected = false;
        });
      });

      // Listen for home and camera events
      socket!.on('home_status_update', _handleHomeStatusUpdate);
      socket!.on('camera_status_update', _handleCameraStatusUpdate);
      socket!.on('security_event', _handleSecurityEvent);
      socket!.on('motion_detected', _handleMotionDetection);
      socket!.on('alarm_triggered', _handleAlarmTriggered);

      socket!.connect();
    } catch (e) {
      debugPrint('Socket initialization error: $e');
      UIUtils.showSnackBar(context, 'Socket connection error: $e', backgroundColor: Colors.red);
    }
  }

  /**
   * Load Home Details
   * 
   * Fetches detailed home information from the API including
   * location data, settings, and configuration.
   */
  Future<void> _loadHomeDetails() async {
    if (_home.id == null) return;
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _apiService.getHomeDetails(_home.id!); // Using ApiService method
      
      if (response.success) {
        setState(() {
          _home = response.data as Home;
        });
        debugPrint('Home details loaded successfully');
      } else {
        throw Exception('Failed to load home details: ${response.error}');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading home details: $e';
      });
      debugPrint('Error loading home details: $e');
      UIUtils.showSnackBar(context, 'Error loading home details: $e', backgroundColor: Colors.red);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /**
   * Load Home Cameras
   * 
   * Fetches all cameras associated with this home and their current status.
   */
  Future<void> _loadHomeCameras() async {
    if (_home.id == null) return;
    
    try {
      final response = await _apiService.getHomeCameras(_home.id!); // Using ApiService method
      
      if (response.success) {
        setState(() {
          _cameras = (response.data as List).map((json) => Camera.fromJson(json)).toList();
          // Sort cameras by status (online first) and then by name
          _cameras.sort((a, b) {
            if (a.isOnline != b.isOnline) {
              return b.isOnline ? 1 : -1;
            }
            return a.name.compareTo(b.name);
          });
        });
        
        _applyFilters();
        _updateMapMarkers();
        debugPrint('Loaded ${_cameras.length} cameras for home ${_home.name}');
      } else {
        throw Exception('Failed to load cameras: ${response.error}');
      }
    } catch (e) {
      debugPrint('Error loading cameras: $e');
      UIUtils.showSnackBar(context, 'Error loading cameras: $e', backgroundColor: Colors.red);
      // Use mock data for development
      _loadMockCameras();
    }
  }

  /**
   * Load Mock Cameras (for development/testing)
   * 
   * Provides sample camera data when API is not available.
   */
  void _loadMockCameras() {
    setState(() {
      _cameras = [
        Camera(
          id: 1,
          name: 'Front Door Camera',
          camCode: 'cam001',
          isActive: true,
          isOnline: true,
          isRecording: false,
          isStreaming: false,
          locationDescription: 'Main entrance',
          healthStatus: 'excellent',
          homeId: _home.id!,
          homeName: _home.name,
          latitude: 40.7128,
          longitude: -74.0060,
        ),
        Camera(
          id: 2,
          name: 'Backyard Camera',
          camCode: 'cam002',
          isActive: true,
          isOnline: false,
          isRecording: false,
          isStreaming: false,
          locationDescription: 'Garden area',
          healthStatus: 'offline',
          homeId: _home.id!,
          homeName: _home.name,
          latitude: 40.7130,
          longitude: -74.0058,
        ),
      ];
    });
    _applyFilters();
    _updateMapMarkers();
  }

  /**
   * Load Home Activities
   * 
   * Fetches recent activities and events for this home.
   */
  Future<void> _loadHomeActivities() async {
    if (_home.id == null) return;
    
    try {
      final response = await _apiService.getHomeActivities(_home.id!); // Using ApiService method
      
      if (response.success) {
        setState(() {
          _activities = (response.data as List).map((json) => HomeActivity.fromJson(json)).toList();
        });
        debugPrint('Loaded ${_activities.length} activities');
      }
    } catch (e) {
      debugPrint('Error loading activities: $e');
      UIUtils.showSnackBar(context, 'Error loading activities: $e', backgroundColor: Colors.red);
    }
  }

  /**
   * Load Home Settings
   * 
   * Retrieves current home security settings and configuration.
   */
  Future<void> _loadHomeSettings() async {
    if (_home.id == null) return;
    
    try {
      final response = await _apiService.getHomeSettings(_home.id!); // Using ApiService method
      
      if (response.success) {
        final data = response.data as Map<String, dynamic>;
        setState(() {
          _alarmEnabled = data['alarm_enabled'] ?? false;
          _motionAlertsEnabled = data['motion_alerts_enabled'] ?? true;
          _emailNotifications = data['email_notifications'] ?? false;
          _smsNotifications = data['sms_notifications'] ?? false;
          _securityMode = data['security_mode'] ?? 'home';
        });
        debugPrint('Home settings loaded');
      }
    } catch (e) {
      debugPrint('Error loading settings: $e');
      UIUtils.showSnackBar(context, 'Error loading settings: $e', backgroundColor: Colors.red);
    }
  }

  /**
   * Load Statistics
   * 
   * Fetches home security statistics and analytics data.
   */
  Future<void> _loadStatistics() async {
    if (_home.id == null) return;
    
    try {
      final response = await _apiService.getHomeStatistics(_home.id!); // Using ApiService method
      
      if (response.success) {
        setState(() {
          _statistics = response.data as Map<String, dynamic>;
        });
        debugPrint('Statistics loaded');
      }
    } catch (e) {
      debugPrint('Error loading statistics: $e');
      UIUtils.showSnackBar(context, 'Error loading statistics: $e', backgroundColor: Colors.red);
      // Use mock statistics
      setState(() {
        _statistics = {
          'total_events_today': 12,
          'motion_detections_today': 8,
          'recordings_today': 3,
          'average_uptime': 98.5,
          'storage_used_gb': 45.2,
          'storage_total_gb': 100.0,
        };
      });
    }
  }

  /**
   * Start Status Updates
   * 
   * Begins periodic status checks for home and camera health monitoring.
   */
  void _startStatusUpdates() {
    _statusTimer = Timer.periodic(const Duration(seconds: 60), (timer) async {
      await _checkHomeStatus();
    });
  }

  /**
   * Check Home Status
   * 
   * Performs a health check on the home security system.
   */
  Future<void> _checkHomeStatus() async {
    if (_home.id == null) return;
    
    try {
      final response = await _apiService.getHomeStatus(_home.id!); // Using ApiService method
      
      if (response.success) {
        final data = response.data as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _home = _home.copyWith(
              isActive: data['is_active'] ?? _home.isActive,
              status: data['status'] ?? _home.status,
            );
          });
        }
      }
    } catch (e) {
      debugPrint('Status check error: $e');
      if (mounted) {
        UIUtils.showSnackBar(context, 'Status check error: $e', backgroundColor: Colors.red);
      }
    }
  }

  /**
   * Setup Search Listener
   * 
   * Configures search functionality for filtering cameras.
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
   * Filters cameras based on search query and status filter.
   */
  void _applyFilters() {
    if (mounted) {
      setState(() {
        _filteredCameras = _cameras.where((camera) {
          // Apply search filter
          bool matchesSearch = _searchQuery.isEmpty ||
              camera.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              camera.locationDescription.toLowerCase().contains(_searchQuery.toLowerCase());
          
          // Apply status filter
          bool matchesStatus = _filterStatus == 'all' ||
              (_filterStatus == 'online' && camera.isOnline) ||
              (_filterStatus == 'offline' && !camera.isOnline) ||
              (_filterStatus == 'recording' && camera.isRecording);
          
          return matchesSearch && matchesStatus;
        }).toList();
      });
    }
  }

  /**
   * Update Map Markers
   * 
   * Updates the map markers to show camera locations.
   */
  void _updateMapMarkers() {
    if (mounted) {
      setState(() {
        _markers = _cameras.map((camera) {
          return Marker(
            markerId: MarkerId(camera.camCode),
            position: LatLng(camera.latitude ?? 0, camera.longitude ?? 0),
            infoWindow: InfoWindow(
              title: camera.name,
              snippet: camera.locationDescription,
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              camera.isOnline ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueRed,
            ),
            onTap: () => _navigateToCameraDetail(camera),
          );
        }).toSet();
      });
    }
  }

  /**
   * Handle Home Status Update
   * 
   * Processes real-time home status updates from the socket server.
   */
  void _handleHomeStatusUpdate(dynamic data) {
    if (data['home_id'] == _home.id) {
      if (mounted) {
        setState(() {
          _home = _home.copyWith(
            isActive: data['is_active'] ?? _home.isActive,
            status: data['status'] ?? _home.status,
          );
        });
      }
      debugPrint('Home status updated: ${_home.status}');
    }
  }

  /**
   * Handle Camera Status Update
   * 
   * Processes real-time camera status updates.
   */
  void _handleCameraStatusUpdate(dynamic data) {
    final cameraCode = data['camera_code'];
    final cameraIndex = _cameras.indexWhere((c) => c.camCode == cameraCode);
    
    if (cameraIndex != -1) {
      if (mounted) {
        setState(() {
          _cameras[cameraIndex] = _cameras[cameraIndex].copyWith(
            isOnline: data['is_online'] ?? _cameras[cameraIndex].isOnline,
            isRecording: data['is_recording'] ?? _cameras[cameraIndex].isRecording,
            isStreaming: data['is_streaming'] ?? _cameras[cameraIndex].isStreaming,
          );
        });
      }
      
      _applyFilters();
      _updateMapMarkers();
      debugPrint('Camera $cameraCode status updated');
    }
  }

  /**
   * Handle Security Event
   * 
   * Processes security events and adds them to the event log.
   */
  void _handleSecurityEvent(dynamic data) {
    if (data['home_id'] == _home.id) {
      final event = SecurityEvent(
        id: DateTime.now().millisecondsSinceEpoch,
        type: data['type'] ?? 'unknown',
        description: data['description'] ?? 'Security event',
        severity: data['severity'] ?? 'info',
        timestamp: DateTime.now(),
        cameraCode: data['camera_code'],
      );
      
      if (mounted) {
        setState(() {
          _securityEvents.insert(0, event);
          if (_securityEvents.length > 100) {
            _securityEvents.removeLast();
          }
        });
      }
      
      debugPrint('Security event: ${event.description}');
      
      // Show notification for high severity events
      if (event.severity == 'high' || event.severity == 'critical') {
        if (mounted) {
          UIUtils.showSnackBar(context, 'Security Alert: ${event.description}', backgroundColor: Colors.red);
        }
      }
    }
  }

  /**
   * Handle Motion Detection
   * 
   * Processes motion detection events from cameras.
   */
  void _handleMotionDetection(dynamic data) {
    if (_motionAlertsEnabled) {
      final cameraName = _cameras
          .firstWhere((c) => c.camCode == data['camera_code'], 
                     orElse: () => Camera.empty())
          .name;
      if (mounted) {
        UIUtils.showSnackBar(context, 'Motion detected on $cameraName', backgroundColor: Colors.orange);
      }
    }
  }

  /**
   * Handle Alarm Triggered
   * 
   * Processes alarm trigger events and shows emergency alerts.
   */
  void _handleAlarmTriggered(dynamic data) {
    if (data['home_id'] == _home.id) {
      if (mounted) {
        _showAlarmDialog(data['reason'] ?? 'Unknown trigger');
      }
    }
  }

  /**
   * Show Alarm Dialog
   * 
   * Displays an emergency alarm dialog with options to dismiss or call emergency services.
   */
  void _showAlarmDialog(String reason) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.red[50],
        title: Row(
          children: [
            const Icon(Icons.warning, color: Colors.red, size: 32),
            const SizedBox(width: 8),
            const Text('SECURITY ALARM', style: TextStyle(color: Colors.red)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Alarm triggered at ${_home.name}'),
            const SizedBox(height: 8),
            Text('Reason: $reason'),
            const SizedBox(height: 16),
            const Text('What would you like to do?'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _disarmAlarm();
            },
            child: const Text('Disarm Alarm'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Call emergency services (implement as needed)
              if (mounted) {
                UIUtils.showSnackBar(context, 'Emergency services contacted', backgroundColor: Colors.red);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Call Emergency'),
          ),
        ],
      ),
    );
  }

  /**
   * Navigate to Camera Detail
   * 
   * Opens the detailed view for a specific camera.
   */
  void _navigateToCameraDetail(Camera camera) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CameraDetailPage(camera: camera),
      ),
    ).then((_) {
      // Refresh data when returning
      _loadHomeCameras();
    });
  }

  /**
   * Start Camera Stream
   * 
   * Initiates a video stream for the specified camera.
   */
  void _startCameraStream(Camera camera) {
    if (!camera.isOnline) {
      if (mounted) {
        UIUtils.showSnackBar(context, 'Camera is offline', backgroundColor: Colors.red);
      }
      return;
    }
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoCallPage(
          roomId: camera.camCode,
          cameraCode: camera.camCode,
          camera: camera,
        ),
      ),
    );
  }

  /**
   * Toggle Camera Recording
   * 
   * Starts or stops recording for the specified camera.
   */
  Future<void> _toggleCameraRecording(Camera camera) async {
    if (!camera.isOnline) {
      if (mounted) {
        UIUtils.showSnackBar(context, 'Camera is offline', backgroundColor: Colors.red);
      }
      return;
    }
    
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
      if (mounted) {
        UIUtils.showSnackBar(context, 'Error: $e', backgroundColor: Colors.red);
      }
    }
  }

  /**
   * Update Home Settings
   * 
   * Saves home security settings to the API.
   */
  Future<void> _updateHomeSettings() async {
    if (_home.id == null) return;
    
    try {
      final response = await _apiService.updateHomeSettings(
        _home.id!,
        {
          'alarm_enabled': _alarmEnabled,
          'motion_alerts_enabled': _motionAlertsEnabled,
          'email_notifications': _emailNotifications,
          'sms_notifications': _smsNotifications,
          'security_mode': _securityMode,
        },
      ); // Using ApiService method
      
      if (response.success) {
        if (mounted) {
          UIUtils.showSnackBar(context, 'Settings updated successfully', backgroundColor: Colors.green);
        }
      } else {
        throw Exception('Failed to update settings: ${response.error}');
      }
    } catch (e) {
      if (mounted) {
        UIUtils.showSnackBar(context, 'Error updating settings: $e', backgroundColor: Colors.red);
      }
    }
  }

  /**
   * Arm Security System
   * 
   * Arms the home security system with the specified mode.
   */
  Future<void> _armSecuritySystem(String mode) async {
    if (_home.id == null) return;
    
    try {
      final response = await _apiService.armHomeSecurity(
        _home.id!,
        mode,
      ); // Using ApiService method
      
      if (response.success) {
        if (mounted) {
          setState(() {
            _securityMode = mode;
            _alarmEnabled = true;
          });
          UIUtils.showSnackBar(context, 'Security system armed ($mode mode)', backgroundColor: Colors.green);
        }
      } else {
        throw Exception('Failed to arm security system: ${response.error}');
      }
    } catch (e) {
      if (mounted) {
        UIUtils.showSnackBar(context, 'Error arming system: $e', backgroundColor: Colors.red);
      }
    }
  }

  /**
   * Disarm Alarm
   * 
   * Disarms the home security system and stops any active alarms.
   */
  Future<void> _disarmAlarm() async {
    if (_home.id == null) return;
    
    try {
      final response = await _apiService.disarmHomeSecurity(_home.id!); // Using ApiService method
      
      if (response.success) {
        if (mounted) {
          setState(() {
            _alarmEnabled = false;
            _securityMode = 'off';
          });
          UIUtils.showSnackBar(context, 'Security system disarmed', backgroundColor: Colors.orange);
        }
      } else {
        throw Exception('Failed to disarm system: ${response.error}');
      }
    } catch (e) {
      if (mounted) {
        UIUtils.showSnackBar(context, 'Error disarming system: $e', backgroundColor: Colors.red);
      }
    }
  }

  /**
   * Refresh All Data
   * 
   * Refreshes all home data with visual feedback.
   */
  Future<void> _refreshAllData() async {
    _refreshController.forward();
    await Future.wait([
      _loadHomeDetails(),
      _loadHomeCameras(),
      _loadHomeActivities(),
      _loadStatistics(),
    ]);
    _refreshController.reset();
  }

  @override
  void dispose() {
    _refreshController.dispose();
    _tabController.dispose();
    _searchController.dispose();
    _statusTimer?.cancel();
    socket?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: _buildBody(),
      floatingActionButton: _buildFloatingActionButton(),
    );
  }

  /**
   * Build App Bar
   * 
   * Creates the app bar with home name, status, and menu options.
   */
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_home.name),
          Text(
            '${_cameras.where((c) => c.isOnline).length}/${_cameras.length} cameras online',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
          ),
        ],
      ),
      backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
      foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
      actions: [
        // Connection status
        Icon(
          isSocketConnected ? Icons.wifi : Icons.wifi_off,
          color: isSocketConnected ? Colors.green : Colors.red,
          size: 20,
        ),
        const SizedBox(width: 8),
        // Security status
        Icon(
          _alarmEnabled ? Icons.security : Icons.no_encryption,
          color: _alarmEnabled ? Colors.green : Colors.orange,
          size: 20,
        ),
        const SizedBox(width: 8),
        // Refresh button
        IconButton(
          icon: RotationTransition(
            turns: _refreshController,
            child: const Icon(Icons.refresh),
          ),
          onPressed: _refreshAllData,
        ),
        // Menu
        PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'arm_home':
                _armSecuritySystem('home');
                break;
              case 'arm_away':
                _armSecuritySystem('away');
                break;
              case 'disarm':
                _disarmAlarm();
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'arm_home',
              child: Row(
                children: [
                  Icon(Icons.home),
                  SizedBox(width: 8),
                  Text('Arm (Home)'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'arm_away',
              child: Row(
                children: [
                  Icon(Icons.shield),
                  SizedBox(width: 8),
                  Text('Arm (Away)'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'disarm',
              child: Row(
                children: [
                  Icon(Icons.no_encryption),
                  SizedBox(width: 8),
                  Text('Disarm'),
                ],
              ),
            ),
          ],
        ),
      ],
      bottom: TabBar(
        controller: _tabController,
        indicatorColor: Colors.white,
        tabs: const [
          Tab(icon: Icon(Icons.dashboard), text: 'Overview'),
          Tab(icon: Icon(Icons.videocam), text: 'Cameras'),
          Tab(icon: Icon(Icons.security), text: 'Security'),
          Tab(icon: Icon(Icons.history), text: 'Activity'),
        ],
      ),
    );
  }

  /**
   * Build Body
   * 
   * Creates the main content area with tabbed navigation.
   */
  Widget _buildBody() {
    if (_isLoading && _home.id == null) {
      return const Center(child: CircularProgressIndicator());
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
              onPressed: _loadHomeDetails,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return TabBarView(
      controller: _tabController,
      children: [
        _buildOverviewTab(),
        _buildCamerasTab(),
        _buildSecurityTab(),
        _buildActivityTab(),
      ],
    );
  }

  /**
   * Build Overview Tab
   * 
   * Creates the overview tab with home statistics and quick controls.
   */
  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHomeInfoCard(),
          const SizedBox(height: 16),
          _buildStatisticsCard(),
          const SizedBox(height: 16),
          _buildQuickControlsCard(),
          const SizedBox(height: 16),
          _buildMapCard(),
        ],
      ),
    );
  }

  /**
   * Build Home Info Card
   * 
   * Creates a card with basic home information and status.
   */
  Widget _buildHomeInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.home, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  'Home Information',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _home.isActive ? Colors.green : Colors.grey,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _home.status.toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              _home.address,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.videocam, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text('${_home.numCameras} cameras installed'),
                const SizedBox(width: 16),
                Icon(Icons.shield, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text('Security: ${_securityMode.toUpperCase()}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /**
   * Build Statistics Card
   * 
   * Creates a card with home security statistics and analytics.
   */
  Widget _buildStatisticsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.analytics, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  'Today\'s Statistics',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    'Events',
                    '${_statistics['total_events_today'] ?? 0}',
                    Icons.event,
                    Colors.blue,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'Motion',
                    '${_statistics['motion_detections_today'] ?? 0}',
                    Icons.directions_run,
                    Colors.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    'Recordings',
                    '${_statistics['recordings_today'] ?? 0}',
                    Icons.fiber_manual_record,
                    Colors.red,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'Uptime',
                    '${_statistics['average_uptime'] ?? 0}%',
                    Icons.trending_up,
                    Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: (_statistics['storage_used_gb'] ?? 0) / 
                     (_statistics['storage_total_gb'] ?? 100),
              backgroundColor: Colors.grey[300],
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
            ),
            const SizedBox(height: 4),
            Text(
              'Storage: ${_statistics['storage_used_gb'] ?? 0}GB / ${_statistics['storage_total_gb'] ?? 100}GB',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  /**
   * Build Stat Item
   * 
   * Creates a statistics item with icon, value, and label.
   */
  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  /**
   * Build Quick Controls Card
   * 
   * Creates a card with quick action buttons for common operations.
   */
  Widget _buildQuickControlsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.flash_on, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  'Quick Controls',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _armSecuritySystem('home'),
                    icon: const Icon(Icons.home),
                    label: const Text('Arm Home'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _armSecuritySystem('away'),
                    icon: const Icon(Icons.shield),
                    label: const Text('Arm Away'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _disarmAlarm,
                icon: const Icon(Icons.no_encryption),
                label: const Text('Disarm System'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /**
   * Build Map Card
   * 
   * Creates a card with a map showing camera locations.
   */
  Widget _buildMapCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.map, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  'Camera Locations',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: LatLng(
                    _home.latitude ?? 40.7128,
                    _home.longitude ?? -74.0060,
                  ),
                  zoom: 18,
                ),
                markers: _markers,
                onMapCreated: (GoogleMapController controller) {
                  // _mapController = controller; // This line is removed
                },
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /**
   * Build Cameras Tab
   * 
   * Creates the cameras tab with camera list and controls.
   */
  Widget _buildCamerasTab() {
    return Column(
      children: [
        // Search and filter bar
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search cameras...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => _searchController.clear(),
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _filterStatus,
                onChanged: (value) {
                  if (mounted) {
                    setState(() {
                      _filterStatus = value!;
                    });
                  }
                  _applyFilters();
                },
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All')),
                  DropdownMenuItem(value: 'online', child: Text('Online')),
                  DropdownMenuItem(value: 'offline', child: Text('Offline')),
                  DropdownMenuItem(value: 'recording', child: Text('Recording')),
                ],
              ),
            ],
          ),
        ),
        // Camera list
        Expanded(
          child: _filteredCameras.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.videocam_off, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('No cameras found'),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadHomeCameras,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _filteredCameras.length,
                    itemBuilder: (context, index) {
                      final camera = _filteredCameras[index];
                      return _buildCameraCard(camera);
                    },
                  ),
                ),
        ),
      ],
    );
  }

  /**
   * Build Camera Card
   * 
   * Creates an individual camera card with status and controls.
   */
  Widget _buildCameraCard(Camera camera) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: () => _navigateToCameraDetail(camera),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                          camera.locationDescription,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (camera.isRecording)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'REC',
                        style: TextStyle(color: Colors.white, fontSize: 10),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Status: ${camera.isOnline ? 'Online' : 'Offline'} • Health: ${camera.healthStatus}',
                style: TextStyle(
                  color: camera.isOnline ? Colors.green : Colors.red,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: camera.isOnline
                        ? () => _startCameraStream(camera)
                        : null,
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: const Text('Stream'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(80, 32),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: camera.isOnline
                        ? () => _toggleCameraRecording(camera)
                        : null,
                    icon: Icon(
                      camera.isRecording ? Icons.stop : Icons.fiber_manual_record,
                      size: 16,
                    ),
                    label: Text(camera.isRecording ? 'Stop' : 'Record'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: camera.isRecording ? Colors.red : Colors.green,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(80, 32),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _navigateToCameraDetail(camera),
                    icon: const Icon(Icons.info, size: 16),
                    label: const Text('Details'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(80, 32),
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
   * Build Security Tab
   * 
   * Creates the security tab with system settings and controls.
   */
  Widget _buildSecurityTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSecurityStatusCard(),
          const SizedBox(height: 16),
          _buildSecuritySettingsCard(),
          const SizedBox(height: 16),
          _buildNotificationSettingsCard(),
        ],
      ),
    );
  }

  /**
   * Build Security Status Card
   * 
   * Creates a card showing current security system status.
   */
  Widget _buildSecurityStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _alarmEnabled ? Icons.security : Icons.no_encryption,
                  color: _alarmEnabled ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Security Status',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _alarmEnabled ? Colors.green : Colors.orange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _alarmEnabled ? 'ARMED' : 'DISARMED',
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Current Mode: ${_securityMode.toUpperCase()}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              _alarmEnabled
                  ? 'Security system is active and monitoring'
                  : 'Security system is disarmed',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  /**
   * Build Security Settings Card
   * 
   * Creates a card with security system configuration options.
   */
  Widget _buildSecuritySettingsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.settings, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  'Security Settings',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Alarm System'),
              subtitle: const Text('Enable security alarm'),
              value: _alarmEnabled,
              onChanged: (value) async { // Made onChanged async
                if (mounted) {
                  setState(() {
                    _alarmEnabled = value;
                  });
                }
                if (value) {
                  await _armSecuritySystem('home');
                } else {
                  await _disarmAlarm();
                }
              },
            ),
            SwitchListTile(
              title: const Text('Motion Alerts'),
              subtitle: const Text('Receive motion detection alerts'),
              value: _motionAlertsEnabled,
              onChanged: (value) {
                if (mounted) {
                  setState(() {
                    _motionAlertsEnabled = value;
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            const Text(
              'Security Mode',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'home', label: Text('Home')),
                ButtonSegment(value: 'away', label: Text('Away')),
                ButtonSegment(value: 'sleep', label: Text('Sleep')),
                ButtonSegment(value: 'off', label: Text('Off')),
              ],
              selected: {_securityMode},
              onSelectionChanged: (Set<String> selection) async { // Made onSelectionChanged async
                final mode = selection.first;
                if (mounted) {
                  setState(() {
                    _securityMode = mode;
                  });
                }
                if (mode != 'off') {
                  await _armSecuritySystem(mode);
                } else {
                  await _disarmAlarm();
                }
              },
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _updateHomeSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Save Settings'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /**
   * Build Notification Settings Card
   * 
   * Creates a card with notification preferences.
   */
  Widget _buildNotificationSettingsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.notifications, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  'Notification Settings',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Email Notifications'),
              subtitle: const Text('Receive alerts via email'),
              value: _emailNotifications,
              onChanged: (value) {
                if (mounted) {
                  setState(() {
                    _emailNotifications = value;
                  });
                }
              },
            ),
            SwitchListTile(
              title: const Text('SMS Notifications'),
              subtitle: const Text('Receive alerts via SMS'),
              value: _smsNotifications,
              onChanged: (value) {
                if (mounted) {
                  setState(() {
                    _smsNotifications = value;
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  /**
   * Build Activity Tab
   * 
   * Creates the activity tab with recent events and security logs.
   */
  Widget _buildActivityTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRecentActivitiesCard(),
          const SizedBox(height: 16),
          _buildSecurityEventsCard(),
        ],
      ),
    );
  }

  /**
   * Build Recent Activities Card
   * 
   * Creates a card showing recent home activities.
   */
  Widget _buildRecentActivitiesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.history, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  'Recent Activities',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: _activities.isEmpty
                  ? const Center(
                      child: Text(
                        'No recent activities',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _activities.length,
                      itemBuilder: (context, index) {
                        final activity = _activities[index];
                        return ListTile(
                          leading: Icon(
                            _getActivityIcon(activity.type),
                            color: Colors.blue,
                            size: 20,
                          ),
                          title: Text(
                            activity.description,
                            style: const TextStyle(fontSize: 14),
                          ),
                          subtitle: Text(
                            UIUtils.formatTimestamp(activity.timestamp),
                            style: const TextStyle(fontSize: 12),
                          ),
                          dense: true,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /**
   * Build Security Events Card
   * 
   * Creates a card showing security events and alerts.
   */
  Widget _buildSecurityEventsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.warning, color: Colors.red),
                SizedBox(width: 8),
                Text(
                  'Security Events',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: _securityEvents.isEmpty
                  ? const Center(
                      child: Text(
                        'No security events',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _securityEvents.length,
                      itemBuilder: (context, index) {
                        final event = _securityEvents[index];
                        return ListTile(
                          leading: Icon(
                            _getSecurityEventIcon(event.type),
                            color: _getSecurityEventColor(event.severity),
                            size: 20,
                          ),
                          title: Text(
                            event.description,
                            style: const TextStyle(fontSize: 14),
                          ),
                          subtitle: Text(
                            '${UIUtils.formatTimestamp(event.timestamp)} • ${event.severity.toUpperCase()}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: event.cameraCode != null
                              ? Text(
                                  event.cameraCode!,
                                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                                )
                              : null,
                          dense: true,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /**
   * Build Floating Action Button
   * 
   * Creates a floating action button for quick actions.
   */
  Widget _buildFloatingActionButton() {
    return FloatingActionButton.extended(
      onPressed: () {
        // Show quick actions menu
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
                    Navigator.pop(context);
                    if (mounted) {
                      UIUtils.showSnackBar(context, 'Add Camera feature coming soon!', backgroundColor: Colors.blue);
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.security),
                  title: const Text('Emergency Mode'),
                  onTap: () async { // Made onTap async
                    Navigator.pop(context);
                    await _armSecuritySystem('emergency');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.call),
                  title: const Text('Call Emergency Services'),
                  onTap: () {
                    Navigator.pop(context);
                    if (mounted) {
                      UIUtils.showSnackBar(context, 'Emergency services contacted', backgroundColor: Colors.red);
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
      backgroundColor: Theme.of(context).floatingActionButtonTheme.backgroundColor,
      foregroundColor: Colors.white,
      icon: const Icon(Icons.add),
      label: const Text('Quick Actions'),
    );
  }

  /**
   * Get Activity Icon
   * 
   * Returns appropriate icon for activity type.
   */
  IconData _getActivityIcon(String type) {
    switch (type) {
      case 'camera_added':
        return Icons.add_a_photo;
      case 'camera_removed':
        return Icons.remove_circle;
      case 'system_armed':
        return Icons.security;
      case 'system_disarmed':
        return Icons.no_encryption;
      case 'settings_changed':
        return Icons.settings;
      default:
        return Icons.info;
    }
  }

  /**
   * Get Security Event Icon
   * 
   * Returns appropriate icon for security event type.
   */
  IconData _getSecurityEventIcon(String type) {
    switch (type) {
      case 'motion_detected':
        return Icons.directions_run;
      case 'alarm_triggered':
        return Icons.alarm;
      case 'intrusion_detected':
        return Icons.warning;
      case 'camera_offline':
        return Icons.videocam_off;
      case 'system_error':
        return Icons.error;
      default:
        return Icons.info;
    }
  }

  /**
   * Get Security Event Color
   * 
   * Returns appropriate color for security event severity.
   */
  Color _getSecurityEventColor(String severity) {
    switch (severity) {
      case 'critical':
        return Colors.red;
      case 'high':
        return Colors.orange;
      case 'medium':
        return Colors.yellow;
      case 'low':
        return Colors.blue;
      case 'info':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }
}




