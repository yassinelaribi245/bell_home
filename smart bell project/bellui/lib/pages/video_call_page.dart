import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:bellui/services/api_service.dart';
import 'package:bellui/models/models.dart';
import 'package:bellui/utils/utils.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class VideoCallPage extends StatefulWidget {
  final String cameraCode;
  final String roomId;
  final Camera camera;
  final bool isMainAppCall;
  final io.Socket? existingSocket;

  const VideoCallPage({
    super.key,
    required this.cameraCode,
    required this.roomId,
    required this.camera,
    this.existingSocket,
    this.isMainAppCall = false,
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

  Timer? _connectionTimeout;

  // Configuration
  final String signalingServerUrl = ApiService.nodeServerUrl;

  // This URL points to your Ngrok-hosted Node.js server's new credential endpoint
  final String twilioTurnCredentialServerUrl = 'https://21fad3a22452.ngrok-free.app/twilio_turn_credentials'; 

  @override
  void initState() {
    super.initState();
    _initRenderers();
    _connectToServer();
  }

  @override
  void dispose() {
    _endCall();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _connectionTimeout?.cancel();
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
    debugPrint('🔔 [BELLUI] $message');
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
        _addDebugLog("Failed to fetch Twilio TURN credentials: ${response.statusCode} ${response.body}");
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
      _localRenderer.srcObject = null;
      _remoteRenderer.srcObject = null;
      _addDebugLog('✅ Video renderers initialized and reset');
    } catch (e) {
      _addDebugLog('❌ Error initializing renderers: $e');
      rethrow;
    }
  }

  void _connectToServer() {
    _addDebugLog('🔗 Preparing signaling connection...');
    if (widget.existingSocket != null && widget.existingSocket!.connected) {
      socket = widget.existingSocket;
      _addDebugLog('📡 Using existing connected socket');
      _setupSocketEventHandlers();
      _joinRoom();
    } else {
      _addDebugLog('📡 Creating new socket connection');
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
    socket!.onConnect((_) {
      _addDebugLog('✅ Connected to Node.js server at: $signalingServerUrl');
      _updateStatus('Connected to server');
      if (!_hasJoinedRoom) {
        _joinRoom();
      }
    });

    socket!.onConnectError((err) {
      _addDebugLog('❌ Socket connect error: $err');
      _updateStatus('Connect Error: $err');
      _showError('Connection error: $err');
    });

    socket!.onConnectTimeout((_) {
      _addDebugLog('⏰ Socket connection timeout');
      _updateStatus('Connection Timeout');
      _showError('Connection timeout');
    });

    socket!.onError((err) {
      _addDebugLog('❌ Socket error: $err');
      _updateStatus('Socket Error: $err');
      _showError('Socket error: $err');
    });

    socket!.onDisconnect((reason) {
      _addDebugLog('🔌 Socket disconnected: $reason');
      _updateStatus('Disconnected: $reason');
      _endCall();
    });

    socket!.on('joined_room', (data) {
      _addDebugLog('🏠 Server confirmed joined room: ${data['room']}');
      setState(() {
        _hasJoinedRoom = true;
      });
      // Start connection timeout after joining room
      _startConnectionTimeout();
    });

    socket!.on('offer', (data) async {
      _addDebugLog('📞 Received offer from camera');
      await _handleOffer(data);
    });

    socket!.on('ice_candidate', (data) async {
      _addDebugLog('🧊 Received ICE candidate from camera');
      await _handleIceCandidate(data);
    });

    socket!.on('call_ended', (data) {
      _addDebugLog('📞 Call ended by remote peer');
      _endCall();
    });
  }

  void _joinRoom() {
    _addDebugLog('📱 Joining room: ${widget.cameraCode} as mobile client');
    socket!.emit('join_room', {
      'room': widget.cameraCode,
      'client_type': 'mobile',
    });
  }

  Future<void> _setupPeerConnection() async {
    try {
      _addDebugLog('🔗 Setting up peer connection with enhanced config...');
      _updateStatus('Setting up peer connection...');
      _isPeerConnectionReady = false;
      _queuedIceCandidates.clear();

      // Fetch dynamic Twilio TURN credentials
      final turnCredentials = await _fetchTwilioTurnCredentials();

      final config = {
        "iceServers": turnCredentials["iceServers"], // Use fetched ICE servers from Twilio
        "iceCandidatePoolSize": 10,
        "bundlePolicy": "max-bundle",
        "rtcpMuxPolicy": "require",
      };

      _peerConnection = await createPeerConnection(config);

      if (_peerConnection == null) {
        throw Exception('Failed to create peer connection');
      }

      _addDebugLog('✅ Peer connection created with enhanced config');
      _updateStatus('Peer connection ready');

      _setupPeerConnectionHandlers();
      _isPeerConnectionReady = true;
      _addDebugLog('✅ Peer connection marked as ready');
      // Process queued candidates only after remote description is set in _handleOffer
    } catch (e, st) {
      _addDebugLog('❌ Peer connection setup error: $e\n$st');
      _updateStatus('PeerConnection Error: $e');
      _showError('PeerConnection error: $e');
      return;
    }
  }

  void _setupPeerConnectionHandlers() {
    _peerConnection!.onTrack = (event) {
      _addDebugLog("📡 Received remote track from camera");

      if (event.streams.isNotEmpty) {
        final remoteStream = event.streams[0];
        _addDebugLog(
          "📹 Remote stream has ${remoteStream.getTracks().length} tracks",
        );

        setState(() {
          _remoteRenderer.srcObject = remoteStream;
          _isCallActive = true;
        });

        _addDebugLog("✅ Remote stream set to renderer");
        _updateStatus("Video call active!");
        _cancelConnectionTimeout(); // Connection established, cancel timeout
      } else {
        _addDebugLog("⚠️ Received track but no streams available");
      }
    };

    _peerConnection!.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        _addDebugLog("🧊 Sending ICE candidate to camera");
        if (socket?.connected == true) {
          socket!.emit("ice_candidate", {
            "room": widget.cameraCode,
            "candidate": candidate.candidate,
            "sdpMid": candidate.sdpMid,
            "sdpMLineIndex": candidate.sdpMLineIndex,
          });
        } else {
          _addDebugLog("⚠️ Socket not connected, cannot send ICE candidate");
        }
      }
    };

    _peerConnection!.onIceConnectionState = (state) {
      _addDebugLog("🔗 ICE connection state: $state");
      setState(() => _iceConnectionState = state.toString());

      switch (state) {
        case RTCIceConnectionState.RTCIceConnectionStateConnected:
          _addDebugLog("✅ ICE connection established - video should start");
          _updateStatus("Connected!");
          _cancelConnectionTimeout();
          break;
        case RTCIceConnectionState.RTCIceConnectionStateCompleted:
          _addDebugLog("✅ ICE connection completed - video should be working");
          _updateStatus("Connection established");
          _cancelConnectionTimeout();
          break;
        case RTCIceConnectionState.RTCIceConnectionStateFailed:
          _addDebugLog("❌ ICE connection failed - attempting recovery...");
          _updateStatus("Connection failed - retrying...");
          _attemptIceRecovery();
          break;
        case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
          _addDebugLog(
            "⚠️ ICE connection disconnected - attempting recovery...",
          );
          _updateStatus("Connection lost - retrying...");
          _attemptIceRecovery();
          break;
        case RTCIceConnectionState.RTCIceConnectionStateClosed:
          _addDebugLog("📞 ICE connection closed");
          _updateStatus("Call ended");
          _endCall();
          break;
        default:
          _addDebugLog("🔗 ICE state: $state");
          _updateStatus("ICE: $state");
      }
    };

    _peerConnection!.onConnectionState = (state) {
      _addDebugLog("🔗 Peer connection state: $state");
      
      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _addDebugLog("✅ Peer connection fully established");
          _updateStatus("Connected - video should be streaming");
          _cancelConnectionTimeout();
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          _addDebugLog("❌ Peer connection failed - attempting restart");
          _updateStatus("Connection failed - restarting...");
          _restartCall();
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          _addDebugLog("⚠️ Peer connection disconnected");
          _updateStatus("Connection lost");
          break;
        default:
          _updateStatus("Connection: $state");
      }
    };

    _peerConnection!.onSignalingState = (state) {
      _addDebugLog("📡 Signaling state: $state");
      _updateStatus("Signaling: $state");
    };

    _peerConnection!.onIceGatheringState = (state) {
      _addDebugLog("🧊 ICE gathering state: $state");
    };
  }

  void _attemptIceRecovery() {
    _addDebugLog('🔄 Attempting ICE recovery...');
    Future.delayed(const Duration(seconds: 3), () async {
      if (_peerConnection != null && mounted) {
        try {
          await _peerConnection!.restartIce();
          _addDebugLog('✅ ICE restart initiated');
        } catch (e) {
          _addDebugLog('❌ ICE restart failed: $e');
          _restartCall(); // If ICE restart fails, try full call restart
        }
      }
    });
  }

  Future<void> _processQueuedIceCandidates() async {
    if (_peerConnection == null || !_isPeerConnectionReady) {
      _addDebugLog("⚠️ Cannot process queued candidates - peer connection not ready");
      return;
    }

    if (_peerConnection!.getRemoteDescription() == null) {
      _addDebugLog("⚠️ Cannot process queued candidates - no remote description");
      return;
    }

    if (_queuedIceCandidates.isEmpty) {
      _addDebugLog("ℹ️ No queued ICE candidates to process");
      return;
    }

    _addDebugLog("🔁 Processing ${_queuedIceCandidates.length} queued ICE candidates...");

    final candidatesToProcess = List<Map<String, dynamic>>.from(_queuedIceCandidates);
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
        _addDebugLog("✅ Processed queued ICE candidate");
      } catch (e) {
        failureCount++;
        _addDebugLog("❌ Error processing queued ICE candidate: $e");
        // Don't re-queue failed candidates to avoid infinite loops
      }
    }

    _addDebugLog("✅ Finished processing queued ICE candidates: $successCount success, $failureCount failed");
  }

  Future<void> _startLocalAudio() async {
    try {
      _addDebugLog('🎤 Starting local audio...');

      final Map<String, dynamic> mediaConstraints = {
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      };

      _localStream = await navigator.mediaDevices.getUserMedia(
        mediaConstraints,
      );

      if (_localStream != null) {
        _localRenderer.srcObject = _localStream;
        _addDebugLog('✅ Local audio started successfully');
      } else {
        throw Exception('Failed to get audio stream - stream is null');
      }
    } catch (e) {
      _addDebugLog('❌ Audio error: $e');
      try {
        _addDebugLog('🔄 Retrying with simpler audio constraints...');
        final Map<String, dynamic> simpleConstraints = {
          'audio': true,
          'video': false,
        };

        _localStream = await navigator.mediaDevices.getUserMedia(
          simpleConstraints,
        );
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

  Future<void> _handleOffer(dynamic data) async {
    try {
      _addDebugLog('📞 Processing offer from camera...');

      if (_peerConnection == null) {
        await _setupPeerConnection();
      }

      if (data == null || data['sdp'] == null) {
        _addDebugLog('❌ Invalid offer format');
        return;
      }

      final offer = RTCSessionDescription(
        data['sdp']['sdp'],
        data['sdp']['type'],
      );

      await _peerConnection!.setRemoteDescription(offer);
      _addDebugLog('✅ Remote description (offer) set');

      // Process queued ICE candidates immediately after setting remote description
      await _processQueuedIceCandidates();

      if (_localStream == null) {
        await _startLocalAudio();
      }

      if (_localStream != null) {
        for (final track in _localStream!.getTracks()) {
          try {
            await _peerConnection!.addTrack(track, _localStream!);
            _addDebugLog('➕ Added ${track.kind} track to peer connection');
          } catch (e) {
            _addDebugLog('❌ Error adding ${track.kind} track: $e');
          }
        }
      }

      await _createAndSendAnswer();
    } catch (e) {
      _addDebugLog('❌ Error in handleOffer: $e');
      _updateStatus('Offer Error: $e');
      _showError('Offer processing error: $e');
    }
  }

  Future<void> _createAndSendAnswer() async {
    try {
      if (_peerConnection == null) {
        throw Exception('PeerConnection is null');
      }

      _addDebugLog('📞 Creating answer...');
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);
      _addDebugLog('✅ Local description (answer) set');

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
      _updateStatus('Answer Error: $e');
      _showError('Answer error: $e');
      rethrow;
    }
  }

  Future<void> _handleIceCandidate(dynamic data) async {
    try {
      if (data == null || data["candidate"] == null) {
        _addDebugLog("❌ Invalid ICE candidate data");
        return;
      }

      // Always queue candidates if peer connection isn't ready or remote description isn't set
      if (_peerConnection == null || 
          _peerConnection!.getRemoteDescription() == null) {
        _addDebugLog("⏳ Queueing ICE candidate (PC ready: $_isPeerConnectionReady, RD set: ${_peerConnection?.getRemoteDescription() != null}): ${data['candidate']}");
        _queuedIceCandidates.add(data);
        return;
      }

      final candidate = RTCIceCandidate(
        data["candidate"],
        data["sdpMid"],
        data["sdpMLineIndex"],
      );

      await _peerConnection!.addCandidate(candidate);
      _addDebugLog("✅ Added ICE candidate: ${candidate.candidate}");
    } catch (e) {
      _addDebugLog("❌ Error adding ICE candidate: $e");
      _showError("Error adding ICE candidate: $e");
    }
  }

  void _endCall() {
    _addDebugLog("📞 Ending call...");
    _updateStatus("Call ended");
    _connectionTimeout?.cancel();

    if (socket?.connected == true) {
      socket!.emit('call_ended', {'room': widget.cameraCode});
      _addDebugLog('📤 Sent call_ended to camera');
    }

    _peerConnection?.close();
    _peerConnection = null;

    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream?.dispose();
    _localStream = null;

    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;

    setState(() {
      _isCallActive = false;
      _isMuted = false;
      _isPeerConnectionReady = false;
      _iceConnectionState = 'New';
      _queuedIceCandidates.clear();
    });
    _addDebugLog("✅ Call ended successfully");
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
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _toggleMute() {
    if (_localStream != null) {
      bool currentMuteState = !_isMuted;
      _localStream!.getAudioTracks().forEach((track) {
        track.enabled = !currentMuteState;
      });
      setState(() {
        _isMuted = currentMuteState;
      });
      _addDebugLog('🎤 Local audio ${currentMuteState ? 'muted' : 'unmuted'}');
    }
  }

  void _startConnectionTimeout() {
    _connectionTimeout?.cancel(); // Cancel any existing timeout
    _addDebugLog('⏰ Starting 30-second connection timeout...');
    _connectionTimeout = Timer(const Duration(seconds: 30), () {
      if (!_isCallActive && mounted) {
        _addDebugLog('❌ Connection timeout: No active call after 30 seconds.');
        _showError('Call connection timed out. Please try again.');
        _endCall();
      }
    });
  }

  void _cancelConnectionTimeout() {
    if (_connectionTimeout != null && _connectionTimeout!.isActive) {
      _connectionTimeout!.cancel();
      _addDebugLog('✅ Connection timeout cancelled.');
    }
  }

  void _restartCall() {
    _addDebugLog('🔄 Restarting call...');
    _endCall();
    // Give a small delay before attempting to reconnect
    Future.delayed(const Duration(seconds: 2), () {
      _connectToServer();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Video Call with ${widget.camera.name}'),
        backgroundColor: Colors.blueAccent,
        actions: [
          IconButton(
            icon: Icon(_isMuted ? Icons.mic_off : Icons.mic),
            onPressed: _toggleMute,
            tooltip: _isMuted ? 'Unmute' : 'Mute',
          ),
        ],
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
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
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
                  onPressed: _isCallActive ? () => _endCall() : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('End Call'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _debugLogs.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
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


