import 'package:flutter/material.dart';
import 'package:bellui/services/api_service.dart';
import 'package:bellui/models/models.dart';
import 'package:bellui/utils/utils.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'dart:async';
import 'dart:convert'; // Added for json.decode

// Import the video call page
import 'package:bellui/pages/video_call_page.dart'; // Corrected import path

class CameraDetailPage extends StatefulWidget {
  final Camera camera;

  const CameraDetailPage({super.key, required this.camera});

  @override
  State<CameraDetailPage> createState() => _CameraDetailPageState();
}

class _CameraDetailPageState extends State<CameraDetailPage>
        // Show incoming call dialog and trigger signaling for testcall-initiated calls
        with
        TickerProviderStateMixin {
  // Show incoming call dialog and trigger signaling for testcall-initiated calls
  void _showIncomingCallDialog(Map<String, dynamic> data) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Incoming Call'),
          content: Text('Camera is calling you. Accept the call?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                socket?.emit('camera_response', {
                  'room': _camera.camCode,
                  'response': 'refused',
                  'timestamp': DateTime.now().toIso8601String(),
                });
                _addDebugLog('Call rejected by user.');
                UIUtils.showSnackBar(
                  context,
                  'Call rejected.',
                  backgroundColor: Colors.red,
                );
              },
              child: const Text('Reject'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                socket?.emit('camera_response', {
                  'room': _camera.camCode,
                  'response': 'accepted',
                  'timestamp': DateTime.now().toIso8601String(),
                });
                _addDebugLog('Call accepted by user. Signaling triggered.');
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => VideoCallPage(
                      roomId: _camera.camCode,
                      cameraCode: _camera.camCode,
                      camera: _camera,
                      existingSocket: socket,
                      isMainAppCall: false,
                    ),
                  ),
                );
              },
              child: const Text('Accept'),
            ),
          ],
        );
      },
    );
  }

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
  final List<String> _debugLogs = [];

  // API service instance
  final ApiService _apiService = ApiService();

  // NEW: Camera control states
  bool _isCameraOn = false;
  bool _isCameraOnline = false;
  String _cameraStatus = 'Offline';

  @override
  void initState() {
    super.initState();
    _camera = widget.camera;
    _initializeAnimations();
    _initializeSocket();

    // Initialize camera status from camera object
    _isCameraOn = _camera.isActive;
    _isCameraOnline = _camera.isOnline;
    _cameraStatus = _camera.healthStatus;
  }

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

      // Register all socket event listeners after socket is initialized
      socket!.on('incoming_call', (data) {
        _addDebugLog('🔔 [SOCKET EVENT] incoming_call: $data');
        _showIncomingCallDialog(data is Map<String, dynamic> ? data : {});
      });

      socket!.onConnect((_) {
        setState(() {
          isSocketConnected = true;
        });

        // Join camera-specific room for updates
        socket!.emit('join_camera_room', {'camera_code': _camera.camCode});

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

      // NEW: Handle camera status updates from testing app
      socket!.on('camera_status_changed', (data) {
        _addDebugLog('📊 [SOCKET EVENT] Camera status changed: $data');
        setState(() {
          _isCameraOnline = data['is_online'] ?? false;
          _isCameraOn = data['is_camera_on'] ?? false;
          _cameraStatus = data['status'] ?? 'Offline';
        });

        // Update camera object
        _camera = _camera.copyWith(
          isOnline: _isCameraOnline,
          isActive: _isCameraOn,
          healthStatus: _cameraStatus,
        );

        _addDebugLog(
          '📊 Camera status updated: $_cameraStatus (Online: $_isCameraOnline, Camera: $_isCameraOn)',
        );
      });

      // NEW: Handle call initiation responses
      socket!.on('call_accepted', (data) {
        _addDebugLog('✅ [SOCKET EVENT] Call accepted by camera: $data');
        UIUtils.showSnackBar(
          context,
          'Call accepted by camera!',
          backgroundColor: Colors.green,
        );

        // Navigate to video call page
        _navigateToVideoCall();
      });

      socket!.on('call_rejected', (data) {
        _addDebugLog('❌ [SOCKET EVENT] Call rejected by camera: $data');
        final reason = data['reason'] ?? 'Unknown reason';
        UIUtils.showSnackBar(
          context,
          'Call rejected: $reason',
          backgroundColor: Colors.red,
        );
      });

      socket!.on('call_initiation_failed', (data) {
        _addDebugLog('❌ [SOCKET EVENT] Call initiation failed: $data');
        final message = data['message'] ?? 'Failed to initiate call';
        UIUtils.showSnackBar(context, message, backgroundColor: Colors.red);
      });

      // NEW: Handle camera control feedback
      socket!.on('camera_control_response', (data) {
        _addDebugLog('🎛️ [SOCKET EVENT] Camera control response: $data');
        final success = data['success'] ?? false;
        final message = data['message'] ?? '';
        final command = data['command'] ?? '';

        if (success) {
          UIUtils.showSnackBar(
            context,
            'Camera control: $message',
            backgroundColor: Colors.green,
          );

          // Update local state based on command
          if (command == 'turn_on') {
            setState(() {
              _isCameraOn = true;
            });
            _addDebugLog('🎛️ Camera turned on locally');
          } else if (command == 'turn_off') {
            setState(() {
              _isCameraOn = false;
            });
            _addDebugLog('🎛️ Camera turned off locally');
          } else if (command == 'toggle') {
            setState(() {
              _isCameraOn = !_isCameraOn;
            });
            _addDebugLog('🎛️ Camera toggled locally: $_isCameraOn');
          }
        } else {
          UIUtils.showSnackBar(
            context,
            'Camera control failed: $message',
            backgroundColor: Colors.red,
          );
        }
      });

      // NEW: Handle camera status response
      socket!.on('camera_status_response', (data) {
        _addDebugLog('📊 [SOCKET EVENT] Camera status response: $data');
        final cameraCode = data['camera_code'] ?? '';

        if (cameraCode == _camera.camCode) {
          setState(() {
            _isCameraOnline = data['is_online'] ?? false;
            _isCameraOn = data['is_camera_on'] ?? false;
            _cameraStatus = data['status'] ?? 'Offline';
          });

          _addDebugLog(
            '📊 Camera status updated from response: $_cameraStatus (Online: $_isCameraOnline, Camera: $_isCameraOn)',
          );
          UIUtils.showSnackBar(
            context,
            'Camera status refreshed',
            backgroundColor: Colors.blue,
          );
        }
      });

      // NEW: Handle camera turned on response
      socket!.on('camera_turned_on', (data) {
        _addDebugLog('🎛️ [SOCKET EVENT] Camera turned on response: $data');
        final cameraCode = data['camera_code'] ?? '';
        final success = data['success'] ?? false;

        if (cameraCode == _camera.camCode) {
          if (success) {
            setState(() {
              _isCameraOn = true;
            });
            _addDebugLog('🎛️ Camera turned on successfully');
            UIUtils.showSnackBar(
              context,
              'Camera turned on successfully',
              backgroundColor: Colors.green,
            );
          } else {
            setState(() {
              _isCameraOn = false;
            });
            _addDebugLog('❌ Failed to turn on camera');
            UIUtils.showSnackBar(
              context,
              'Failed to turn on camera',
              backgroundColor: Colors.red,
            );
          }
        }
      });
      socket!.on('camera_turned_off', (data) {
        _addDebugLog('🎛️ [SOCKET EVENT] Camera turned off response: $data');
        final cameraCode = data['camera_code'] ?? '';
        final success = data['success'] ?? false;

        if (cameraCode == _camera.camCode) {
          if (success) {
            setState(() {
              _isCameraOn = false;
            });
            _addDebugLog('🎛️ Camera turned off successfully');
            UIUtils.showSnackBar(
              context,
              'Camera turned off successfully',
              backgroundColor: Colors.green,
            );
          } else {
            setState(() {
              _isCameraOn = false;
            });
            _addDebugLog('❌ Failed to turn off camera');
            UIUtils.showSnackBar(
              context,
              'Failed to turn off camera',
              backgroundColor: Colors.red,
            );
          }
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
      UIUtils.showSnackBar(
        context,
        'Socket connection error: $e',
        backgroundColor: Colors.red,
      );
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

      _addDebugLog(
        'Status updated: Online=${_camera.isOnline}, Recording=${_camera.isRecording}',
      );

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
        // _activities.insert(0, activity); // Removed
        // if (_activities.length > 50) { // Removed
        //   _activities.removeLast(); // Removed
        // } // Removed
      });

      _addDebugLog('Motion detected at ${DateTime.now()}');

      // Show notification if enabled
      // if (_notificationsEnabled) { // Removed
      //   UIUtils.showSnackBar(context, 'Motion detected!', backgroundColor: Colors.orange); // Removed
      // } // Removed
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
      UIUtils.showSnackBar(
        context,
        'Recording started',
        backgroundColor: Colors.green,
      );
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
      UIUtils.showSnackBar(
        context,
        'Recording stopped',
        backgroundColor: Colors.red,
      );
    }
  }

  /// Handle Camera Error
  ///
  /// Processes camera error events and displays appropriate messages.
  void _handleCameraError(dynamic data) {
    if (data['camera_code'] == _camera.camCode) {
      final error = data['error'] ?? 'Unknown error';
      _addDebugLog('Camera error: $error');
      UIUtils.showSnackBar(
        context,
        'Camera error: $error',
        backgroundColor: Colors.red,
      );
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
    if (_camera.isOnline) {
      UIUtils.showSnackBar(
        context,
        'Camera is offline',
        backgroundColor: Colors.red,
      );
      return;
    }

    // Emit start_call1 to trigger testcall to start the call
    socket?.emit('start_call1', {'room': _camera.camCode});

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
      // _checkCameraStatus(); // Removed
    });
  }

  // Navigate to video call page
  void _navigateToVideoCall({bool isMainAppCall = true}) {
    socket!.emit('start_call1', {'room': _camera.camCode});
    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoCallPage(
          roomId: _camera.camCode,
          cameraCode: _camera.camCode,
          camera: _camera,
          existingSocket: socket,
          isMainAppCall: isMainAppCall,
        ),
      ),
    );
  }

  // NEW: Helper methods for call button states
  bool _getCallButtonEnabled() {
    return _isCameraOn; // Only check if camera is active
  }

  String _getCallButtonText() {
    if (!_isCameraOn) {
      return 'Camera Inactive';
    } else {
      return 'start call';
    }
  }

  Color _getCallButtonColor() {
    if (!_isCameraOn) {
      return Colors.grey;
    } else {
      return Colors.green;
    }
  }

  // NEW: Method to turn camera on
  void _turnCameraOn() {
    if (!mounted) return;
    if (_isCameraOn) return; // Prevent double clicks

    setState(() {
      _isCameraOn = true;
    });

    socket!.emit('camera_turned_on', {
      'camera_code': _camera.camCode,
      'success': true,
      'message': 'Camera turned on successfully',
      'timestamp': DateTime.now().toIso8601String(),
    });
    _addDebugLog('Attempting to turn camera on...');
  }

  // NEW: Method to turn camera off
  void _turnCameraOff() {
    if (!mounted) return;
    if (!_isCameraOn) return; // Prevent double clicks

    setState(() {
      _isCameraOn = false;
    });

    socket!.emit('camera_turned_off', {
      'camera_code': _camera.camCode,
      'success': true,
      'message': 'Camera turned off successfully',
      'timestamp': DateTime.now().toIso8601String(),
    });
    _addDebugLog('Attempting to turn camera off...');
  }

  // NEW: Method to get camera status
  void _getCameraStatus() {
    if (!mounted) return;

    socket!.emit('get_camera_status', {'camera_code': _camera.camCode});
    _addDebugLog('Requesting camera status...');
  }

  void _toggleCamera() {
    if (!mounted) return;
    if (_isCameraOn) {
      _turnCameraOff();
    } else {
      _turnCameraOn();
    }
  }

  @override
  void dispose() {
    socket!.emit('leave', {'room': _camera.camCode});
    debugPrint('📡 Left room ${_camera.camCode}');
    _pulseController.dispose();
    _rotationController.dispose();
    _statusTimer?.cancel();
    socket?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: _buildAppBar(), body: _buildBody());
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
                // _restartCamera(); // Removed
                break;
              case 'refresh':
                // _loadCameraDetails(); // Removed
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
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCameraInfoCard(),
          const SizedBox(height: 16),
          _buildControlsCard(),
          const SizedBox(height: 16),
          _buildDebugCard(),
        ],
      ),
    );
  }

  /// Build Status Card
  ///

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

            // NEW: Simplified camera activity status
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _isCameraOn
                    ? Colors.green.shade100
                    : Colors.red.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _isCameraOn ? Colors.green : Colors.red,
                  width: 2,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    'Camera Activity',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: _isCameraOn
                          ? Colors.green.shade800
                          : Colors.red.shade800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isCameraOn ? 'ACTIVE' : 'INACTIVE',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: _isCameraOn
                          ? Colors.green.shade800
                          : Colors.red.shade800,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Call button - navigate to video call
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _getCallButtonEnabled()
                    ? _navigateToVideoCall
                    : null,
                icon: const Icon(Icons.call),
                label: Text(_getCallButtonText()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _getCallButtonColor(),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 48),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Turn On Camera button (when camera is inactive)
            // Camera Toggle Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _toggleCamera,
                icon: Icon(_isCameraOn ? Icons.videocam_off : Icons.videocam),
                label: Text(_isCameraOn ? 'Turn Off Camera' : 'Turn On Camera'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isCameraOn ? Colors.red : Colors.green,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 48),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // NEW: Refresh Status button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _getCameraStatus,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh Camera Status'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 48),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Start stream button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isCameraOn ? _startCameraStream : null,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start Stream'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isCameraOn ? Colors.blue : Colors.grey,
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

  Widget _buildCameraInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Camera Info',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildInfoRow('ID', _camera.id?.toString() ?? 'N/A'),
            _buildInfoRow('Code', _camera.camCode),
            _buildInfoRow('Home ID', _camera.homeId.toString()),
            _buildInfoRow('Created At', _camera.createdAt?.toString() ?? 'N/A'),
            _buildInfoRow('Updated At', _camera.updatedAt?.toString() ?? 'N/A'),
            _buildInfoRow(
              'Date Creation',
              _camera.dateCreation?.toString() ?? 'N/A',
            ),
            _buildInfoRow('Longitude', _camera.longitude?.toString() ?? 'N/A'),
            _buildInfoRow('Latitude', _camera.latitude?.toString() ?? 'N/A'),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 110,
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
