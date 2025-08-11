import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

class VideoCallPage extends StatefulWidget {
  final String cameraCode;

  const VideoCallPage({super.key, required this.cameraCode});

  @override
  State<VideoCallPage> createState() => _VideoCallPageState();
}

class _VideoCallPageState extends State<VideoCallPage> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  io.Socket? socket;
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;

  String _connectionStatus = 'Connecting...';
  String _iceConnectionState = 'New';
  bool _isCallActive = false;
  bool _isMuted = false;
  List<String> _debugLogs = [];

  // NEW: Camera control states
  bool _isCameraOn = false;
  bool _isCameraOnline = false;
  String _cameraStatus = 'Offline';

  // Configuration - UPDATE THIS URL
  final String signalingServerUrl = 'https://b626468b61a3.ngrok-free.app';

  @override
  void initState() {
    super.initState();
    _initRenderers();
    _connectToServer();
    _addDebugLog('📱 Video Call Page Started for camera: ${widget.cameraCode}');
  }

  void _addDebugLog(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    setState(() {
      _debugLogs.add('[$timestamp] $message');
      if (_debugLogs.length > 50) {
        _debugLogs.removeAt(0);
      }
    });
    debugPrint(message);
  }

  Future<void> _initRenderers() async {
    try {
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();
      _addDebugLog('✅ Video renderers initialized');
    } catch (e) {
      _addDebugLog('❌ Failed to initialize video renderers: $e');
    }
  }

  void _connectToServer() async {
    try {
      _addDebugLog('🔗 Connecting to signaling server...');

      socket = io.io(signalingServerUrl, <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': false,
        'timeout': 20000,
      });

      _setupSocketEventHandlers();
      socket!.connect();
    } catch (e) {
      _addDebugLog('❌ Connection error: $e');
      _updateStatus('Connection Error');
    }
  }

  void _setupSocketEventHandlers() {
    // Connection events
    socket!.onConnect((_) async {
      _addDebugLog('✅ Connected to signaling server');
      _updateStatus('Connected - setting up call...');

      // Set camera online but not active yet
      setState(() {
        _isCameraOnline = true;
        _cameraStatus = 'Online'; // Online but not active until turned on
      });

      // Join room as camera device
      socket!.emit('join_room', {
        'room': widget.cameraCode,
        'client_type': 'camera',
      });
      _addDebugLog('📹 Joining room: ${widget.cameraCode} as camera device');

      // Report camera status to update database
      _reportCameraStatus();

      // Also report camera as connected to database
      _reportCameraConnected();
    });

    socket!.onConnectError((err) {
      _addDebugLog('❌ Connection error: $err');
      _updateStatus('Connection Error');
      _setCameraOffline();
    });

    socket!.onDisconnect((_) {
      _addDebugLog('❌ Disconnected from server');
      _updateStatus('Disconnected');
      _setCameraOffline();

      // Report camera disconnected to database
      _reportCameraDisconnected();
    });

    // NEW: Handle incoming call requests from main app
    socket!.on('incoming_call', (data) {
      _addDebugLog('📞 Incoming call request from main app');
      _handleIncomingCall(data);
    });

    // NEW: Handle camera status requests
    socket!.on('get_camera_status', (data) {
      _addDebugLog('📊 Camera status requested');
      _reportCameraStatus();

      // NEW: Send direct response to main app
      socket!.emit('camera_status_response', {
        'camera_code': widget.cameraCode,
        'is_online': _isCameraOnline,
        'is_camera_on': _isCameraOn,
        'status': _cameraStatus,
        'timestamp': DateTime.now().toIso8601String(),
      });
      _addDebugLog('📊 Camera status response sent to main app');
    });

    // NEW: Handle camera control commands
    socket!.on('camera_control', (data) {
      _addDebugLog('🎛️ [SOCKET EVENT] Camera control command: $data');
      final command = data['command'] ?? '';
      _addDebugLog('🎛️ Raw command from data: "$command"');
      _addDebugLog('🎛️ Command type: ${command.runtimeType}');
      _addDebugLog('🎛️ Command length: ${command.length}');
      _addDebugLog('🎛️ Command bytes: ${command.codeUnits}');
      _handleCameraControl(command);
    });

    // NEW: Handle turn on camera command
    socket!.on('camera_turned_on', (data) {
      _addDebugLog('🎛️ [SOCKET EVENT] Turn on camera command received: $data');
      final cameraCode = data['camera_code'] ?? '';

      if (cameraCode == widget.cameraCode) {
        _turnCameraOn();

        // Send response back to main app
        socket!.emit('camera_turned_on', {
          'camera_code': widget.cameraCode,
          'success': true,
          'message': 'Camera turned on successfully',
          'timestamp': DateTime.now().toIso8601String(),
        });

        _addDebugLog('🎛️ Camera turned on and response sent');
      }
    });

    // WebRTC events
    socket!.on('offer', (data) async {
      _addDebugLog('📥 Received offer from mobile client');
      await _handleOffer(data);
    });

    socket!.on('ice_candidate', (data) async {
      _addDebugLog('🧊 Received ICE candidate from mobile client');
      await _handleIceCandidate(data);
    });

    socket!.on('answer', (data) async {
      _addDebugLog('📥 Received answer from mobile client');
      await _handleAnswer(data);
    });

    socket!.on('end_call', (data) {
      _addDebugLog('📞 Call ended by mobile client');
      _endCall();
    });
  }

  Future<void> _setupPeerConnection() async {
    try {
      _addDebugLog('🔗 Setting up peer connection...');

      final Map<String, dynamic> config = {
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'},
          {'urls': 'stun:stun2.l.google.com:19302'},
          {
            'urls': 'turn:openrelay.metered.ca:80',
            'username': 'openrelayproject',
            'credential': 'openrelayproject',
          },
        ],
        'iceCandidatePoolSize': 10,
        'bundlePolicy': 'max-bundle',
        'rtcpMuxPolicy': 'require',
      };

      _peerConnection = await createPeerConnection(config);
      _addDebugLog('✅ Peer connection created');

      _setupPeerConnectionHandlers();
    } catch (e) {
      _addDebugLog('❌ Peer connection setup error: $e');
      rethrow;
    }
  }

  void _setupPeerConnectionHandlers() {
    // Handle incoming remote stream (video and audio from camera)
    _peerConnection!.onTrack = (event) {
      _addDebugLog('📡 Received remote track from camera');
      _addDebugLog('🎬 Track kind: ${event.track.kind}, ID: ${event.track.id}');

      if (event.streams.isNotEmpty) {
        final remoteStream = event.streams[0];
        _addDebugLog(
          '📹 Remote stream has ${remoteStream.getTracks().length} tracks',
        );

        // Debug track information
        remoteStream.getTracks().forEach((track) {
          _addDebugLog(
            '🎬 Remote ${track.kind} track - enabled: ${track.enabled}, ID: ${track.id}',
          );
        });

        setState(() {
          _remoteRenderer.srcObject = remoteStream;
          _isCallActive = true;
        });

        _addDebugLog('✅ Remote stream set to renderer');
        _updateStatus('Video call active!');
      } else {
        _addDebugLog('⚠️ Received track but no streams available');
      }
    };

    // ICE candidate handling
    _peerConnection!.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        _addDebugLog('🧊 Sending ICE candidate to mobile client');
        socket!.emit('ice_candidate', {
          'room': widget.cameraCode,
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      } else {
        _addDebugLog('🧊 ICE gathering complete');
      }
    };

    // Connection state monitoring
    _peerConnection!.onIceConnectionState = (state) {
      _addDebugLog('🔗 ICE connection state: $state');
      setState(() => _iceConnectionState = state.toString());

      switch (state) {
        case RTCIceConnectionState.RTCIceConnectionStateConnected:
          _updateStatus('Connected!');
          break;
        case RTCIceConnectionState.RTCIceConnectionStateCompleted:
          _updateStatus('Connection established');
          break;
        case RTCIceConnectionState.RTCIceConnectionStateFailed:
          _addDebugLog('❌ ICE connection failed');
          _updateStatus('Connection failed');
          break;
        case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
          _updateStatus('Connection lost');
          break;
        case RTCIceConnectionState.RTCIceConnectionStateClosed:
          _updateStatus('Call ended');
          _endCall();
          break;
        default:
          _updateStatus('ICE: $state');
      }
    };

    _peerConnection!.onConnectionState = (state) {
      _addDebugLog('🔗 Peer connection state: $state');
    };

    _peerConnection!.onSignalingState = (state) {
      _addDebugLog('📡 Signaling state: $state');
    };

    _peerConnection!.onIceGatheringState = (state) {
      _addDebugLog('🧊 ICE gathering state: $state');
    };
  }

  Future<void> _startLocalStream() async {
    try {
      _addDebugLog('📹 Starting local video and audio stream...');

      final Map<String, dynamic> mediaConstraints = {
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': {
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
          'frameRate': {'ideal': 30},
        },
      };

      _localStream = await navigator.mediaDevices.getUserMedia(
        mediaConstraints,
      );

      if (_localStream != null) {
        _localRenderer.srcObject = _localStream;

        _addDebugLog('✅ Local stream started successfully');
        _addDebugLog(
          '📊 Local stream tracks: ${_localStream!.getTracks().length}',
        );

        // Log track details
        _localStream!.getTracks().forEach((track) {
          _addDebugLog(
            '🎬 Local ${track.kind} track: ${track.id} - enabled: ${track.enabled}',
          );
        });
      } else {
        throw Exception('Failed to get media stream');
      }
    } catch (e) {
      _addDebugLog('❌ Media stream error: $e');
      // Try with simpler constraints
      try {
        _addDebugLog('🔄 Retrying with simpler constraints...');
        final simpleConstraints = {'audio': true, 'video': true};

        _localStream = await navigator.mediaDevices.getUserMedia(
          simpleConstraints,
        );
        if (_localStream != null) {
          _localRenderer.srcObject = _localStream;
          _addDebugLog('✅ Local stream started with simple constraints');
        }
      } catch (retryError) {
        _addDebugLog('❌ Retry failed: $retryError');
      }
    }
  }

  Future<void> _handleOffer(dynamic data) async {
    try {
      _addDebugLog('📞 Processing offer from mobile client...');
      _addDebugLog('📄 Offer SDP type: ${data['sdp']['type']}');

      final offer = RTCSessionDescription(
        data['sdp']['sdp'],
        data['sdp']['type'],
      );
      await _peerConnection!.setRemoteDescription(offer);
      _addDebugLog('✅ Remote description (offer) set');

      // Add local stream tracks to peer connection BEFORE creating answer
      if (_localStream != null) {
        _localStream!.getTracks().forEach((track) {
          _peerConnection!.addTrack(track, _localStream!);
          _addDebugLog(
            '➕ Added ${track.kind} track to peer connection: ${track.id}',
          );
        });
      } else {
        _addDebugLog('⚠️ No local stream available to add to peer connection');
      }

      // Create and send answer
      await _createAndSendAnswer();
    } catch (e) {
      _addDebugLog('❌ Error in handleOffer: $e');
    }
  }

  Future<void> _createAndSendAnswer() async {
    try {
      _addDebugLog('📞 Creating answer...');

      // Create answer - mobile sends audio, expects video+audio
      final Map<String, dynamic> answerOptions = {
        'offerToReceiveAudio': true, // We want to receive audio from camera
        'offerToReceiveVideo': true, // We want to receive video from camera
      };

      final answer = await _peerConnection!.createAnswer(answerOptions);

      // Log SDP details for debugging
      _addDebugLog('📄 Answer SDP type: ${answer.type}');
      _addDebugLog(
        '📄 Answer SDP (first 100 chars): ${answer.sdp?.substring(0, 100)}...',
      );

      await _peerConnection!.setLocalDescription(answer);
      _addDebugLog('✅ Local description (answer) set');

      socket!.emit('answer', {
        'room': widget.cameraCode,
        'sdp': answer.toMap(),
      });
      _addDebugLog('📤 Answer sent to mobile client');
    } catch (e) {
      _addDebugLog('❌ Error creating/sending answer: $e');
    }
  }

  Future<void> _handleIceCandidate(dynamic data) async {
    try {
      if (_peerConnection == null) {
        _addDebugLog('⚠️ Received ICE candidate but no peer connection');
        return;
      }

      final candidate = RTCIceCandidate(
        data['candidate'],
        data['sdpMid'],
        data['sdpMLineIndex'],
      );
      await _peerConnection!.addCandidate(candidate);
      _addDebugLog('✅ ICE candidate added');
    } catch (e) {
      _addDebugLog('❌ Error adding ICE candidate: $e');
    }
  }

  Future<void> _handleAnswer(dynamic data) async {
    try {
      _addDebugLog('📞 Processing answer from mobile client...');
      _addDebugLog('📄 Answer SDP type: ${data['sdp']['type']}');

      final answer = RTCSessionDescription(
        data['sdp']['sdp'],
        data['sdp']['type'],
      );
      await _peerConnection!.setRemoteDescription(answer);
      _addDebugLog('✅ Remote description (answer) set');
    } catch (e) {
      _addDebugLog('❌ Error in handleAnswer: $e');
    }
  }

  void _toggleMute() {
    if (_localStream != null) {
      final audioTracks = _localStream!.getAudioTracks();
      if (audioTracks.isNotEmpty) {
        final audioTrack = audioTracks[0];
        audioTrack.enabled = !audioTrack.enabled;
        setState(() {
          _isMuted = !audioTrack.enabled;
        });
        _addDebugLog('🎤 Audio ${_isMuted ? 'muted' : 'unmuted'}');
      }
    }
  }

  void _endCall() {
    _addDebugLog('📞 Ending call...');

    if (socket != null) {
      socket!.emit('end_call', {'room': widget.cameraCode});
    }

    setState(() {
      _isCallActive = false;
      _remoteRenderer.srcObject = null;
    });

    if (_peerConnection != null) {
      _peerConnection!.close();
      _peerConnection = null;
    }

    if (_localStream != null) {
      _localStream!.dispose();
      _localStream = null;
    }

    // Navigate back to home screen
    Navigator.of(context).pop();
  }

  void _updateStatus(String status) {
    if (mounted) {
      setState(() => _connectionStatus = status);
    }
  }

  // NEW: Report camera status to server
  void _reportCameraStatus() {
    if (socket?.connected == true) {
      final status = {
        'camera_code': widget.cameraCode,
        'is_online': _isCameraOnline,
        'is_camera_on': _isCameraOn,
        'status': _cameraStatus,
        'timestamp': DateTime.now().toIso8601String(),
      };

      socket!.emit('camera_status_update', status);
      _addDebugLog('📊 Camera status reported: $_cameraStatus');
    }
  }

  // NEW: Report camera connected to database
  void _reportCameraConnected() {
    if (socket?.connected == true) {
      final connectionData = {
        'camera_code': widget.cameraCode,
        'is_online': true,
        'is_camera_on': _isCameraOn,
        'status': 'online',
        'timestamp': DateTime.now().toIso8601String(),
      };

      socket!.emit('camera_status_update', connectionData);
      _addDebugLog('🗄️ Camera connected status reported to database');
    }
  }

  // NEW: Report camera disconnected to database
  void _reportCameraDisconnected() {
    if (socket?.connected == true) {
      final disconnectedData = {
        'camera_code': widget.cameraCode,
        'is_online': false,
        'is_camera_on': _isCameraOn,
        'status': 'offline',
        'timestamp': DateTime.now().toIso8601String(),
      };
      socket!.emit('camera_status_update', disconnectedData);
      _addDebugLog('🗄️ Camera disconnected status reported to database');
    }
  }

  // NEW: Report camera active to database
  void _reportCameraActive() {
    if (socket?.connected == true) {
      final activeData = {
        'camera_code': widget.cameraCode,
        'is_online': _isCameraOnline,
        'is_camera_on': true,
        'status': 'active',
        'timestamp': DateTime.now().toIso8601String(),
      };
      socket!.emit('camera_status_update', activeData);
      _addDebugLog('🗄️ Camera active status reported to database');
    }
  }

  // NEW: Report camera inactive to database
  void _reportCameraInactive() {
    if (socket?.connected == true) {
      final inactiveData = {
        'camera_code': widget.cameraCode,
        'is_online': _isCameraOnline,
        'is_camera_on': false,
        'status': 'inactive',
        'timestamp': DateTime.now().toIso8601String(),
      };
      socket!.emit('camera_status_update', inactiveData);
      _addDebugLog('🗄️ Camera inactive status reported to database');
    }
  }

  // NEW: Set camera offline
  void _setCameraOffline() {
    setState(() {
      _isCameraOnline = false;
      _cameraStatus = 'Offline';
    });
    _reportCameraStatus();
  }

  // NEW: Handle incoming call from main app
  void _handleIncomingCall(data) {
    if (!_isCameraOn) {
      _addDebugLog('❌ Cannot accept call - camera is off');
      socket!.emit('call_rejected', {
        'camera_code': widget.cameraCode,
        'reason': 'camera_off',
        'timestamp': DateTime.now().toIso8601String(),
      });
      return;
    }

    _addDebugLog('✅ Accepting incoming call');
    socket!.emit('call_accepted', {
      'camera_code': widget.cameraCode,
      'timestamp': DateTime.now().toIso8601String(),
    });

    // Setup peer connection for the call
    _setupPeerConnection();
  }

  // NEW: Handle camera control commands
  void _handleCameraControl(String command) {
    _addDebugLog(
      '🎛️ Handling camera control command: "$command" (length:  [36m${command.length} [0m)',
    );
    _addDebugLog('🎛️ Command bytes: ${command.codeUnits}');
    _addDebugLog('🎛️ Command runtime type: ${command.runtimeType}');

    final normalizedCommand = command.trim().toLowerCase();
    _addDebugLog('🎛️ Normalized command: "$normalizedCommand"');

    if (normalizedCommand.contains('off')) {
      _addDebugLog('🎛️ Detected "off" in command, turning camera off.');
      _turnCameraOff();
    } else if (normalizedCommand.contains('on')) {
      _addDebugLog('🎛️ Detected "on" in command, turning camera on.');
      _turnCameraOn();
    } else if (normalizedCommand.contains('toggle')) {
      _addDebugLog('🎛️ Detected "toggle" in command, toggling camera.');
      if (_isCameraOn) {
        _turnCameraOff();
      } else {
        _turnCameraOn();
      }
    } else {
      _addDebugLog('❌ Unknown camera control command: "$command"');
      _addDebugLog('❌ Normalized command: "$normalizedCommand"');
      _addDebugLog('❌ Available commands: turn_on, turn_off, toggle');
    }
  }

  // NEW: Turn camera on
  void _turnCameraOn() async {
    setState(() {
      _isCameraOn = true;
      _cameraStatus = 'Active';
    });
    _addDebugLog('✅ Camera turned ON - Status: Active');

    // Start local stream when camera is turned on
    await _startLocalStream();

    _reportCameraStatus();

    // Also report camera as active to database
    _reportCameraActive();

    // NEW: Send control response to main app
    socket!.emit('camera_control_response', {
      'camera_code': widget.cameraCode,
      'command': 'turn_on',
      'success': true,
      'message': 'Camera turned on successfully',
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  // NEW: Turn camera off
  void _turnCameraOff() {
    setState(() {
      _isCameraOn = false;
      _cameraStatus = 'Inactive';
    });
    _addDebugLog('❌ Camera turned OFF - Status: Inactive');

    // Dispose local stream when camera is turned off
    if (_localStream != null) {
      _localStream!.dispose();
      _localStream = null;
      _localRenderer.srcObject = null;
      _addDebugLog('📹 Local stream disposed');
    }

    _reportCameraStatus();

    // Also report camera as inactive to database
    _reportCameraInactive();

    // NEW: Send control response to main app
    socket!.emit('camera_control_response', {
      'camera_code': widget.cameraCode,
      'command': 'turn_off',
      'success': true,
      'message': 'Camera turned off successfully',
      'timestamp': DateTime.now().toIso8601String(),
    });

    // End any active call
    if (_isCallActive) {
      _endCall();
    }
  }

  // NEW: Ring bell function (for testing)
  void _ringBell() {
    if (!_isCameraOn) {
      _addDebugLog('❌ Cannot ring bell - camera is off');
      return;
    }

    _addDebugLog('🔔 Ringing bell...');
    socket!.emit('ring_bell', {
      'camera_code': widget.cameraCode,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  @override
  void dispose() {
    _endCall();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    socket?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Camera Simulator - ${widget.cameraCode}'),
        backgroundColor: _isCameraOn ? Colors.green : Colors.red,
        foregroundColor: Colors.white,
        actions: [
          // Camera status indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _isCameraOn ? Colors.green.shade700 : Colors.red.shade700,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _isCameraOn ? 'ON' : 'OFF',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          // Camera status bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: _isCameraOn ? Colors.green.shade100 : Colors.red.shade100,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Camera Status: $_cameraStatus',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: _isCameraOn
                            ? Colors.green.shade800
                            : Colors.red.shade800,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _isCameraOnline ? Colors.green : Colors.red,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _isCameraOnline ? 'ONLINE' : 'OFFLINE',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Connection: $_connectionStatus | ICE: $_iceConnectionState',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  'Camera: ${_isCameraOn ? "ACTIVE" : "INACTIVE"}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _isCameraOn
                        ? Colors.green.shade700
                        : Colors.red.shade700,
                  ),
                ),
              ],
            ),
          ),

          // Camera controls
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Camera On/Off Toggle
                ElevatedButton.icon(
                  onPressed: () {
                    if (_isCameraOn) {
                      _turnCameraOff();
                    } else {
                      _turnCameraOn();
                    }
                  },
                  icon: Icon(_isCameraOn ? Icons.videocam_off : Icons.videocam),
                  label: Text(_isCameraOn ? 'Turn Off' : 'Turn On'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isCameraOn ? Colors.red : Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),

                // Ring Bell Button
                ElevatedButton.icon(
                  onPressed: _isCameraOn ? _ringBell : null,
                  icon: const Icon(Icons.notifications_active),
                  label: const Text('Ring Bell'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isCameraOn ? Colors.orange : Colors.grey,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),

                // Call Status
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _isCallActive ? Colors.blue : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isCallActive ? Icons.call : Icons.call_end,
                        color: _isCallActive
                            ? Colors.white
                            : Colors.grey.shade600,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _isCallActive ? 'In Call' : 'Idle',
                        style: TextStyle(
                          color: _isCallActive
                              ? Colors.white
                              : Colors.grey.shade600,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Video display
          Expanded(
            flex: 3,
            child: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border.all(
                  color: _isCallActive ? Colors.blue : Colors.grey,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Stack(
                  children: [
                    _remoteRenderer.srcObject != null
                        ? SizedBox.expand(
                            child: RTCVideoView(
                              _remoteRenderer,
                              objectFit: RTCVideoViewObjectFit
                                  .RTCVideoViewObjectFitCover,
                            ),
                          )
                        : Container(
                            color: Colors.black,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _isCallActive
                                      ? Icons.videocam
                                      : Icons.videocam_off,
                                  size: 80,
                                  color: _isCallActive
                                      ? Colors.white
                                      : Colors.grey,
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  _isCallActive
                                      ? 'Waiting for video...'
                                      : 'No video connection',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                  ),
                                ),
                                if (!_isCameraOn) ...[
                                  const SizedBox(height: 10),
                                  const Text(
                                    'Turn camera ON to enable calls',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                    // Call status overlay
                    if (_isCallActive)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'LIVE',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Call controls (only show when in call)
          if (_isCallActive)
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: _toggleMute,
                    icon: Icon(_isMuted ? Icons.mic_off : Icons.mic),
                    label: Text(_isMuted ? 'Unmute' : 'Mute'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isMuted ? Colors.red : Colors.grey,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _endCall,
                    icon: const Icon(Icons.call_end),
                    label: const Text('End Call'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),

          // Debug logs
          Container(
            height: 150,
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Debug Logs:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: ListView.builder(
                    itemCount: _debugLogs.length,
                    itemBuilder: (context, index) {
                      final log = _debugLogs[_debugLogs.length - 1 - index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: Text(
                          log,
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
        ],
      ),
    );
  }
}
