import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'package:http_parser/http_parser.dart';

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
  final List<Map<String, dynamic>> _queuedIceCandidates = [];
  io.Socket? socket;
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  bool isCaller = true;
  List<String> _availableCameraCodes = [];
  bool _showCameraSelector = false;

  String _connectionStatus = 'Disconnected';
  bool _isPeerConnectionReady = false;
  String _iceConnectionState = 'New';
  bool _isConnected = false;
  bool _isCameraReady = false;
  bool _isCallActive = false;
  bool _mobileClientAvailable = false;
  final List<String> _debugLogs = [];
  bool _isCapturing = false;
  int _lastBurstCount = 0;
  // Configuration
  final String signalingServerUrl = 'https://538ea5f38580.ngrok-free.app';
  String cameraCode = 'cam123';
  final String twilioTurnCredentialServerUrl =
      'https://538ea5f38580.ngrok-free.app/twilio_turn_credentials';
  final String uploadFramesUrl =
      'https://e39ad83dbdb5.ngrok-free.app/bellapp/public/api/upload-frames'; // e.g. https://<ngrok>/api/upload-frames

  @override
  void initState() {
    super.initState();
    _initRenderers();
    _addDebugLog('🔔 Camera Testing App Started');

    // Show camera selector BEFORE connecting to server
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showCameraCodeSelector();
    });

    // Don't connect to server automatically - wait for camera code selection
    // _connectToServer(); // Remove this line
  }

  @override
  void dispose() {
    _endCall();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    socket?.disconnect();
    socket?.dispose();
    super.dispose();
  }

  void _addDebugLog(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    if (mounted) {
      setState(() {
        _debugLogs.add('[$timestamp] $message');
        if (_debugLogs.length > 50) {
          _debugLogs.removeAt(0);
        }
      });
    }
    debugPrint(message);
  }

  // Fetch camera codes from API
  Future<void> _fetchCameraCodes() async {
    try {
      _addDebugLog('🔍 Fetching camera codes from API...');

      final response = await http
          .get(
            Uri.parse('https://e39ad83dbdb5.ngrok-free.app/bellapp/public/api/getcameracode'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));

      _addDebugLog('📡 API Response Status: ${response.statusCode}');
      _addDebugLog('📡 API Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _addDebugLog('📊 Parsed data: $data');

        if (data['cameracode'] != null && data['cameracode'].isNotEmpty) {
          final List<dynamic> codes = data['cameracode'][0];
          setState(() {
            _availableCameraCodes = codes.cast<String>();
          });
          _addDebugLog(
            '✅ Successfully loaded ${_availableCameraCodes.length} camera codes',
          );
        } else {
          _addDebugLog('⚠️ No camera codes found in response');
        }
      } else {
        _addDebugLog('❌ API call failed with status: ${response.statusCode}');
      }
    } catch (e) {
      _addDebugLog('❌ Error fetching camera codes: $e');
      // Show error in dialog
      setState(() {
        _availableCameraCodes = ['Error loading codes'];
      });
    }
  }

  // Show camera code selector popup
  void _showCameraCodeSelector() async {
    await _fetchCameraCodes();
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _buildCameraCodeDialog(),
    );
  }

  // Build camera code selection dialog
  Widget _buildCameraCodeDialog() {
    String? selectedCode;

    return StatefulBuilder(
      builder: (context, setDialogState) {
        return Dialog(
          child: Container(
            padding: const EdgeInsets.all(20),
            constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.camera_alt, color: Colors.orange),
                    const SizedBox(width: 8),
                    const Text(
                      'Select Camera Code',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Loading or content
                Expanded(
                  child: _availableCameraCodes.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 16),
                              Text('Loading camera codes...'),
                            ],
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: _availableCameraCodes.length,
                          itemBuilder: (context, index) {
                            final code = _availableCameraCodes[index];
                            return Card(
                              child: ListTile(
                                title: Text(code),
                                leading: Radio<String>(
                                  value: code,
                                  groupValue: selectedCode,
                                  onChanged: (value) {
                                    setDialogState(() {
                                      selectedCode = value;
                                    });
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                ),

                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton(
                      onPressed: () async {
                        setDialogState(() {
                          _availableCameraCodes.clear();
                        });
                        await _fetchCameraCodes();
                        setDialogState(() {});
                      },
                      child: const Text('Refresh'),
                    ),
                    ElevatedButton(
                      onPressed:
                          selectedCode != null &&
                              selectedCode != 'Error loading codes'
                          ? () {
                              _updateCameraCode(selectedCode!);
                              Navigator.of(context).pop();
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Connect'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Update camera code without restarting app
  void _updateCameraCode(String newCameraCode) {
    setState(() {
      cameraCode = newCameraCode;
    });
    _addDebugLog('📹 Camera code updated to: $newCameraCode');

    // Now connect to server with the selected camera code
    _connectToServer();
  }

  Future<Map<String, dynamic>> _fetchTwilioTurnCredentials() async {
    try {
      _addDebugLog("Fetching Twilio TURN credentials from backend...");
      final response = await http.get(Uri.parse(twilioTurnCredentialServerUrl));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _addDebugLog("Successfully fetched Twilio TURN credentials.");
        return data;
      } else {
        _addDebugLog(
          "Failed to fetch Twilio TURN credentials: ${response.statusCode} ${response.body}",
        );
        throw Exception("Failed to fetch Twilio TURN credentials");
      }
    } catch (e) {
      _addDebugLog("Error fetching Twilio TURN credentials: $e");
      _showError("Error fetching Twilio TURN credentials: $e");
      rethrow;
    }
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

  void _connectToServer() {
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

      // Report camera connected status to database
      _reportCameraConnected();
    });

    socket!.onConnectError((err) {
      _addDebugLog('❌ Socket connect error: $err');
      _updateStatus('Connect Error: $err');
      _showError('Socket connection error: $err');
    });

    socket!.onConnectTimeout((_) {
      _addDebugLog('⏰ Socket connection timeout');
      _updateStatus('Connection Timeout');
      _showError('Socket connection timeout');
    });

    socket!.onError((err) {
      _addDebugLog('❌ Socket error: $err');
      _updateStatus('Socket Error: $err');
      _showError('Socket error: $err');
    });

    socket!.onDisconnect((reason) {
      _addDebugLog('🔌 Socket disconnected: $reason');
      _updateStatus('Disconnected: $reason');
      setState(() {
        _isConnected = false;
        _mobileClientAvailable = false;
      });

      // Report camera disconnected status to database
      _reportCameraDisconnected();
      _endCall(); // End call if socket disconnects
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
      _endCall(); // End call if mobile client disconnects
    });

    // Call response handling
    socket!.on('camera_response', (data) async {
      _addDebugLog('📱 Mobile response: ${data['response']}');

      if (data["response"] == "accepted") {
        _addDebugLog("🎉 Call accepted! Starting video stream...");
        await _setupPeerConnection();
        await _startVideoCall();
        setState(() => _isCallActive = true);
      } else if (data["response"] == "rejected") {
        _addDebugLog("❌ Call rejected by mobile app.");
        _endCall();
      }
    });

    // WebRTC Signaling events
    socket!.on('offer', (data) async {
      _addDebugLog('📞 Received offer from mobile app');
      await _handleOffer(data);
    });

    socket!.on('answer', (data) async {
      _addDebugLog('📞 Received answer from mobile app');
      await _handleAnswer(data);
    });

    socket!.on('ice_candidate', (data) async {
      _addDebugLog('🧊 Received ICE candidate from mobile app');
      await _handleIceCandidate(data);
    });

    socket!.on('call_ended', (data) {
      _addDebugLog('📞 Call ended by remote peer');
      _endCall();
    });

    socket!.on('camera_turned_on', (data) {
      _addDebugLog('🎛️ [SOCKET EVENT] Turn on camera command received: $data');
      final receivedCameraCode = data['camera_code'] ?? '';

      if (receivedCameraCode == cameraCode) {
        _turnCameraOn();

        // Send response back to main app
        socket!.emit('camera_turned_on', {
          'camera_code': cameraCode,
          'success': true,
          'message': 'Camera turned on successfully',
          'timestamp': DateTime.now().toIso8601String(),
        });

        _addDebugLog('🎛️ Camera turned on and response sent');
      }
    });
    socket!.on('camera_turned_off', (data) {
      _addDebugLog(
        '🎛️ [SOCKET EVENT] Turn off camera command received: $data',
      );
      final receivedCameraCode = data['camera_code'] ?? '';

      if (receivedCameraCode == cameraCode) {
        _turnCameraOff();

        // Send response back to main app
        socket!.emit('camera_turned_off', {
          'camera_code': cameraCode,
          'success': true,
          'message': 'Camera turned off successfully',
          'timestamp': DateTime.now().toIso8601String(),
        });

        _addDebugLog('🎛️ Camera turned off and response sent');
      }
    });
    // Listen for start_call1 event from server (bellui-initiated call)
    socket!.on('start_call1', (data) async {
      _addDebugLog(
        '📞 Received start_call1 from server, starting call immediately...',
      );
      await _setupPeerConnection();
      await _startVideoCall();
      setState(() => _isCallActive = true);
    });
  }

  void _turnCameraOn() {
    _addDebugLog('🎛️ Turning camera on...');
    _startCamera();
    _addDebugLog('🎛️ Camera turned on.');
  }

  void _turnCameraOff() {
    _addDebugLog('🎛️ Turning camera off...');
    _stopCamera();
    _addDebugLog('🎛️ Camera turned off.');
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

      // Report camera ready status to database
      _reportCameraReady();
    } catch (e) {
      _addDebugLog('❌ Camera/microphone error: $e');
      _showError('Camera/microphone access failed: $e');
    }
  }

  Future<void> _stopCamera() async {
    try {
      _addDebugLog('📹 Stopping camera and microphone...');
      _updateStatus('Stopping camera...');

      if (_localStream != null) {
        _localStream!.getTracks().forEach((track) {
          track.stop();
        });
        _localStream!.dispose();
        _localStream = null;
      }
      _localRenderer.srcObject = null;
      setState(() => _isCameraReady = false);
      _addDebugLog('✅ Camera and microphone stopped successfully');
      _updateStatus('Camera stopped');
      _reportCameraNotReady();
    } catch (e) {
      _addDebugLog('❌ Error stopping camera: $e');
      _showError('Error stopping camera: $e');
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
      socket!.emit('ring_bell', {
        'camera_code': cameraCode,
        'timestamp': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) {
      _addDebugLog('❌ Error sending notification: $e');
      return false;
    }
  }

  Future<void> _setupPeerConnection() async {
    try {
      _addDebugLog("🔗 Setting up peer connection...");
      _queuedIceCandidates.clear();
      _isPeerConnectionReady = false; // Reset before setup

      // Fetch dynamic Twilio TURN credentials
      final turnCredentials = await _fetchTwilioTurnCredentials();

      final config = {
        "iceServers":
            turnCredentials["iceServers"], // Use fetched ICE servers from Twilio
        "iceCandidatePoolSize": 10,
        "bundlePolicy": "max-bundle",
        "rtcpMuxPolicy": "require",
      };

      _peerConnection = await createPeerConnection(config);
      _addDebugLog("✅ Peer connection created");

      // Add local stream tracks (video and audio from camera)
      if (_localStream != null) {
        for (final track in _localStream!.getTracks()) {
          await _peerConnection!.addTrack(track, _localStream!);
          _addDebugLog("➕ Added ${track.kind} track to peer connection");
        }
      }

      _setupPeerConnectionHandlers();
      _isPeerConnectionReady = true; // Mark as ready after handlers are set
      _addDebugLog("✅ Peer connection marked as ready");
      // Process queued candidates only after remote description is set in _handleAnswer
    } catch (e) {
      _addDebugLog("❌ Peer connection setup error: $e");
      _showError("Peer connection setup failed: $e");
      rethrow;
    }
  }

  // Attempts to reconnect and restart the call after ICE failure/disconnect
  bool _manualCallEnd = false;

  void _attemptReconnect() async {
    if (_manualCallEnd) {
      _addDebugLog('🛑 Manual call end detected, not reconnecting.');
      return;
    }
    _addDebugLog('🔄 Attempting to reconnect call...');
    _endCall();
    await Future.delayed(const Duration(seconds: 2));
    if (_isCameraReady && _mobileClientAvailable) {
      _addDebugLog('🔄 Re-establishing peer connection and restarting call...');
      await _setupPeerConnection();
      await _startVideoCall();
      setState(() => _isCallActive = true);
    } else {
      _addDebugLog(
        '⚠️ Cannot reconnect: camera not ready or mobile not available',
      );
    }
  }

  void _setupPeerConnectionHandlers() {
    // Handle incoming remote stream (audio from mobile app)
    _peerConnection!.onTrack = (event) {
      _addDebugLog('📡 [onTrack] Received remote stream from mobile app');
      if (event.streams.isNotEmpty) {
        final remoteStream = event.streams[0];
        _addDebugLog(
          '🎤 [onTrack] Remote stream has ${remoteStream.getTracks().length} tracks',
        );
        remoteStream.getTracks().forEach((track) {
          _addDebugLog(
            '🎬 [onTrack] Remote ${track.kind} track - enabled: ${track.enabled}',
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
        _addDebugLog(
          '🧊 [onIceCandidate] Sending ICE candidate to mobile: ${candidate.candidate}',
        );
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
      _addDebugLog(
        '🔗 [onIceConnectionState] ICE connection state changed: $state',
      );
      setState(() => _iceConnectionState = state.toString());
      switch (state) {
        case RTCIceConnectionState.RTCIceConnectionStateConnected:
          _updateStatus('Video call connected!');
          break;
        case RTCIceConnectionState.RTCIceConnectionStateCompleted:
          _updateStatus('Connection established');
          break;
        case RTCIceConnectionState.RTCIceConnectionStateFailed:
          _addDebugLog('❌ [onIceConnectionState] ICE connection failed');
          _updateStatus('Connection failed');
          _showError('Connection failed - attempting to reconnect...');
          _attemptReconnect();
          break;
        case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
          _addDebugLog('⚠️ [onIceConnectionState] ICE connection disconnected');
          _updateStatus('Connection lost - attempting to reconnect...');
          _attemptReconnect();
          break;
        case RTCIceConnectionState.RTCIceConnectionStateClosed:
          _addDebugLog('🔒 [onIceConnectionState] ICE connection closed');
          _updateStatus('Call ended');
          _endCall();
          break;
        default:
          _addDebugLog('🔗 [onIceConnectionState] ICE: $state');
          _updateStatus('ICE: $state');
      }
    };

    _peerConnection!.onConnectionState = (state) {
      _addDebugLog('🔗 [onConnectionState] Peer connection state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _addDebugLog('❌ [onConnectionState] Peer connection failed');
        _showError('Peer connection failed - ending call');
        _endCall();
      }
    };

    _peerConnection!.onSignalingState = (state) {
      _addDebugLog('📡 [onSignalingState] Signaling state: $state');
    };
  }

  Future<void> _startVideoCall() async {
    try {
      _addDebugLog('📹 Creating offer for mobile app...');

      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);
      _addDebugLog('✅ Local description (offer) set');

      socket!.emit('offer', {'room': cameraCode, 'sdp': offer.toMap()});
      _addDebugLog('📤 Offer sent to mobile app');
    } catch (e) {
      _addDebugLog('❌ Error starting video call: $e');
      _showError('Error starting video call: $e');
    }
  }

  Future<void> _handleOffer(dynamic data) async {
    try {
      _addDebugLog('📞 Processing offer from mobile app...');

      if (_peerConnection == null) {
        await _setupPeerConnection();
      }

      final offer = RTCSessionDescription(
        data['sdp']['sdp'],
        data['sdp']['type'],
      );

      await _peerConnection!.setRemoteDescription(offer);
      _addDebugLog('✅ Remote description (offer) set');

      // Process queued ICE candidates after setting remote description
      await _processQueuedIceCandidates();

      // Create and send answer
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);
      _addDebugLog('✅ Local description (answer) set');

      socket!.emit('answer', {'room': cameraCode, 'sdp': answer.toMap()});
      _addDebugLog('📤 Answer sent to mobile app');
    } catch (e) {
      _addDebugLog('❌ Error handling offer: $e');
      _showError('Error handling offer: $e');
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
      _addDebugLog('✅ Remote description (answer) set');

      // Process queued ICE candidates after setting remote description
      await _processQueuedIceCandidates();
    } catch (e) {
      _addDebugLog('❌ Error handling answer: $e');
      _showError('Error handling answer: $e');
    }
  }

  Future<void> _handleIceCandidate(dynamic data) async {
    try {
      if (data == null || data["candidate"] == null) {
        _addDebugLog("❌ [handleIceCandidate] Invalid ICE candidate data");
        return;
      }

      // Always queue candidates if peer connection isn't ready or remote description isn't set
      bool shouldQueue = false;
      if (_peerConnection == null || !_isPeerConnectionReady) {
        shouldQueue = true;
      } else {
        var remoteDesc = await _peerConnection!.getRemoteDescription();
        if (remoteDesc == null) {
          shouldQueue = true;
        }
      }
      if (shouldQueue) {
        _addDebugLog(
          "⏳ [handleIceCandidate] Queueing ICE candidate (PC ready: $_isPeerConnectionReady, RD set: ${_peerConnection != null ? (await _peerConnection!.getRemoteDescription()) != null : false}): ${data['candidate']}",
        );
        _queuedIceCandidates.add(data);
        return;
      }

      final candidate = RTCIceCandidate(
        data["candidate"],
        data["sdpMid"],
        data["sdpMLineIndex"],
      );

      await _peerConnection!.addCandidate(candidate);
      _addDebugLog(
        "✅ [handleIceCandidate] Added ICE candidate: ${candidate.candidate}",
      );
    } catch (e) {
      _addDebugLog("❌ [handleIceCandidate] Error adding ICE candidate: $e");
      _showError("Error adding ICE candidate: $e");
    }
  }

  Future<void> _processQueuedIceCandidates() async {
    if (_peerConnection == null || !_isPeerConnectionReady) {
      _addDebugLog(
        "⚠️ [processQueuedIceCandidates] Cannot process queued candidates - peer connection not ready",
      );
      return;
    }

    var remoteDesc = await _peerConnection!.getRemoteDescription();
    if (remoteDesc == null) {
      _addDebugLog(
        "⚠️ [processQueuedIceCandidates] Cannot process queued candidates - no remote description",
      );
      return;
    }

    if (_queuedIceCandidates.isEmpty) {
      _addDebugLog(
        "ℹ️ [processQueuedIceCandidates] No queued ICE candidates to process",
      );
      return;
    }

    _addDebugLog(
      "🔁 [processQueuedIceCandidates] Processing ${_queuedIceCandidates.length} queued ICE candidates...",
    );

    final candidatesToProcess = List<Map<String, dynamic>>.from(
      _queuedIceCandidates,
    );
    _queuedIceCandidates.clear();

    int successCount = 0;
    int failureCount = 0;

    for (var candidateData in candidatesToProcess) {
      try {
        final candidate = RTCIceCandidate(
          candidateData["candidate"],
          candidateData["sdpMid"],
          candidateData["sdpMLineIndex"],
        );
        await _peerConnection!.addCandidate(candidate);
        successCount++;
        _addDebugLog(
          "✅ [processQueuedIceCandidates] Processed queued ICE candidate",
        );
      } catch (e) {
        failureCount++;
        _addDebugLog(
          "❌ [processQueuedIceCandidates] Error processing queued ICE candidate: $e",
        );
        // Don't re-queue failed candidates to avoid infinite loops
      }
    }

    _addDebugLog(
      "✅ [processQueuedIceCandidates] Finished processing queued ICE candidates: $successCount success, $failureCount failed",
    );
  }

  void _endCall() {
    _addDebugLog("📞 Ending call...");
    _updateStatus("Call ended");
    _manualCallEnd = true;
    if (socket?.connected == true) {
      socket!.emit('end_call', {'room': cameraCode});
      _addDebugLog('📤 Sent end_call to server');
    }
    _peerConnection?.close();
    _peerConnection = null;
    _remoteRenderer.srcObject = null;
    setState(() {
      _isCallActive = false;
      _isPeerConnectionReady = false;
      _iceConnectionState = 'New';
      _queuedIceCandidates.clear();
    });
    _addDebugLog("✅ Call ended successfully");
    // Only reset _manualCallEnd if a new call is started
  }

  void _updateStatus(String status) {
    if (mounted) {
      setState(() {
        _connectionStatus = status;
      });
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  // Database reporting functions
  void _reportCameraConnected() {
    _addDebugLog('Reporting camera connected to DB...');
    socket!.emit('camera_status_update', {
      'camera_code': cameraCode,
      'is_online': true,
      'status': 'online',
      'is_camera_on': _isCameraReady, // Initial state
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  void _reportCameraDisconnected() {
    _addDebugLog('Reporting camera disconnected to DB...');
    socket!.emit('camera_status_update', {
      'camera_code': cameraCode,
      'is_online': false,
      'status': 'offline',
      'is_camera_on': false,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  void _reportCameraReady() {
    _addDebugLog('Reporting camera ready to DB...');
    socket!.emit('camera_status_update', {
      'camera_code': cameraCode,
      'is_online': true,
      'status': 'online',
      'is_camera_on': true,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  void _reportCameraNotReady() {
    _addDebugLog('Reporting camera not ready to DB...');
    socket!.emit('camera_status_update', {
      'camera_code': cameraCode,
      'is_online': true,
      'status': 'online',
      'is_camera_on': false,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
Future<void> _onDoorbellPressed() async {
  _addDebugLog('🔔 Doorbell pressed → capturing burst…');
  try {
    await _captureBurstAndUpload(frameCount: 5, intervalMs: 33);
  } catch (e) {
    _addDebugLog('❌ Capture/upload error: $e');
    _showError('Capture/upload error: $e');
  }
}
// Make sure you have a variable for the camera code available in this scope
// final String cameraCode = 'your_camera_code_here';

Future<void> _captureBurstAndUpload({int frameCount = 5, int intervalMs = 33}) async {
  if (_isCapturing) return;
  if (_localStream == null) {
    _showError('Camera not started yet.');
    _addDebugLog('⚠️ Cannot capture: _localStream is null');
    return;
  }

  final tracks = _localStream!.getVideoTracks();
  if (tracks.isEmpty) {
    _showError('No local video track available.');
    _addDebugLog('⚠️ Cannot capture: no video tracks');
    return;
  }

  final videoTrack = tracks.first;

  _isCapturing = true;
  setState(() {}); // refresh FAB disabled state
  _lastBurstCount = 0;

  try {
    // --- FIX #1: Point to the correct Laravel API endpoint ---
    final request = http.MultipartRequest('POST', Uri.parse('https://e39ad83dbdb5.ngrok-free.app/bellapp/public/api/upload-frames' ));
    
    // This part is correct
    request.fields['camera_code'] = cameraCode;

    for (int i = 0; i < frameCount; i++) {
      final buffer = await videoTrack.captureFrame();
      final bytes = buffer.asUint8List();

      request.files.add(
        http.MultipartFile.fromBytes(
          // --- FIX #2: Use 'frames[]' to send files as an array ---
          'frames[]',
          bytes,
          filename: 'frame_$i.png',
          // contentType is optional but good practice
          // contentType: MediaType('image', 'png' ),
        ),
      );

      _lastBurstCount++;
      await Future.delayed(Duration(milliseconds: intervalMs));
    }

    // This variable seems to be from an older version, let's use the correct URL from the request object
    _addDebugLog('📤 Uploading $_lastBurstCount frames to ${request.url}');
    
    final streamed = await request.send();
    // It's generally safer to use http.Response.fromStream to handle the response body
    final response = await http.Response.fromStream(streamed );

    if (response.statusCode == 200) {
      _addDebugLog('✅ Upload ok: ${response.body}');
    } else {
      _addDebugLog('❌ Upload failed [${response.statusCode}]: ${response.body}');
      _showError('Upload failed [${response.statusCode}]');
    }
  } catch (e) {
    // Also good to have a catch-all for network errors etc.
    _addDebugLog('🔥 An exception occurred during upload: $e');
    _showError('An error occurred: $e');
  } finally {
    _isCapturing = false;
    if (mounted) setState(() {});
  }
}


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
  onPressed: _isCapturing ? null : _onDoorbellPressed,
  label: Text(_isCapturing ? 'Capturing...' : 'Ring Bell'),
  icon: const Icon(Icons.notifications_active),
  backgroundColor: Colors.orange,
),
      appBar: AppBar(
        title: const Text('Camera Testing App'),
        backgroundColor: Colors.orange,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              'Status: $_connectionStatus',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              'ICE Connection: $_iceConnectionState',
              style: const TextStyle(fontSize: 14),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                // Remote video (full screen)
                Positioned.fill(
                  child: RTCVideoView(
                    _remoteRenderer,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                ),
                // Local video (small, top-right)
                Positioned(
                  top: 20,
                  right: 20,
                  width: 120,
                  height: 90,
                  child: AspectRatio(
                    aspectRatio: 4 / 3,
                    child: RTCVideoView(
                      _localRenderer,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                
                ElevatedButton(
                  onPressed: _isCameraReady ? _ringBell : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Ring Bell'),
                ),
                ElevatedButton(
                  onPressed: _isCallActive ? () => _endCall() : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('End Call'),
                ),
                ElevatedButton(
                  onPressed: _isCameraReady ? _stopCamera : _startCamera,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isCameraReady
                        ? Colors.orange
                        : Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(_isCameraReady ? 'Stop Camera' : 'Start Camera'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _debugLogs.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 2.0,
                  ),
                  child: Text(
                    _debugLogs[index],
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
