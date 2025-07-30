import 'package:flutter/material.dart';
import 'package:bellui/services/api_service.dart';
import 'package:bellui/models/models.dart';
import 'package:bellui/utils/utils.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'dart:async';
import 'dart:convert'; // Added for json.decode

// Import the video call page
import 'package:bellui/pages/video_call_page.dart'; // Corrected import path

/// Camera Detail Page
/// 
/// This page provides a comprehensive view of a single camera with:
/// - Real-time status monitoring and health information
/// - Streaming controls (start/stop video stream)
/// - Recording controls (start/stop recording)
/// - Camera settings and configuration options
/// - Location and technical information
/// - Activity history and logs
/// - Motion detection settings
/// - Storage and notification preferences
/// 
/// The page updates in real-time using Socket.IO connections and
/// provides full control over camera operations.
class CameraDetailPage extends StatefulWidget {
  final Camera camera;

  const CameraDetailPage({
    super.key,
    required this.camera,
  });

  @override
  State<CameraDetailPage> createState() => _CameraDetailPageState();
}

class _CameraDetailPageState extends State<CameraDetailPage>
    with TickerProviderStateMixin {
  
  // Camera state management
  late Camera _camera;
  bool _isLoading = false;
  
  // Real-time communication
  io.Socket? socket;
  bool isSocketConnected = false;
  Timer? _statusTimer;
  
  // Animation controllers
  late AnimationController _pulseController;
  late AnimationController _rotationController;
  
  // Activity and logs
  List<CameraActivity> _activities = [];
  final List<String> _debugLogs = [];
  
  // Settings and controls
  bool _motionDetectionEnabled = true;
  bool _nightVisionEnabled = false;
  bool _audioEnabled = true;
  bool _notificationsEnabled = true;
  double _sensitivity = 0.5;
  
  // API service instance
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    _camera = widget.camera;
    _initializeAnimations();
    _initializeSocket();
    _loadCameraDetails();
    _loadCameraActivities();
    _startStatusUpdates();
    _loadCameraSettings();
  }

  /// Initialize Animation Controllers
  /// 
  /// Sets up animations for visual feedback during camera operations
  /// like recording indicators and status updates.
  void _initializeAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    
    _rotationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    
    // Start pulse animation if camera is recording
    if (_camera.isRecording) {
      _pulseController.repeat(reverse: true);
    }
  }

  /// Initialize Socket Connection
  /// 
  /// Establishes real-time connection for camera status updates
  /// and live event notifications.
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
        
        // Join camera-specific room for updates
        socket!.emit('join_camera_room', {
          'camera_code': _camera.camCode,
        });
        
        _addDebugLog('Connected to camera ${_camera.camCode}');
      });

      socket!.onDisconnect((_) {
        setState(() {
          isSocketConnected = false;
        });
        _addDebugLog('Disconnected from camera ${_camera.camCode}');
      });

      // Listen for camera-specific events
      socket!.on('camera_status_update', _handleStatusUpdate);
      socket!.on('motion_detected', _handleMotionDetection);
      socket!.on('recording_started', _handleRecordingStarted);
      socket!.on('recording_stopped', _handleRecordingStopped);
      socket!.on('camera_error', _handleCameraError);
      // --- Fix: Listen for camera_response to start call ---
      socket!.on('camera_response', (data) {
        _addDebugLog('🔔 [SOCKET EVENT] camera_response: $data');
        if (data['response'] == 'accepted') {
          _addDebugLog('📱 Call accepted by mobile, starting call...');
          // Wait for mobile to join room before starting call
          Future.delayed(const Duration(milliseconds: 500), () {
            _startCameraStream();
          });
        } else if (data['response'] == 'refused') {
          _addDebugLog('❌ Call refused by mobile');
        }
      });
      // --- End fix ---
      // --- Add catch-all event logger for debugging ---
      socket!.onAny((event, data) {
        _addDebugLog('🔔 [SOCKET EVENT] $event: $data');
      });
      // --- End catch-all ---

      socket!.connect();
    } catch (e) {
      _addDebugLog('Socket initialization error: $e');
      UIUtils.showSnackBar(context, 'Socket connection error: $e', backgroundColor: Colors.red);
    }
  }

  /// Load Camera Details
  /// 
  /// Fetches detailed camera information from the API including
  /// technical specifications and current settings.
  Future<void> _loadCameraDetails() async {
    if (_camera.id == null) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await _apiService.getCameraDetails(_camera.id!);
      
      if (response.success) {
        setState(() {
          _camera = response.data!;
        });
        _addDebugLog('Camera details loaded successfully');
      } else {
        throw Exception('Failed to load camera details: ${response.error}');
      }
    } catch (e) {
      _addDebugLog('Error loading camera details: $e');
      UIUtils.showSnackBar(context, 'Error loading camera details: $e', backgroundColor: Colors.red);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Load Camera Activities
  /// 
  /// Fetches recent camera activities and events for display
  /// in the activity history section.
  Future<void> _loadCameraActivities() async {
    if (_camera.id == null) return;
    
    try {
      final response = await _apiService.getCameraActivities(_camera.id!);
      
      if (response.success) {
        setState(() {
          _activities = response.data!;
        });
        _addDebugLog('Loaded ${_activities.length} activities');
      }
    } catch (e) {
      _addDebugLog('Error loading activities: $e');
      UIUtils.showSnackBar(context, 'Error loading activities: $e', backgroundColor: Colors.red);
    }
  }

  /// Load Camera Settings
  /// 
  /// Retrieves current camera configuration settings
  /// for display and modification.
  Future<void> _loadCameraSettings() async {
    if (_camera.id == null) return;
    
    try {
      final response = await _apiService.getCameraSettings(_camera.id!);
      
      if (response.success) {
        final data = response.data!;
        setState(() {
          _motionDetectionEnabled = data['motion_detection'] ?? true;
          _nightVisionEnabled = data['night_vision'] ?? false;
          _audioEnabled = data['audio_enabled'] ?? true;
          _notificationsEnabled = data['notifications_enabled'] ?? true;
          _sensitivity = (data['sensitivity'] ?? 0.5).toDouble();
        });
        _addDebugLog('Camera settings loaded');
      }
    } catch (e) {
      _addDebugLog('Error loading settings: $e');
      UIUtils.showSnackBar(context, 'Error loading settings: $e', backgroundColor: Colors.red);
    }
  }

  /// Start Status Updates
  /// 
  /// Begins periodic status checks to monitor camera health
  /// and connectivity when socket connection is not available.
  void _startStatusUpdates() {
    _statusTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _checkCameraStatus();
    });
  }

  /// Check Camera Status
  /// 
  /// Performs a health check on the camera to verify
  /// connectivity and operational status.
  Future<void> _checkCameraStatus() async {
    if (_camera.id == null) return;
    
    try {
      final response = await _apiService.getCameraStatus(_camera.id!);
      
      if (response.success) {
        final data = response.data!;
        setState(() {
          _camera = _camera.copyWith(
            isOnline: data['is_online'] ?? false,
            isRecording: data['is_recording'] ?? false,
            isStreaming: data['is_streaming'] ?? false,
          );
        });
        
        // Update recording animation
        if (_camera.isRecording && !_pulseController.isAnimating) {
          _pulseController.repeat(reverse: true);
        } else if (!_camera.isRecording && _pulseController.isAnimating) {
          _pulseController.stop();
          _pulseController.reset();
        }
      }
    } catch (e) {
      _addDebugLog('Status check error: $e');
      UIUtils.showSnackBar(context, 'Status check error: $e', backgroundColor: Colors.red);
    }
  }

  /// Handle Status Update
  /// 
  /// Processes real-time status updates received via Socket.IO
  /// and updates the UI accordingly.
  void _handleStatusUpdate(dynamic data) {
    if (data['camera_code'] == _camera.camCode) {
      setState(() {
        _camera = _camera.copyWith(
          isOnline: data['is_online'] ?? _camera.isOnline,
          isRecording: data['is_recording'] ?? _camera.isRecording,
          isStreaming: data['is_streaming'] ?? _camera.isStreaming,
        );
      });
      
      _addDebugLog('Status updated: Online=${_camera.isOnline}, Recording=${_camera.isRecording}');
      
      // Update animations based on new status
      if (_camera.isRecording && !_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      } else if (!_camera.isRecording && _pulseController.isAnimating) {
        _pulseController.stop();
        _pulseController.reset();
      }
    }
  }

  /// Handle Motion Detection
  /// 
  /// Processes motion detection events and updates the activity log.
  void _handleMotionDetection(dynamic data) {
    if (data['camera_code'] == _camera.camCode) {
      final activity = CameraActivity(
        id: DateTime.now().millisecondsSinceEpoch,
        type: 'motion_detected',
        description: 'Motion detected',
        timestamp: DateTime.now(),
      );
      
      setState(() {
        _activities.insert(0, activity);
        if (_activities.length > 50) {
          _activities.removeLast();
        }
      });
      
      _addDebugLog('Motion detected at ${DateTime.now()}');
      
      // Show notification if enabled
      if (_notificationsEnabled) {
        UIUtils.showSnackBar(context, 'Motion detected!', backgroundColor: Colors.orange);
      }
    }
  }

  /// Handle Recording Started
  /// 
  /// Processes recording start events and updates the UI.
  void _handleRecordingStarted(dynamic data) {
    if (data['camera_code'] == _camera.camCode) {
      setState(() {
        _camera = _camera.copyWith(isRecording: true);
      });
      
      _pulseController.repeat(reverse: true);
      _addDebugLog('Recording started');
      UIUtils.showSnackBar(context, 'Recording started', backgroundColor: Colors.green);
    }
  }

  /// Handle Recording Stopped
  /// 
  /// Processes recording stop events and updates the UI.
  void _handleRecordingStopped(dynamic data) {
    if (data['camera_code'] == _camera.camCode) {
      setState(() {
        _camera = _camera.copyWith(isRecording: false);
      });
      
      _pulseController.stop();
      _pulseController.reset();
      _addDebugLog('Recording stopped');
      UIUtils.showSnackBar(context, 'Recording stopped', backgroundColor: Colors.red);
    }
  }

  /// Handle Camera Error
  /// 
  /// Processes camera error events and displays appropriate messages.
  void _handleCameraError(dynamic data) {
    if (data['camera_code'] == _camera.camCode) {
      final error = data['error'] ?? 'Unknown error';
      _addDebugLog('Camera error: $error');
      UIUtils.showSnackBar(context, 'Camera error: $error', backgroundColor: Colors.red);
    }
  }

  /// Add Debug Log
  /// 
  /// Adds a timestamped debug message to the debug log list.
  void _addDebugLog(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    setState(() {
      _debugLogs.insert(0, '[$timestamp] $message');
      if (_debugLogs.length > 100) {
        _debugLogs.removeLast();
      }
    });
    debugPrint(message); // Use debugPrint instead of print
  }

  /// Start Camera Stream
  /// 
  /// Initiates a video stream from the camera and navigates
  /// to the video call page.
  void _startCameraStream() {
    if (!mounted) return;
    if (!_camera.isOnline) {
      UIUtils.showSnackBar(context, 'Camera is offline', backgroundColor: Colors.red);
      return;
    }
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoCallPage(
          roomId: _camera.camCode,
          cameraCode: _camera.camCode,
          camera: _camera,
        ),
      ),
    ).then((_) {
      // Refresh status when returning from video call
      _checkCameraStatus();
    });
  }

  /// Toggle Camera Recording
  /// 
  /// Starts or stops camera recording via API call.
  Future<void> _toggleRecording() async {
    if (!mounted) return;
    if (!_camera.isOnline) {
      UIUtils.showSnackBar(context, 'Camera is offline', backgroundColor: Colors.red);
      return;
    }
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      final response = await _apiService.toggleCameraRecording(_camera.id!);
      
      if (response.success) {
        final data = response.data!;
        if (!mounted) return;
        setState(() {
          _camera = _camera.copyWith(isRecording: data['is_recording']);
        });
        
        _addDebugLog('Recording ${_camera.isRecording ? 'started' : 'stopped'}');
        UIUtils.showSnackBar(
          context,
          _camera.isRecording ? 'Recording started' : 'Recording stopped',
          backgroundColor: _camera.isRecording ? Colors.green : Colors.red,
        );
        
        // Update animation
        if (_camera.isRecording) {
          _pulseController.repeat(reverse: true);
        } else {
          _pulseController.stop();
          _pulseController.reset();
        }
      } else {
        throw Exception('Failed to toggle recording: ${response.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;
      UIUtils.showSnackBar(context, 'Error: $e', backgroundColor: Colors.red);
      _addDebugLog('Recording toggle error: $e');
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Update Camera Settings
  /// 
  /// Saves camera configuration changes to the API.
  Future<void> _updateSettings() async {
    if (!mounted) return;
    if (_camera.id == null) return;
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      final response = await _apiService.updateCameraSettings(
        _camera.id!,
        {
          'motion_detection': _motionDetectionEnabled,
          'night_vision': _nightVisionEnabled,
          'audio_enabled': _audioEnabled,
          'notifications_enabled': _notificationsEnabled,
          'sensitivity': _sensitivity,
        },
      );
      
      if (response.success) {
        if (!mounted) return;
        UIUtils.showSnackBar(context, 'Settings updated successfully', backgroundColor: Colors.green);
        _addDebugLog('Settings updated');
      } else {
        throw Exception('Failed to update settings: ${response.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;
      UIUtils.showSnackBar(context, 'Error updating settings: $e', backgroundColor: Colors.red);
      _addDebugLog('Settings update error: $e');
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Restart Camera
  /// 
  /// Sends a restart command to the camera system.
  Future<void> _restartCamera() async {
    if (!mounted) return;
    if (_camera.id == null) return;
    
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restart Camera'),
        content: const Text('Are you sure you want to restart this camera? This may take a few minutes.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Restart'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      final response = await _apiService.restartCamera(_camera.id!);
      
      if (response.success) {
        if (!mounted) return;
        UIUtils.showSnackBar(context, 'Camera restart initiated', backgroundColor: Colors.orange);
        _addDebugLog('Camera restart command sent');
        
        // Start rotation animation
        _rotationController.repeat();
        
        // Stop animation after 30 seconds
        Timer(const Duration(seconds: 30), () {
          _rotationController.stop();
          _rotationController.reset();
        });
      } else {
        throw Exception('Failed to restart camera: ${response.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;
      UIUtils.showSnackBar(context, 'Error restarting camera: $e', backgroundColor: Colors.red);
      _addDebugLog('Restart error: $e');
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotationController.dispose();
    _statusTimer?.cancel();
    socket?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = widget.camera;
    return Scaffold(
      appBar: AppBar(
        title: Text('Camera Details'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            ListTile(
              title: const Text('ID'),
              subtitle: Text(camera.id?.toString() ?? 'N/A'),
            ),
            ListTile(
              title: const Text('Date Creation'),
              subtitle: Text(camera.dateCreation?.toString() ?? 'N/A'),
            ),
            ListTile(
              title: const Text('Is Active'),
              subtitle: Text(camera.isActive ? 'Yes' : 'No'),
            ),
            ListTile(
              title: const Text('Is Recording'),
              subtitle: Text(camera.isRecording ? 'Yes' : 'No'),
            ),
            ListTile(
              title: const Text('Longitude'),
              subtitle: Text(camera.longitude?.toString() ?? 'N/A'),
            ),
            ListTile(
              title: const Text('Latitude'),
              subtitle: Text(camera.latitude?.toString() ?? 'N/A'),
            ),
            ListTile(
              title: const Text('Home ID'),
              subtitle: Text(camera.homeId.toString()),
            ),
            ListTile(
              title: const Text('Created At'),
              subtitle: Text(camera.createdAt?.toString() ?? 'N/A'),
            ),
            ListTile(
              title: const Text('Updated At'),
              subtitle: Text(camera.updatedAt?.toString() ?? 'N/A'),
            ),
          ],
        ),
      ),
    );
  }

  /// Build App Bar
  /// 
  /// Creates the app bar with camera name, status indicators, and menu options.
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_camera.name),
          Text(
            _camera.camCode,
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
        // Camera status
        Icon(
          _camera.isOnline ? Icons.videocam : Icons.videocam_off,
          color: _camera.isOnline ? Colors.green : Colors.red,
          size: 20,
        ),
        const SizedBox(width: 8),
        // Menu
        PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'restart':
                _restartCamera();
                break;
              case 'refresh':
                _loadCameraDetails();
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'restart',
              child: Row(
                children: [
                  Icon(Icons.restart_alt),
                  SizedBox(width: 8),
                  Text('Restart Camera'),
                ],
              ),
            ),
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
          ],
        ),
      ],
    );
  }

  /// Build Body
  /// 
  /// Creates the main content area with camera information and controls.
  Widget _buildBody() {
    if (_isLoading && _camera.id == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatusCard(),
          const SizedBox(height: 16),
          _buildControlsCard(),
          const SizedBox(height: 16),
          _buildSettingsCard(),
          const SizedBox(height: 16),
          _buildActivityCard(),
          const SizedBox(height: 16),
          _buildDebugCard(),
        ],
      ),
    );
  }

  /// Build Status Card
  /// 
  /// Creates a card showing current camera status and health information.
  Widget _buildStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  'Camera Status',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_camera.isRecording)
                  ScaleTransition(
                    scale: Tween(begin: 0.8, end: 1.2).animate(_pulseController),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'RECORDING',
                        style: TextStyle(color: Colors.white, fontSize: 10),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatusItem(
                    'Online',
                    _camera.isOnline ? 'Yes' : 'No',
                    _camera.isOnline ? Colors.green : Colors.red,
                  ),
                ),
                Expanded(
                  child: _buildStatusItem(
                    'Health',
                    _camera.healthStatus,
                    _getHealthColor(_camera.healthStatus),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildStatusItem(
                    'Recording',
                    _camera.isRecording ? 'Active' : 'Inactive',
                    _camera.isRecording ? Colors.red : Colors.grey,
                  ),
                ),
                Expanded(
                  child: _buildStatusItem(
                    'Streaming',
                    _camera.isStreaming ? 'Active' : 'Inactive',
                    _camera.isStreaming ? Colors.blue : Colors.grey,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Location: ${_camera.locationDescription}',
              style: const TextStyle(color: Colors.grey),
            ),
            Text(
              'Home: ${_camera.homeName}',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  /// Build Status Item
  /// 
  /// Creates a status item with label, value, and color coding.
  Widget _buildStatusItem(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  /// Get Health Color
  /// 
  /// Returns appropriate color for camera health status.
  Color _getHealthColor(String health) {
    switch (health.toLowerCase()) {
      case 'excellent':
        return Colors.green;
      case 'good':
        return Colors.lightGreen;
      case 'warning':
        return Colors.orange;
      case 'critical':
        return Colors.red;
      case 'offline':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  /// Build Controls Card
  /// 
  /// Creates a card with camera control buttons for streaming and recording.
  Widget _buildControlsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.control_camera, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  'Camera Controls',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _camera.isOnline ? _startCameraStream : null,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start Stream'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 48),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _camera.isOnline ? _toggleRecording : null,
                    icon: Icon(
                      _camera.isRecording ? Icons.stop : Icons.fiber_manual_record,
                    ),
                    label: Text(_camera.isRecording ? 'Stop Recording' : 'Start Recording'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _camera.isRecording ? Colors.red : Colors.green,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 48),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Build Settings Card
  /// 
  /// Creates a card with camera configuration settings and controls.
  Widget _buildSettingsCard() {
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
                  'Camera Settings',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Motion Detection'),
              subtitle: const Text('Detect movement and send alerts'),
              value: _motionDetectionEnabled,
              onChanged: (value) {
                setState(() {
                  _motionDetectionEnabled = value;
                });
              },
            ),
            SwitchListTile(
              title: const Text('Night Vision'),
              subtitle: const Text('Enable infrared night vision'),
              value: _nightVisionEnabled,
              onChanged: (value) {
                setState(() {
                  _nightVisionEnabled = value;
                });
              },
            ),
            SwitchListTile(
              title: const Text('Audio Recording'),
              subtitle: const Text('Record audio with video'),
              value: _audioEnabled,
              onChanged: (value) {
                setState(() {
                  _audioEnabled = value;
                });
              },
            ),
            SwitchListTile(
              title: const Text('Push Notifications'),
              subtitle: const Text('Receive alerts on your device'),
              value: _notificationsEnabled,
              onChanged: (value) {
                setState(() {
                  _notificationsEnabled = value;
                });
              },
            ),
            const SizedBox(height: 16),
            Text(
              'Motion Sensitivity: ${( _sensitivity * 100).round()}%',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            Slider(
              value: _sensitivity,
              onChanged: (value) {
                setState(() {
                  _sensitivity = value;
                });
              },
              divisions: 10,
              label: '${( _sensitivity * 100).round()}%',
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _updateSettings,
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

  /// Build Activity Card
  /// 
  /// Creates a card showing recent camera activities and events.
  Widget _buildActivityCard() {
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
                  'Recent Activity',
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
                        'No recent activity',
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
                            color: _getActivityColor(activity.type),
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

  /// Build Floating Action Button
  /// 
  /// Creates a floating action button for quick camera stream access.
  Widget _buildFloatingActionButton() {
    return FloatingActionButton.extended(
      onPressed: _camera.isOnline ? _startCameraStream : null,
      backgroundColor: _camera.isOnline 
          ? Theme.of(context).floatingActionButtonTheme.backgroundColor
          : Colors.grey,
      foregroundColor: Colors.white,
      icon: const Icon(Icons.videocam),
      label: const Text('Live View'),
    );
  }

  /// Get Activity Icon
  /// 
  /// Returns appropriate icon for activity type.
  IconData _getActivityIcon(String type) {
    switch (type) {
      case 'motion_detected':
        return Icons.directions_run;
      case 'recording_started':
        return Icons.fiber_manual_record;
      case 'recording_stopped':
        return Icons.stop;
      case 'stream_started':
        return Icons.play_arrow;
      case 'stream_stopped':
        return Icons.stop;
      case 'camera_online':
        return Icons.power;
      case 'camera_offline':
        return Icons.power_off;
      default:
        return Icons.info;
    }
  }

  /// Get Activity Color
  /// 
  /// Returns appropriate color for activity type.
  Color _getActivityColor(String type) {
    switch (type) {
      case 'motion_detected':
        return Colors.orange;
      case 'recording_started':
        return Colors.red;
      case 'recording_stopped':
        return Colors.grey;
      case 'stream_started':
        return Colors.blue;
      case 'stream_stopped':
        return Colors.grey;
      case 'camera_online':
        return Colors.green;
      case 'camera_offline':
        return Colors.red;
      default:
        return Colors.blue;
    }
  }
}


