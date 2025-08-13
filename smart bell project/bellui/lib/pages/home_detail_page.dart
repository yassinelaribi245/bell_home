import 'package:flutter/material.dart';
import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:bellui/services/api_service.dart';
import 'package:bellui/models/models.dart';
import 'package:bellui/utils/utils.dart';
import 'package:bellui/pages/camera_detail_page.dart';
import 'package:bellui/pages/video_call_page.dart';

/// Home Detail Page (Redesigned)
/// 
/// This page provides a comprehensive view of a single home/property with:
/// - Home information and location details (similar to camera details layout)
/// - List of all cameras associated with the home
/// - Real-time camera status monitoring
/// - Clean card-based layout matching camera detail page
/// 
/// The page serves as a central hub for managing all security aspects
/// of a specific property or location with a consistent UI design.
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
  bool _isLoading = false;
  String? _errorMessage;
  
  // Real-time communication
  io.Socket? socket;
  bool isSocketConnected = false;
  Timer? _statusTimer;
  
  // Animation controllers
  late AnimationController _refreshController;
  
  // Activity and events
  List<HomeActivity> _activities = [];
  
  // Home settings and configuration
  bool _alarmEnabled = false;
  bool _motionAlertsEnabled = true;
  String _securityMode = 'home'; // home, away, sleep, off
  
  // Search and filtering
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  
  // Statistics
  Map<String, dynamic> _statistics = {};
  
  // API service instance
  final ApiService _apiService = ApiService();

  // Debug logs
  final List<String> _debugLogs = [];

  @override
  void initState() {
    super.initState();
    _home = widget.home;
    _initializeControllers();
    _initializeSocket();
    _loadHomeCameras();
    _loadHomeSettings();
    _loadStatistics();
    _startStatusUpdates();
    _setupSearchListener();
  }

  /**
   * Initialize Controllers
   * 
   * Sets up animation controllers for smooth UI transitions.
   */
  void _initializeControllers() {
    _refreshController = AnimationController(
      duration: const Duration(milliseconds: 1000),
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
        
        _addDebugLog('Connected to home ${_home.id} socket room');
      });

      socket!.onDisconnect((_) {
        setState(() {
          isSocketConnected = false;
        });
      });

      // Listen for home and camera events
      socket!.on('home_status_update', _handleHomeStatusUpdate);
      socket!.on('camera_status_update', _handleCameraStatusUpdate);

      socket!.connect();
    } catch (e) {
      _addDebugLog('Socket initialization error: $e');
      UIUtils.showSnackBar(context, 'Socket connection error: $e', backgroundColor: Colors.red);
    }
  }

  /**
   * Load Home Cameras
   * 
   * Fetches all cameras associated with this home.
   */
  Future<void> _loadHomeCameras() async {
    if (_home.id == null) return;
    
    try {
      final response = await _apiService.getHomeCameras(_home.id!);
      
      if (response.success) {
        setState(() {
          _cameras = response.data as List<Camera>;
          // Sort cameras by status (online first) and then by name
          _cameras.sort((a, b) {
            if (a.isOnline != b.isOnline) {
              return b.isOnline ? 1 : -1;
            }
            return a.name.compareTo(b.name);
          });
        });
        
        _addDebugLog('Loaded ${_cameras.length} cameras for home ${_home.id}');
      } else {
        _addDebugLog('Failed to load cameras: ${response.error}');
        setState(() {
          _cameras = [];
        });
      }
    } catch (e) {
      _addDebugLog('Error loading cameras: $e');
      setState(() {
        _cameras = [];
      });
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
      final response = await _apiService.getHomeSettings(_home.id!);
      
      if (response.success) {
        final data = response.data as Map<String, dynamic>;
        setState(() {
          _alarmEnabled = data['alarm_enabled'] ?? false;
          _motionAlertsEnabled = data['motion_alerts_enabled'] ?? true;
          _securityMode = data['security_mode'] ?? 'home';
        });
        _addDebugLog('Home settings loaded');
      }
    } catch (e) {
      _addDebugLog('Error loading settings: $e');
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
      final response = await _apiService.getHomeStatistics(_home.id!);
      
      if (response.success) {
        setState(() {
          _statistics = response.data as Map<String, dynamic>;
        });
        _addDebugLog('Statistics loaded');
      }
    } catch (e) {
      _addDebugLog('Error loading statistics: $e');
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
      final response = await _apiService.getHomeStatus(_home.id!);
      
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
      _addDebugLog('Status check error: $e');
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
    });
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
      _addDebugLog('Home status updated: ${_home.status}');
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
      
      _addDebugLog('Camera $cameraCode status updated');
    }
  }

  /**
   * Navigate to Camera Detail
   * 
   * Navigates to the camera detail page for the selected camera.
   */
  void _navigateToCameraDetail(Camera camera) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CameraDetailPage(camera: camera),
      ),
    ).then((_) {
      // Refresh cameras when returning from camera detail
      _loadHomeCameras();
    });
  }

  /**
   * Add Debug Log
   * 
   * Adds a timestamped debug message to the debug log list.
   */
  void _addDebugLog(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    setState(() {
      _debugLogs.insert(0, '[$timestamp] $message');
      if (_debugLogs.length > 100) {
        _debugLogs.removeLast();
      }
    });
    debugPrint(message);
  }

  /// Show Delete Home Dialog
  ///
  /// Shows a confirmation dialog before deleting the home.
  void _showDeleteHomeDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Home'),
          content: Text(
            'Are you sure you want to delete this home (ID: ${_home.id})?\n\nThis action will also delete all associated cameras and cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _deleteHome();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  /// Delete Home
  ///
  /// Calls the API to delete the home and navigates back.
  Future<void> _deleteHome() async {
    if (_home.id == null) {
      UIUtils.showSnackBar(
        context,
        'Cannot delete home: Invalid home ID',
        backgroundColor: Colors.red,
      );
      return;
    }

    try {
      setState(() {
        _isLoading = true;
      });

      final response = await _apiService.deleteHome(_home.id!);
      
      if (response.success) {
        UIUtils.showSnackBar(
          context,
          'Home deleted successfully',
          backgroundColor: Colors.green,
        );
        
        // Navigate back to previous screen
        if (mounted) {
          Navigator.of(context).pop();
        }
      } else {
        throw Exception(response.error ?? 'Failed to delete home');
      }
    } catch (e) {
      _addDebugLog('Error deleting home: $e');
      UIUtils.showSnackBar(
        context,
        'Error deleting home: $e',
        backgroundColor: Colors.red,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _refreshController.dispose();
    _statusTimer?.cancel();
    socket?.disconnect();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: _buildBody(),
    );
  }

  /// Build App Bar
  /// 
  /// Creates the app bar with home ID, status indicators, and menu options.
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Text('Home ID: ${_home.id ?? 'Unknown'}'),
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
        // Home status
        Icon(
          _home.isActive ? Icons.home : Icons.home_outlined,
          color: _home.isActive ? Colors.green : Colors.red,
          size: 20,
        ),
        const SizedBox(width: 8),
        // Menu
        PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'refresh':
                _loadHomeCameras();
                break;
              case 'settings':
                // Navigate to home settings
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'refresh',
              child: Row(
                children: [
                  Icon(Icons.refresh),
                  SizedBox(width: 8),
                  Text('Refresh'),
                ],
              ),
            ),
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
          ],
        ),
      ],
    );
  }

  /// Build Body
  /// 
  /// Creates the main content area with home information and camera list.
  Widget _buildBody() {
    if (_isLoading && _home.id == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHomeInfoCard(),
          const SizedBox(height: 16),
          _buildCamerasCard(),
          const SizedBox(height: 16),
          _buildDebugCard(),
        ],
      ),
    );
  }

  /// Build Home Info Card
  /// 
  /// Creates a card with home information similar to camera info card.
  Widget _buildHomeInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Home Information',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildInfoRow('ID', _home.id?.toString() ?? 'N/A'),
            _buildInfoRow('Surface Area', _home.formattedSurface),
            _buildInfoRow('Number of Cameras', _home.numCameras.toString()),
            _buildInfoRow('Status', _home.status.toUpperCase()),
            _buildInfoRow('Security Mode', _securityMode.toUpperCase()),
            _buildInfoRow('Created At', _home.createdAt?.toString() ?? 'N/A'),
            _buildInfoRow('Updated At', _home.updatedAt?.toString() ?? 'N/A'),
            if (_home.hasLocation) ...[
              _buildInfoRow('Longitude', _home.longitude?.toString() ?? 'N/A'),
              _buildInfoRow('Latitude', _home.latitude?.toString() ?? 'N/A'),
            ],
            const SizedBox(height: 16),
            
            // Delete Home button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _showDeleteHomeDialog,
                icon: const Icon(Icons.delete),
                label: const Text('Delete Home'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 48),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build Cameras Card
  /// 
  /// Creates a card with the list of cameras in this home.
  Widget _buildCamerasCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.videocam, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  'Cameras',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  '${_cameras.length} cameras',
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Search bar
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search cameras...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
            const SizedBox(height: 16),
            
            // Camera list
            if (_cameras.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'No cameras found in this home',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              ..._cameras
                  .where((camera) =>
                      _searchQuery.isEmpty ||
                      camera.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                      camera.locationDescription.toLowerCase().contains(_searchQuery.toLowerCase()))
                  .map((camera) => _buildCameraListItem(camera))
                  .toList(),
          ],
        ),
      ),
    );
  }

  /// Build Camera List Item
  /// 
  /// Creates a list item for each camera with status and actions.
  Widget _buildCameraListItem(Camera camera) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: camera.isOnline ? Colors.green : Colors.red,
          child: Icon(
            camera.isOnline ? Icons.videocam : Icons.videocam_off,
            color: Colors.white,
            size: 20,
          ),
        ),
        title: Text(
          camera.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(camera.locationDescription.isNotEmpty 
                ? camera.locationDescription 
                : 'No location specified'),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: camera.isOnline ? Colors.green : Colors.red,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    camera.isOnline ? 'ONLINE' : 'OFFLINE',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (camera.isRecording)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'RECORDING',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                if (camera.isStreaming)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'STREAMING',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () => _navigateToCameraDetail(camera),
      ),
    );
  }

  /// Build Debug Card
  /// 
  /// Creates a card with debug logs for troubleshooting.
  Widget _buildDebugCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bug_report, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  'Debug Log',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _debugLogs.clear();
                    });
                  },
                  child: const Text('Clear'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              height: 150,
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: _debugLogs.isEmpty
                  ? const Center(
                      child: Text(
                        'No debug messages',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _debugLogs.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1),
                          child: Text(
                            _debugLogs[index],
                            style: const TextStyle(
                              fontSize: 10,
                              fontFamily: 'monospace',
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build Info Row
  /// 
  /// Creates a row with label and value for displaying information.
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label + ':',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

