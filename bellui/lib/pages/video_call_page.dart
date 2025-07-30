import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:bellui/services/api_service.dart'; // Import the new API service
import 'package:bellui/models/models.dart'; // Import the new models
import 'package:bellui/utils/utils.dart'; // Import the new utils

class VideoCallPage extends StatefulWidget {
  final String cameraCode;
  final String roomId;
  final Camera camera; // Pass the Camera object
  final io.Socket? existingSocket; // Accept existing socket

  const VideoCallPage({
    super.key,
    required this.cameraCode,
    required this.roomId,
    required this.camera,
    this.existingSocket, // Optional existing socket
  });

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
  final List<String> _debugLogs = [];
  final List<Map<String, dynamic>> _queuedIceCandidates = [];
  bool _isPeerConnectionReady = false;

  // Configuration - Use nodeServerUrl from ApiService
  final String signalingServerUrl = ApiService.nodeServerUrl;

  // --- PeerConnection config and constraints (FIXED) ---
  static final Map<String, dynamic> _peerConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
    ],
  };
  static final Map<String, dynamic> _peerConstraints = {
    'mandatory': {},
    'optional': [],
  };
  static final Map<String, dynamic> _offerAnswerConstraints = {
    'offerToReceiveAudio': true,
    'offerToReceiveVideo': false,
  };

  @override
  void initState() {
    super.initState();
    _initRenderers();
    _ensureSocketAndConnect();
    debugPrint('📱 Video Call Page Started for camera: ${widget.cameraCode}');
  }

  Future<void> _ensureSocketAndConnect() async {
    try {
      // If we have an existing socket and it's connected, use it
      if (widget.existingSocket != null && widget.existingSocket!.connected) {
        _addDebugLog('📡 Using existing connected socket');
        socket = widget.existingSocket;
        _setupSocketEventHandlers();
        
        // Join room immediately
        socket!.emit('join_room', {
          'room': widget.cameraCode,
          'client_type': 'mobile',
        });
        _addDebugLog('📱 Joined room: ${widget.cameraCode}');

        // Setup peer connection and local audio
        await _setupPeerConnection();
        await _startLocalAudio();
      } else {
        // Create new connection
        _connectToServer();
      }
    } catch (e) {
      _addDebugLog('❌ Error in socket setup: $e');
      _updateStatus('Connection Error');
    }
  }

  void _addDebugLog(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    setState(() {
      _debugLogs.add('[$timestamp] $message');
      if (_debugLogs.length > 50) {
        _debugLogs.removeAt(0);
      }
    });
    debugPrint(message); // Use debugPrint
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

      // Use existing socket if provided, otherwise create new one
      if (widget.existingSocket != null && widget.existingSocket!.connected) {
        _addDebugLog('📡 Using existing socket connection');
        socket = widget.existingSocket;
        _setupSocketEventHandlers();
        // DO NOT join room or emit camera_response here!
        // Only set up PeerConnection and local audio
        await _setupPeerConnection();
        await _startLocalAudio();
      } else {
        _addDebugLog('📡 Creating new socket connection');
        
        // Add connection timeout
        Future.delayed(const Duration(seconds: 15), () {
          if (socket?.connected != true) {
            _addDebugLog('⏱️ Connection timeout');
            _updateStatus('Connection Timeout');
          }
        });

        socket = io.io(signalingServerUrl, <String, dynamic>{
          'transports': ['websocket'],
          'autoConnect': false,
          'timeout': 20000,
        });

        _setupSocketEventHandlers();
        socket!.connect();
      }
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

      // Join room as mobile client
      socket!.emit('join_room', {
        'room': widget.cameraCode,
        'client_type': 'mobile',
      });
      _addDebugLog('📱 Joining room: ${widget.cameraCode} as mobile client');

      // Setup peer connection and local audio
      await _setupPeerConnection();
      await _startLocalAudio();
    });

    socket!.onConnectError((err) {
      _addDebugLog('❌ Socket connect error: $err');
      _updateStatus('Connect Error');
    });

    socket!.onError((err) {
      _addDebugLog('❌ Socket error: $err');
    });

    socket!.onDisconnect((reason) {
      _addDebugLog('🔌 Socket disconnected: $reason');
      _updateStatus('Disconnected');
      
      // Try to reconnect if this is not the existing socket
      if (socket != widget.existingSocket) {
        _addDebugLog('🔄 Attempting to reconnect...');
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            _connectToServer();
          }
        });
      }
    });

    // Room events
    socket!.on('joined_room', (data) {
      _addDebugLog('🏠 Successfully joined room: ${data['room']}');
      _updateStatus('Waiting for camera...');
      
      // Set a timeout for waiting for the camera
      Future.delayed(const Duration(seconds: 10), () {
        if (mounted && !_isCallActive) {
          _addDebugLog('⏱️ Timeout waiting for camera');
          _updateStatus('Camera not responding');
        }
      });
    });

    socket!.on('camera_available', (data) {
      _addDebugLog('📹 Camera is available and ready');
      _updateStatus('Camera ready - waiting for call...');
    });

    socket!.on('camera_not_found', (data) {
      _addDebugLog('❌ Camera not found in room: ${data['room']}');
      _updateStatus('Camera not found');
      
      // Navigate back after a delay
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          Navigator.of(context).pop();
        }
      });
    });

    // WebRTC signaling events
    socket!.on('offer', (data) async {
      _addDebugLog('📞 Received offer from camera');
      try {
        await _handleOffer(data);
      } catch (e) {
        _addDebugLog('❌ Error handling offer: $e');
      }
    });

    socket!.on('ice_candidate', (data) async {
      _addDebugLog('🧊 Received ICE candidate from camera');
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
  }

  Future<void> _setupPeerConnection() async {
    try {
      _addDebugLog('🔗 Setting up peer connection (nuclear config)...');

      // Reset state
      _isPeerConnectionReady = false;
      _queuedIceCandidates.clear();

      // Use minimal nuclear config
      _peerConnection = await createPeerConnection(_peerConfig, _peerConstraints);
      _addDebugLog('✅ Peer connection created (nuclear config)');

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
        _addDebugLog('🧊 Sending ICE candidate to camera');
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

  Future<void> _processQueuedIceCandidates() async {
    if (_peerConnection == null) return;

    _addDebugLog(
      '🔁 Processing ${_queuedIceCandidates.length} queued ICE candidates',
    );

    for (var candidateData in _queuedIceCandidates) {
      try {
        final candidate = RTCIceCandidate(
          candidateData['candidate'],
          candidateData['sdpMid'],
          candidateData['sdpMLineIndex'],
        );
        await _peerConnection!.addCandidate(candidate);
        _addDebugLog('✅ Processed queued ICE candidate');
      } catch (e) {
        _addDebugLog('❌ Error processing queued ICE candidate: $e');
      }
    }

    _queuedIceCandidates.clear();
  }

  Future<void> _startLocalAudio() async {
    try {
      _addDebugLog('🎤 Starting local audio...');

      final Map<String, dynamic> mediaConstraints = {
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
          'sampleRate': 48000,
          'channelCount': 1,
        },
        'video': false, // Mobile only sends audio
      };

      _addDebugLog('📱 Requesting audio permissions...');
      _localStream = await navigator.mediaDevices.getUserMedia(
        mediaConstraints,
      );

      if (_localStream != null) {
        _localRenderer.srcObject = _localStream;

        _addDebugLog('✅ Local audio started successfully');
        _addDebugLog(
          '📊 Local stream tracks: ${_localStream!.getTracks().length}',
        );

        // Log track details
        _localStream!.getTracks().forEach((track) {
          _addDebugLog(
            '🎬 Local ${track.kind} track: ${track.id} - enabled: ${track.enabled}',
          );
        });

        // Verify we have audio tracks
        final audioTracks = _localStream!.getAudioTracks();
        if (audioTracks.isEmpty) {
          throw Exception('No audio tracks in local stream');
        }
        _addDebugLog('✅ Audio track verified: ${audioTracks[0].id}');
      } else {
        throw Exception('Failed to get audio stream - stream is null');
      }
    } catch (e) {
      _addDebugLog('❌ Audio error: $e');
      // Try with simpler constraints if the first attempt fails
      try {
        _addDebugLog('🔄 Retrying with simpler audio constraints...');
        final Map<String, dynamic> simpleConstraints = {
          'audio': true,
          'video': false,
        };
        
        _localStream = await navigator.mediaDevices.getUserMedia(simpleConstraints);
        if (_localStream != null) {
          _localRenderer.srcObject = _localStream;
          _addDebugLog('✅ Local audio started with simple constraints');
        } else {
          throw Exception('Failed to get audio stream with simple constraints');
        }
      } catch (retryError) {
        _addDebugLog('❌ Audio retry failed: $retryError');
        rethrow;
      }
    }
  }

  Future<void> _resetPeerConnection() async {
    _addDebugLog('🔄 Resetting peer connection completely...');
    
    // Mark as not ready
    _isPeerConnectionReady = false;
    
    // Clear queued candidates
    _queuedIceCandidates.clear();
    
    // Close and dispose peer connection
    if (_peerConnection != null) {
      try {
        await _peerConnection!.close();
        _addDebugLog('✅ Peer connection closed');
      } catch (e) {
        _addDebugLog('⚠️ Error closing peer connection: $e');
      }
      _peerConnection = null;
    }
    
    // Dispose local stream
    if (_localStream != null) {
      try {
        _localStream!.dispose();
        _addDebugLog('✅ Local stream disposed');
      } catch (e) {
        _addDebugLog('⚠️ Error disposing local stream: $e');
      }
      _localStream = null;
    }
    
    // Clear renderers
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
    
    // Small delay to ensure cleanup is complete
    await Future.delayed(const Duration(milliseconds: 200));
    _addDebugLog('✅ Peer connection reset complete');
  }

  Future<void> _nuclearReset() async {
    _addDebugLog('☢️ NUCLEAR RESET: Complete WebRTC stack reset...');
    
    // Mark as not ready
    _isPeerConnectionReady = false;
    
    // Clear queued candidates
    _queuedIceCandidates.clear();
    
    // Force close and dispose peer connection
    if (_peerConnection != null) {
      try {
        await _peerConnection!.close();
        _addDebugLog('✅ Peer connection force closed');
      } catch (e) {
        _addDebugLog('⚠️ Error closing peer connection: $e');
      }
      _peerConnection = null;
    }
    
    // Force dispose local stream
    if (_localStream != null) {
      try {
        _localStream!.dispose();
        _addDebugLog('✅ Local stream force disposed');
      } catch (e) {
        _addDebugLog('⚠️ Error disposing local stream: $e');
      }
      _localStream = null;
    }
    
    // Clear renderers
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
    
    // Force garbage collection (if available)
    try {
      // This might help on some platforms
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      // Ignore
    }
    
    _addDebugLog('☢️ NUCLEAR RESET: Complete');
  }

  // --- Force restart WebRTC stack ---
  Future<void> _forceRestartWebRTC() async {
    _addDebugLog('🔄 FORCE RESTART: Complete WebRTC stack restart...');
    
    // Mark as not ready
    _isPeerConnectionReady = false;
    
    // Clear queued candidates
    _queuedIceCandidates.clear();
    
    // Force close and dispose peer connection
    if (_peerConnection != null) {
      try {
        await _peerConnection!.close();
        _addDebugLog('✅ Peer connection force closed');
      } catch (e) {
        _addDebugLog('⚠️ Error closing peer connection: $e');
      }
      _peerConnection = null;
    }
    
    // Force dispose local stream
    if (_localStream != null) {
      try {
        _localStream!.dispose();
        _addDebugLog('✅ Local stream force disposed');
      } catch (e) {
        _addDebugLog('⚠️ Error disposing local stream: $e');
      }
      _localStream = null;
    }
    
    // Clear renderers
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
    
    // Force garbage collection and wait longer
    await Future.delayed(const Duration(milliseconds: 2000));
    
    _addDebugLog('🔄 FORCE RESTART: Complete');
  }

  Future<void> _handleOffer(dynamic data) async {
    try {
      _addDebugLog('📞 Processing offer from camera...');

      // Force restart before handling new offer
      await _forceRestartWebRTC();

      // Create fresh peer connection with minimal config
      await _setupPeerConnection();

      // Validate offer data
      if (data['sdp'] == null ||
          data['sdp']['sdp'] == null ||
          data['sdp']['type'] == null) {
        throw Exception('Invalid offer format');
      }

      _addDebugLog('📄 Offer SDP type: ${data['sdp']['type']}');

      final offer = RTCSessionDescription(
        data['sdp']['sdp'],
        data['sdp']['type'],
      );
      
      // Set remote description first
      await _peerConnection!.setRemoteDescription(offer);
      _addDebugLog('✅ Remote description (offer) set');

      // Ensure local stream is started before adding tracks
      if (_localStream == null) {
        _addDebugLog('⚠️ No local stream, starting local audio...');
        await _startLocalAudio();
      }

      // Add local stream tracks if available
      if (_localStream != null) {
        _addDebugLog('➕ Adding local stream tracks to peer connection...');
        for (final track in _localStream!.getTracks()) {
          try {
            await _peerConnection!.addTrack(track, _localStream!);
            _addDebugLog(
              '➕ Added ${track.kind} track to peer connection: ${track.id}',
            );
          } catch (e) {
            _addDebugLog('❌ Error adding ${track.kind} track: $e');
          }
        }
        
        // Wait a bit for tracks to be added
        await Future.delayed(const Duration(milliseconds: 500));
        _addDebugLog('✅ All tracks added to peer connection');
      } else {
        _addDebugLog('⚠️ No local stream available to add to peer connection');
      }

      // Create and send answer with proper constraints
      await _createAndSendAnswer();

      // Mark peer connection as ready and process queued candidates
      _isPeerConnectionReady = true;
      await _processQueuedIceCandidates();
    } catch (e) {
      _addDebugLog('❌ Error in handleOffer: $e');
      _updateStatus('Offer Error');
      
      // Clean up on error
      await _forceRestartWebRTC();
    }
  }

  Future<void> _createAndSendAnswer() async {
    try {
      if (_peerConnection == null) {
        throw Exception('PeerConnection is null');
      }

      _addDebugLog('📞 Creating answer...');
      _addDebugLog('📡 Current signaling state: ${_peerConnection!.signalingState}');

      // Ensure we're in the correct state to create an answer
      if (_peerConnection!.signalingState != RTCSignalingState.RTCSignalingStateHaveRemoteOffer) {
        _addDebugLog('⚠️ Signaling state is not HaveRemoteOffer: ${_peerConnection!.signalingState}');
        await Future.delayed(const Duration(milliseconds: 500));
        if (_peerConnection!.signalingState != RTCSignalingState.RTCSignalingStateHaveRemoteOffer) {
          throw Exception('Invalid signaling state for creating answer: ${_peerConnection!.signalingState}');
        }
      }

      // Create answer with proper constraints
      final answer = await _peerConnection!.createAnswer(_offerAnswerConstraints);

      // Log SDP details for debugging
      _addDebugLog('📄 Answer SDP type: ${answer.type}');
      _addDebugLog('📄 Answer SDP length: ${answer.sdp?.length ?? 0}');

      // Set local description with retry logic
      int retryCount = 0;
      const maxRetries = 3;
      
      while (retryCount < maxRetries) {
        try {
          await _peerConnection!.setLocalDescription(answer);
          _addDebugLog('✅ Local description (answer) set successfully on attempt ${retryCount + 1}');
          break;
        } catch (e) {
          retryCount++;
          _addDebugLog('❌ Failed to set local description (attempt $retryCount): $e');
          
          if (retryCount >= maxRetries) {
            throw Exception('Failed to set local description after $maxRetries attempts: $e');
          }
          
          // Wait before retry
          await Future.delayed(Duration(milliseconds: 200 * retryCount));
        }
      }

      if (socket?.connected == true) {
        socket!.emit('answer', {
          'room': widget.cameraCode,
          'sdp': answer.toMap(),
        });
        _addDebugLog('📤 Answer sent to camera');
      } else {
        throw Exception('Socket not connected');
      }
    } catch (e) {
      _addDebugLog('❌ Error creating/sending answer: $e');
      _updateStatus('Answer Error');
      rethrow;
    }
  }

  Future<void> _handleIceCandidate(dynamic data) async {
    try {
      if (_peerConnection == null || !_isPeerConnectionReady) {
        _addDebugLog('⏳ Queueing ICE candidate (peer connection not ready)');
        _queuedIceCandidates.add(data);
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
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _updateStatus(String status) {
    if (mounted) {
      setState(() => _connectionStatus = status);
    }
  }

  void _restartCall() async {
    _addDebugLog('🔄 Restarting call completely (force restart)...');
    _updateStatus('Restarting call...');
    
    // Force restart everything
    await _forceRestartWebRTC();
    
    // Reconnect to server
    if (socket != null) {
      socket!.disconnect();
      socket!.dispose();
    }
    
    // Wait longer for complete cleanup
    await Future.delayed(const Duration(milliseconds: 2000));
    
    // Reconnect
    _connectToServer();
  }

  void _forceRestartApp() async {
    _addDebugLog('🔄 FORCE RESTART APP: Complete app restart...');
    _updateStatus('Force restarting app...');
    
    // Force restart everything
    await _forceRestartWebRTC();
    
    // Disconnect socket
    if (socket != null) {
      socket!.disconnect();
      socket!.dispose();
    }
    
    // Wait for cleanup
    await Future.delayed(const Duration(milliseconds: 3000));
    
    // Reconnect everything
    _connectToServer();
  }

  void _reconnect() {
    _addDebugLog('♻️ Attempting to reconnect...');
    _updateStatus('Reconnecting...');
    _restartCall();
  }

  @override
  void dispose() {
    _addDebugLog('♻️ Disposing resources (nuclear cleanup)...');

    // Use the nuclear reset method for complete cleanup
    _nuclearReset();

    // Dispose of renderers
    _localRenderer.dispose();
    _remoteRenderer.dispose();

    // Only disconnect socket if it's not the existing one from main dashboard
    if (socket != null && socket != widget.existingSocket) {
      socket!.disconnect();
      socket!.dispose();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Video Call - ${widget.cameraCode}'),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
        actions: [
          Icon(
            _isCallActive ? Icons.videocam : Icons.videocam_off,
            color: _isCallActive ? Colors.white : Colors.grey,
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
            color: _isCallActive
                ? Colors.green.shade100
                : Colors.orange.shade100,
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
                  'ICE: $_iceConnectionState | Camera: ${widget.cameraCode}',
                  style: const TextStyle(fontSize: 12),
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
                  color: _isCallActive ? Colors.green : Colors.grey,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Stack(
                  children: [
                    _remoteRenderer.srcObject != null
                        ? RTCVideoView(
                            _remoteRenderer,
                            objectFit: RTCVideoViewObjectFit
                                .RTCVideoViewObjectFitCover,
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
                          '📹 Camera Video',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ),
                    // Local audio indicator
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _isMuted ? Colors.red : Colors.green,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isMuted ? Icons.mic_off : Icons.mic,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Control buttons
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    FloatingActionButton(
                      onPressed: _toggleMute,
                      backgroundColor: _isMuted ? Colors.red : Colors.green,
                      child: Icon(
                        _isMuted ? Icons.mic_off : Icons.mic,
                        color: Colors.white,
                      ),
                    ),
                    FloatingActionButton(
                      onPressed: _endCall,
                      backgroundColor: Colors.red,
                      child: const Icon(Icons.call_end, color: Colors.white),
                    ),
                    FloatingActionButton(
                      onPressed: _reconnect,
                      backgroundColor: Colors.blue,
                      child: const Icon(Icons.refresh, color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _forceRestartApp,
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('Force Restart'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
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
                      },                   ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}


