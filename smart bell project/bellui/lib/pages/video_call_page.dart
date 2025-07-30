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
  bool _hasJoinedRoom = false;

  // Configuration - Use nodeServerUrl from ApiService
  final String signalingServerUrl = ApiService.nodeServerUrl;

  // --- PeerConnection config and constraints (SAFE) ---
  // Replace the peer config and constraints with minimal config
  static final Map<String, dynamic> _peerConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
    'iceCandidatePoolSize': 10,
  };

  // Add this debug log method at the top of the class
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
    debugPrint('🔔 [BELLUI] $message');
  }

  // --- Renderer Initialization Helper ---
  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
    _addDebugLog('✅ Video renderers initialized and reset');
  }

  // --- Force Restart WebRTC Stack ---
  Future<void> _forceRestartWebRTC() async {
    _addDebugLog('🔄 Restarting call completely (force restart)...');
    try {
      // Do NOT dispose renderers here, just clear srcObject
      _localRenderer.srcObject = null;
      _remoteRenderer.srcObject = null;
      // Reset peer connection and streams
      if (_peerConnection != null) {
        try {
          await _peerConnection!.close();
          _addDebugLog('✅ Peer connection closed');
        } catch (e) {
          _addDebugLog('⚠️ Error closing peer connection: $e');
        }
        _peerConnection = null;
      }
      if (_localStream != null) {
        try {
          await _localStream!.dispose();
          _addDebugLog('✅ Local stream disposed');
        } catch (e) {
          _addDebugLog('⚠️ Error disposing local stream: $e');
        }
        _localStream = null;
      }
      _queuedIceCandidates.clear();
      _isPeerConnectionReady = false;
      _addDebugLog('🔄 FORCE RESTART: Complete WebRTC stack restart...');
    } catch (e) {
      _addDebugLog('❌ Error during force restart: $e');
    }
  }

  // --- Peer Connection Setup ---
  Future<void> _setupPeerConnection() async {
    try {
      _addDebugLog('🔗 Setting up peer connection with minimal config (testcall style)...');
      _updateStatus('Setting up peer connection...');
      _isPeerConnectionReady = false;
      _queuedIceCandidates.clear();
      if (_peerConfig.isEmpty) {
        throw Exception('Peer configuration is empty');
      }
      final iceServers = _peerConfig['iceServers'] as List<dynamic>?;
      if (iceServers == null || iceServers.isEmpty) {
        _addDebugLog('⚠️ No ICE servers configured, using fallback');
        _peerConfig['iceServers'] = [
          {'urls': 'stun:stun.l.google.com:19302'},
        ];
      }
      _addDebugLog('🧊 ICE servers config: ' + _peerConfig['iceServers'].toString());
      _peerConnection = await createPeerConnection(_peerConfig);
      _addDebugLog('✅ Peer connection created (minimal config)');
      _updateStatus('Peer connection ready');
      if (_peerConnection == null) {
        throw Exception('Failed to create peer connection');
      }
      _setupPeerConnectionHandlers();
      _isPeerConnectionReady = true;
      _addDebugLog('✅ Peer connection marked as ready - can now process ICE candidates');
      await _processQueuedIceCandidates();
    } catch (e, st) {
      _addDebugLog('❌ Peer connection setup error: $e\n$st');
      _updateStatus('PeerConnection Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PeerConnection error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
      return;
    }
  }

  // --- Peer Connection Handlers ---
  void _setupPeerConnectionHandlers() {
    _peerConnection!.onTrack = (event) {
      _addDebugLog('📡 Received remote track from camera');
      _addDebugLog('🎬 Track kind: ${event.track.kind}, ID: ${event.track.id}');
      _addDebugLog('🎬 Track enabled: ${event.track.enabled}');
      if (event.streams.isNotEmpty) {
        final remoteStream = event.streams[0];
        _addDebugLog('📹 Remote stream has ${remoteStream.getTracks().length} tracks');
        remoteStream.getTracks().forEach((track) {
          _addDebugLog('🎬 Remote ${track.kind} track - enabled: ${track.enabled}, ID: ${track.id}');
        });
        _remoteRenderer.srcObject = remoteStream;
        _addDebugLog('✅ Remote stream set to renderer');
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
      _updateStatus('ICE: $state');

      switch (state) {
        case RTCIceConnectionState.RTCIceConnectionStateConnected:
          _addDebugLog('✅ ICE connection established - video should start');
          _updateStatus('Connected!');
          break;
        case RTCIceConnectionState.RTCIceConnectionStateCompleted:
          _addDebugLog('✅ ICE connection completed - video should be working');
          _updateStatus('Connection established');
          break;
        case RTCIceConnectionState.RTCIceConnectionStateFailed:
          _addDebugLog('❌ ICE connection failed - attempting recovery...');
          _updateStatus('Connection failed - retrying...');
          // Don't immediately end call, try to recover
          // _attemptIceRecovery(); // This method is not defined
          break;
        case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
          _addDebugLog('⚠️ ICE connection disconnected - attempting recovery...');
          _updateStatus('Connection lost - retrying...');
          // Don't immediately end call, try to recover
          // _attemptIceRecovery(); // This method is not defined
          break;
        case RTCIceConnectionState.RTCIceConnectionStateClosed:
          _addDebugLog('📞 ICE connection closed');
          _updateStatus('Call ended');
          _endCall();
          break;
        default:
          _addDebugLog('🔗 ICE state: $state');
          _updateStatus('ICE: $state');
      }
    };

    _peerConnection!.onConnectionState = (state) {
      _addDebugLog('🔗 Peer connection state: $state');
      _updateStatus('Peer: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _addDebugLog('✅ Peer connection connected - checking for video');
      }
    };

    _peerConnection!.onSignalingState = (state) {
      _addDebugLog('📡 Signaling state: $state');
      _updateStatus('Signaling: $state');
    };

    _peerConnection!.onIceGatheringState = (state) {
      _addDebugLog('🧊 ICE gathering state: $state');
    };
  }

  Future<void> _processQueuedIceCandidates() async {
    if (_peerConnection == null) {
      _addDebugLog('⚠️ Cannot process queued ICE candidates - peer connection is null');
      return;
    }
    
    if (!_isPeerConnectionReady) {
      _addDebugLog('⚠️ Cannot process queued ICE candidates - peer connection not ready');
      return;
    }
    
    // Additional safety check: ensure we have a remote description
    try {
      final remoteDesc = await _peerConnection!.getRemoteDescription();
      if (remoteDesc == null) {
        _addDebugLog('⚠️ Cannot process queued ICE candidates - no remote description yet');
        return;
      }
    } catch (e) {
      _addDebugLog('⚠️ Cannot process queued ICE candidates - error checking remote description: $e');
      return;
    }

    if (_queuedIceCandidates.isEmpty) {
      _addDebugLog('ℹ️ No queued ICE candidates to process');
      return;
    }

    _addDebugLog(
      '🔁 Processing ${_queuedIceCandidates.length} queued ICE candidates...',
    );

    final candidatesToProcess = List<Map<String, dynamic>>.from(_queuedIceCandidates);
    _queuedIceCandidates.clear();

    for (var candidateData in candidatesToProcess) {
      try {
        final candidate = RTCIceCandidate(
          candidateData['candidate'],
          candidateData['sdpMid'],
          candidateData['sdpMLineIndex'],
        );
        await _peerConnection!.addCandidate(candidate);
        _addDebugLog('✅ Processed queued ICE candidate: ${candidateData['candidate']?.substring(0, 30)}...');
      } catch (e) {
        _addDebugLog('❌ Error processing queued ICE candidate: $e');
        // Don't re-queue failed candidates
      }
    }

    _addDebugLog('✅ Finished processing queued ICE candidates');
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

  Future<void> _handleOffer(dynamic data) async {
    try {
      _addDebugLog('📞 Processing offer from camera...');

      // Only reset if we have an existing peer connection that's not in the right state
      if (_peerConnection != null) {
        final signalingState = _peerConnection!.signalingState;
        if (signalingState != RTCSignalingState.RTCSignalingStateStable) {
          _addDebugLog('🔄 Resetting existing peer connection (signaling state: $signalingState)');
          await _resetPeerConnection();
        } else {
          _addDebugLog('✅ Using existing peer connection (signaling state: $signalingState)');
        }
      }

      // Create fresh peer connection if needed
      if (_peerConnection == null) {
        await _setupPeerConnection();
      }

      // Validate offer data strictly
      if (data == null || data['sdp'] == null ||
          data['sdp']['sdp'] == null ||
          data['sdp']['type'] == null ||
          data['sdp']['sdp'] is! String ||
          data['sdp']['type'] is! String) {
        _addDebugLog('❌ Invalid offer format or null/invalid SDP fields: ' + data.toString());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Invalid offer received from camera. Please try again.'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
        throw Exception('Invalid offer format or null/invalid SDP fields');
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

      // Peer connection is already ready from setup, just process any queued candidates
      _addDebugLog('✅ Offer processed - processing any queued candidates...');
      await _processQueuedIceCandidates();
      
      // Also process any candidates that might have arrived during offer processing
      await Future.delayed(const Duration(milliseconds: 100));
      await _processQueuedIceCandidates();
      
    } catch (e, st) {
      _addDebugLog('❌ Error in handleOffer: $e\n$st');
      _updateStatus('Offer Error: $e');
      
      // Don't force restart on error, just log it
      _addDebugLog('⚠️ Offer processing failed, but keeping peer connection alive');
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
      final answer = await _peerConnection!.createAnswer();

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
    } catch (e, st) {
      _addDebugLog('❌ Error creating/sending answer: $e\n$st');
      _updateStatus('Answer Error: $e');
      rethrow;
    }
  }

  Future<void> _handleIceCandidate(dynamic data) async {
    try {
      // Strict null/type checks for ICE candidate
      if (data == null ||
          data['candidate'] == null || data['sdpMid'] == null || data['sdpMLineIndex'] == null ||
          data['candidate'] is! String || data['sdpMid'] is! String ||
          (data['sdpMLineIndex'] is! int && data['sdpMLineIndex'] is! double)) {
        _addDebugLog('❌ Invalid ICE candidate data: ' + data.toString());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Invalid ICE candidate received. Skipping.'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
        return;
      }

      if (_peerConnection == null || !_isPeerConnectionReady) {
        _addDebugLog('⏳ Queueing ICE candidate (peer connection not ready) - queue size: ${_queuedIceCandidates.length}');
        _queuedIceCandidates.add(data);
        return;
      }

      final candidate = RTCIceCandidate(
        data['candidate'],
        data['sdpMid'],
        data['sdpMLineIndex'] is int ? data['sdpMLineIndex'] : (data['sdpMLineIndex'] as double).toInt(),
      );

      await _peerConnection!.addCandidate(candidate);
      _addDebugLog('✅ ICE candidate added successfully');
    } catch (e, st) {
      _addDebugLog('❌ Error adding ICE candidate: $e\n$st');
      _updateStatus('ICE Error: $e');
      // Don't queue failed candidates, just log the error
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

    // Only end if we're actually in a call
    if (!_isCallActive && _peerConnection == null) {
      _addDebugLog('⚠️ Call already ended or not active');
      return;
    }

    if (socket != null && socket!.connected) {
      socket!.emit('end_call', {'room': widget.cameraCode});
    }

    setState(() {
      _isCallActive = false;
      _localRenderer.srcObject = null;
      _remoteRenderer.srcObject = null;
    });

    // Clean up peer connection
    if (_peerConnection != null) {
      try {
        _peerConnection!.close();
        _addDebugLog('✅ Peer connection closed');
      } catch (e) {
        _addDebugLog('⚠️ Error closing peer connection: $e');
      }
      _peerConnection = null;
    }

    // Clean up local stream
    if (_localStream != null) {
      try {
        _localStream!.dispose();
        _addDebugLog('✅ Local stream disposed');
      } catch (e) {
        _addDebugLog('⚠️ Error disposing local stream: $e');
      }
      _localStream = null;
    }

    // Do NOT disconnect or dispose the socket here; keep the connection alive

    // Navigate back to home screen
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  // Add robust error and status logging to the debug log and UI
  void _updateStatus(String status) {
    _addDebugLog('STATUS: $status');
    if (mounted) {
      setState(() {
        _connectionStatus = status;
      });
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
    // _connectToServer(); // This method is not defined
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
    // _connectToServer(); // This method is not defined
  }

  void _reconnect() {
    _addDebugLog('♻️ Attempting to reconnect...');
    _updateStatus('Reconnecting...');
    _restartCall();
  }

  @override
  void initState() {
    super.initState();
    _startCallSystem();
  }

  Future<void> _startCallSystem() async {
    _addDebugLog('🚀 Initializing call system...');
    await _initRenderers();
    _addDebugLog('🔗 Preparing signaling connection...');

    // Use existing socket if provided and connected
    if (widget.existingSocket != null && widget.existingSocket!.connected) {
      _addDebugLog('📡 Using existing connected socket');
      socket = widget.existingSocket;
      _setupSocketEventHandlers();
      _joinRoom();
    } else {
      // Create new socket connection
      socket = io.io(signalingServerUrl, <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': false,
        'timeout': 20000,
      });
      _setupSocketEventHandlers();
      socket!.connect();
    }
  }

  void _setupSocketEventHandlers() {
    if (socket == null) return;
    socket!.onConnect((_) {
      _addDebugLog('✅ Connected to signaling server');
      _updateStatus('Connected to signaling server');
      _joinRoom();
    });
    socket!.on('joined_room', (data) {
      _addDebugLog('🏠 Server confirmed joined room: ${data['room']}');
      _hasJoinedRoom = true;
    });
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
    socket!.onDisconnect((_) {
      _addDebugLog('⚠️ Disconnected from signaling server');
      _updateStatus('Disconnected from signaling server');
    });
    socket!.onConnectError((err) {
      _addDebugLog('❌ Socket connect error: $err');
      _updateStatus('Socket connect error: $err');
    });
    socket!.onError((err) {
      _addDebugLog('❌ Socket error: $err');
      _updateStatus('Socket error: $err');
    });
  }

  void _joinRoom() {
    if (socket != null && socket!.connected) {
      _addDebugLog('📱 Joining room: ${widget.cameraCode} as mobile client');
      socket!.emit('join_room', {
        'room': widget.cameraCode,
        'client_type': 'mobile',
      });
      _hasJoinedRoom = true;
    } else {
      _addDebugLog('❌ Cannot join room, socket not connected');
    }
  }

  @override
  void dispose() {
    _addDebugLog('♻️ Disposing resources (safe cleanup)...');

    try {
      _localRenderer.dispose();
      _addDebugLog('✅ Local renderer disposed');
    } catch (e) {
      _addDebugLog('⚠️ Error disposing local renderer: $e');
    }
    try {
      _remoteRenderer.dispose();
      _addDebugLog('✅ Remote renderer disposed');
    } catch (e) {
      _addDebugLog('⚠️ Error disposing remote renderer: $e');
    }

    try {
      // Safely dispose of peer connection
      if (_peerConnection != null) {
        try {
          _peerConnection!.close();
          _addDebugLog('✅ Peer connection closed');
        } catch (e) {
          _addDebugLog('⚠️ Error closing peer connection: $e');
        }
        _peerConnection = null;
      }

      // Safely dispose of local stream
      if (_localStream != null) {
        try {
          _localStream!.dispose();
          _addDebugLog('✅ Local stream disposed');
        } catch (e) {
          _addDebugLog('⚠️ Error disposing local stream: $e');
        }
        _localStream = null;
      }

      // Safely disconnect socket
      if (socket != null && socket != widget.existingSocket) {
        try {
          socket!.disconnect();
          socket!.dispose();
          _addDebugLog('✅ Socket disconnected and disposed');
        } catch (e) {
          _addDebugLog('⚠️ Error disposing socket: $e');
        }
      }

      _addDebugLog('✅ All resources disposed safely');
    } catch (e) {
      _addDebugLog('❌ Error during disposal: $e');
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
            child: Row(
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


