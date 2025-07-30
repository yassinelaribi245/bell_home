import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

void main() {
  runApp(const CameraTestingApp());
}

class CameraTestingApp extends StatelessWidget {
  const CameraTestingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Bell Camera Testing',
      theme: ThemeData(
        primarySwatch: Colors.orange,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const CameraTestingScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class CameraTestingScreen extends StatefulWidget {
  const CameraTestingScreen({super.key});

  @override
  State<CameraTestingScreen> createState() => _CameraTestingScreenState();
}

class _CameraTestingScreenState extends State<CameraTestingScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  io.Socket? socket;
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;

  String _connectionStatus = 'Disconnected';
  String _iceConnectionState = 'New';
  bool _isConnected = false;
  bool _isCameraReady = false;
  bool _isCallActive = false;
  bool _mobileClientAvailable = false;
  List<String> _debugLogs = [];

  // Configuration
  final String signalingServerUrl = 'https://b14086ebe0fc.ngrok-free.app';
  final String cameraCode = 'cam123';

  @override
  void initState() {
    super.initState();
    _initRenderers();
    _addDebugLog('🔔 Camera Testing App Started');
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
      _showError('Failed to initialize video renderers: $e');
    }
  }

  void _connectToServer() async {
    try {
      _addDebugLog('🔗 Connecting to signaling server...');
      _updateStatus('Connecting to server...');

      socket = io.io(signalingServerUrl, <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': false,
        'timeout': 20000,
      });

      _setupSocketEventHandlers();
      socket!.connect();
    } catch (e) {
      _addDebugLog('❌ Connection error: $e');
      _showError('Connection error: $e');
    }
  }

  void _setupSocketEventHandlers() {
    // Connection events
    socket!.onConnect((_) async {
      _addDebugLog('✅ Connected to signaling server');
      _updateStatus('Connected to signaling server');
      setState(() => _isConnected = true);

      // Join room as camera device
      socket!.emit('join_room', {'room': cameraCode, 'client_type': 'camera'});
      _addDebugLog('📹 Joining room: $cameraCode as camera device');
    });

    socket!.onConnectError((err) {
      _addDebugLog('❌ Socket connect error: $err');
      _updateStatus('Connect Error: $err');
    });

    socket!.onConnectTimeout((_) {
      _addDebugLog('⏰ Socket connection timeout');
      _updateStatus('Connection Timeout');
    });

    socket!.onError((err) {
      _addDebugLog('❌ Socket error: $err');
      _updateStatus('Socket Error: $err');
    });

    socket!.onDisconnect((reason) {
      _addDebugLog('🔌 Socket disconnected: $reason');
      _updateStatus('Disconnected: $reason');
      setState(() {
        _isConnected = false;
        _mobileClientAvailable = false;
      });
    });

    // Room events
    socket!.on('joined_room', (data) {
      _addDebugLog('🏠 Successfully joined room: ${data['room']}');
      _addDebugLog('📱 Mobile available: ${data['mobile_available']}');
      setState(() {
        _mobileClientAvailable = data['mobile_available'] ?? false;
      });

      // Announce camera readiness
      socket!.emit('camera_ready', {'room': cameraCode, 'status': 'ready'});
      _addDebugLog('📹 Announced camera readiness');

      if (_mobileClientAvailable) {
        _updateStatus('Mobile app connected - ready to ring bell');
      } else {
        _updateStatus('Waiting for mobile app...');
      }
    });

    socket!.on('mobile_available', (data) {
      _addDebugLog('📱 Mobile app is now available');
      setState(() => _mobileClientAvailable = true);
      _updateStatus('Mobile app connected - ready to ring bell');
    });

    socket!.on('mobile_disconnected', (data) {
      _addDebugLog('📱 Mobile app disconnected');
      setState(() => _mobileClientAvailable = false);
      _updateStatus('Mobile app disconnected');
    });

    // Call response handling
    socket!.on('camera_response', (data) async {
      _addDebugLog('📱 Mobile response: ${data['response']}');

      if (data['response'] == 'accepted') {
        _addDebugLog('🎉 Call accepted! Starting video stream...');
        _updateStatus('Call accepted - starting video stream');
        setState(() => _isCallActive = true);

        try {
          await _setupPeerConnection();
          await _startVideoCall();
        } catch (e) {
          _addDebugLog('❌ Error starting video call: $e');
          _showError('Failed to start video call: $e');
        }
      } else {
        _addDebugLog('❌ Call rejected by mobile app');
        _updateStatus('Call rejected');
        _endCall();
      }
    });

    // WebRTC signaling events
    socket!.on('answer', (data) async {
      _addDebugLog('📞 Received answer from mobile app');
      try {
        await _handleAnswer(data);
      } catch (e) {
        _addDebugLog('❌ Error handling answer: $e');
        _showError('Error handling answer: $e');
      }
    });

    socket!.on('ice_candidate', (data) async {
      _addDebugLog('🧊 Received ICE candidate from mobile');
      try {
        await _handleIceCandidate(data);
      } catch (e) {
        _addDebugLog('❌ Error handling ICE candidate: $e');
      }
    });

    socket!.on('call_ended', (data) {
      _addDebugLog('📞 Call ended by ${data['ended_by']}');
      _endCall();
    });

    socket!.on('error', (data) {
      _addDebugLog('❌ Server error: ${data['message']}');
      _showError('Server error: ${data['message']}');
    });
  }

  Future<void> _startCamera() async {
    try {
      _addDebugLog('📹 Starting camera and microphone...');
      _updateStatus('Starting camera...');

      _localStream = await navigator.mediaDevices.getUserMedia({
        'video': {
          'width': {'ideal': 640},
          'height': {'ideal': 480},
          'frameRate': {'ideal': 30},
        },
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
      });

      _localRenderer.srcObject = _localStream;
      setState(() => _isCameraReady = true);

      _addDebugLog('✅ Camera and microphone started successfully');
      _updateStatus('Camera ready - you can now ring the bell');
    } catch (e) {
      _addDebugLog('❌ Camera/microphone error: $e');
      _showError('Camera/microphone access failed: $e');
    }
  }

  Future<void> _ringBell() async {
    try {
      _addDebugLog('🔔 Ringing bell - sending notification...');
      _updateStatus('Sending notification to mobile app...');

      // Send notification request to server
      final response = await _sendNotificationRequest();

      if (response) {
        _addDebugLog('✅ Notification sent successfully');
        _updateStatus('Notification sent - waiting for mobile response...');
        // Do NOT set up peer connection here. Wait for camera_response.
        // await _setupPeerConnection();
      } else {
        _addDebugLog('❌ Failed to send notification');
        _updateStatus('Failed to send notification');
      }
    } catch (e) {
      _addDebugLog('❌ Ring bell error: $e');
      _showError('Ring bell failed: $e');
    }
  }

  Future<bool> _sendNotificationRequest() async {
    try {
      // In a real implementation, you would make an HTTP request to your server's /notify endpoint
      // For now, we'll simulate this by emitting a socket event
      // You can replace this with actual HTTP request if needed

      socket!.emit('ring_bell', {
        'camera_code': cameraCode,
        'timestamp': DateTime.now().toIso8601String(),
      });

      // Simulate HTTP request to /notify endpoint
      //final response = await http.post(
      //Uri.parse('$signalingServerUrl/notify'),
      //headers: {'Content-Type': 'application/json'},
      //body: json.encode({'camera_code': cameraCode}),
      //);
      //return response.statusCode == 200;
      return true;
    } catch (e) {
      _addDebugLog('❌ Error sending notification: $e');
      return false;
    }
  }

  Future<void> _setupPeerConnection() async {
    try {
      _addDebugLog('🔗 Setting up peer connection...');

      final config = {
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'},
          {'urls': 'stun:stun2.l.google.com:19302'},
          {'urls': 'stun:stun3.l.google.com:19302'},
          {'urls': 'stun:stun4.l.google.com:19302'},
        ],
      };

      _peerConnection = await createPeerConnection(config);
      _addDebugLog('✅ Peer connection created');

      // Add local stream tracks (video and audio from camera)
      if (_localStream != null) {
        _localStream!.getTracks().forEach((track) {
          _peerConnection!.addTrack(track, _localStream!);
          _addDebugLog('➕ Added ${track.kind} track to peer connection');
        });
      }

      _setupPeerConnectionHandlers();
    } catch (e) {
      _addDebugLog('❌ Peer connection setup error: $e');
      rethrow;
    }
  }

  void _setupPeerConnectionHandlers() {
    // Handle incoming remote stream (audio from mobile app)
    _peerConnection!.onTrack = (event) {
      _addDebugLog('📡 Received remote stream from mobile app');
      if (event.streams.isNotEmpty) {
        final remoteStream = event.streams[0];
        _addDebugLog(
          '🎤 Remote stream has ${remoteStream.getTracks().length} tracks',
        );

        // Debug track information
        remoteStream.getTracks().forEach((track) {
          _addDebugLog(
            '🎬 Remote ${track.kind} track - enabled: ${track.enabled}',
          );
        });

        setState(() {
          _remoteRenderer.srcObject = remoteStream;
        });
      }
    };

    // ICE candidate handling
    _peerConnection!.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        _addDebugLog('🧊 Sending ICE candidate to mobile');
        socket!.emit('ice_candidate', {
          'room': cameraCode,
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      }
    };

    // Connection state monitoring
    _peerConnection!.onIceConnectionState = (state) {
      _addDebugLog('🔗 ICE connection state: $state');
      setState(() => _iceConnectionState = state.toString());

      switch (state) {
        case RTCIceConnectionState.RTCIceConnectionStateConnected:
          _updateStatus('Video call connected!');
          break;
        case RTCIceConnectionState.RTCIceConnectionStateCompleted:
          _updateStatus('Connection established');
          break;
        case RTCIceConnectionState.RTCIceConnectionStateFailed:
          _addDebugLog('❌ ICE connection failed');
          _updateStatus('Connection failed');
          _showError('Connection failed - please try again');
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
  }

  Future<void> _startVideoCall() async {
    try {
      _addDebugLog('📹 Creating offer for mobile app...');

      final offer = await _peerConnection!.createOffer({
        'offerToReceiveAudio': true, // We want to receive audio from mobile
        'offerToReceiveVideo': false, // We don't expect video from mobile
      });

      await _peerConnection!.setLocalDescription(offer);
      _addDebugLog('✅ Local description set');

      socket!.emit('offer', {'room': cameraCode, 'sdp': offer.toMap()});
      _addDebugLog('📤 Offer sent to mobile app');
    } catch (e) {
      _addDebugLog('❌ Video call error: $e');
      _showError('Failed to start video call: $e');
    }
  }

  Future<void> _handleAnswer(dynamic data) async {
    try {
      _addDebugLog('📞 Processing answer from mobile app...');

      final answer = RTCSessionDescription(
        data['sdp']['sdp'],
        data['sdp']['type'],
      );
      await _peerConnection!.setRemoteDescription(answer);
      _addDebugLog('✅ Remote description set - call established');
    } catch (e) {
      _addDebugLog('❌ Error in handleAnswer: $e');
      rethrow;
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

  void _endCall() {
    _addDebugLog('📞 Ending call...');

    if (_isCallActive && socket != null) {
      socket!.emit('end_call', {'room': cameraCode});
    }

    setState(() {
      _isCallActive = false;
      _remoteRenderer.srcObject = null;
    });

    if (_peerConnection != null) {
      _peerConnection!.close();
      _peerConnection = null;
    }

    _updateStatus(_isConnected ? 'Ready to ring bell again' : 'Disconnected');
  }

  void _updateStatus(String status) {
    if (mounted) {
      setState(() => _connectionStatus = status);
    }
  }

  void _showError(String message) {
    _addDebugLog('❌ Error: $message');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 5),
          backgroundColor: Colors.red,
        ),
      );
    }
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
        title: const Text('Smart Bell Camera Testing'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        actions: [
          Icon(
            _isConnected ? Icons.wifi : Icons.wifi_off,
            color: _isConnected ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 8),
          Icon(
            _mobileClientAvailable
                ? Icons.phone_android
                : Icons.phone_android_outlined,
            color: _mobileClientAvailable ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          // Status bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: _getStatusColor(),
            child: Column(
              children: [
                Text(
                  _connectionStatus,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Camera: $cameraCode | ICE: $_iceConnectionState',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),

          // Control buttons
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isConnected ? null : _connectToServer,
                        icon: const Icon(Icons.wifi),
                        label: Text(
                          _isConnected ? 'Connected' : 'Connect to Server',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isConnected
                              ? Colors.green
                              : Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: (!_isConnected || _isCameraReady)
                            ? null
                            : _startCamera,
                        icon: const Icon(Icons.videocam),
                        label: Text(
                          _isCameraReady ? 'Camera Ready' : 'Start Camera',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isCameraReady
                              ? Colors.green
                              : Colors.orange,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed:
                            (!_isConnected || !_isCameraReady || _isCallActive)
                            ? null
                            : _ringBell,
                        icon: const Icon(Icons.doorbell),
                        label: const Text('🔔 Ring Bell'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: !_isCallActive ? null : _endCall,
                        icon: const Icon(Icons.call_end),
                        label: const Text('End Call'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Video displays
          Expanded(
            flex: 3,
            child: Row(
              children: [
                // Local video (camera sending)
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _isCameraReady ? Colors.green : Colors.grey,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Stack(
                        children: [
                          _localRenderer.srcObject != null
                              ? RTCVideoView(_localRenderer, mirror: true)
                              : Container(
                                  color: Colors.black,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        _isCameraReady
                                            ? Icons.videocam
                                            : Icons.videocam_off,
                                        size: 50,
                                        color: _isCameraReady
                                            ? Colors.white
                                            : Colors.grey,
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        _isCameraReady
                                            ? 'Camera Ready'
                                            : 'Camera Not Started',
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
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
                                '📹 Local Camera (Sending)',
                                style: TextStyle(
                                  color: Colors.white,
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

                // Remote audio indicator (receiving from mobile)
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _isCallActive ? Colors.green : Colors.grey,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Container(
                      color: Colors.black87,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _isCallActive ? Icons.mic : Icons.mic_off,
                            size: 50,
                            color: _isCallActive ? Colors.green : Colors.grey,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _isCallActive
                                ? 'Receiving Audio from Mobile'
                                : 'No Audio Connection',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          if (_remoteRenderer.srcObject != null)
                            Container(
                              margin: const EdgeInsets.only(top: 8),
                              child: RTCVideoView(_remoteRenderer),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Debug logs
          Expanded(
            flex: 2,
            child: Container(
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Debug Log:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
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
                  const SizedBox(height: 4),
                  Expanded(
                    child: ListView.builder(
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
          ),
        ],
      ),
    );
  }

  Color _getStatusColor() {
    if (_isCallActive) return Colors.green.shade100;
    if (_isConnected && _mobileClientAvailable && _isCameraReady)
      return Colors.blue.shade100;
    if (_isConnected) return Colors.yellow.shade100;
    return Colors.red.shade100;
  }
}
