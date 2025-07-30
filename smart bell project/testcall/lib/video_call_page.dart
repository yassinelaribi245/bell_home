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

  // Configuration - UPDATE THIS URL
  final String signalingServerUrl = 'https://c8eeb122-7274-4c11-9f14-b7fa09b317a3-00-2mmvsplajbe9g.kirk.replit.dev';

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
      
      socket = io.io(
        signalingServerUrl,
        <String, dynamic>{
          'transports': ['websocket'],
          'autoConnect': false,
          'timeout': 20000,
        },
      );

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
      
      // Join room as mobile client
      socket!.emit('join_room', {
        'room': widget.cameraCode,
        'client_type': 'mobile'
      });
      _addDebugLog('📱 Joining room: ${widget.cameraCode} as mobile client');
      
      // Setup peer connection and local audio immediately
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
    });

    // Room events
    socket!.on('joined_room', (data) {
      _addDebugLog('🏠 Successfully joined room: ${data['room']}');
      _updateStatus('Waiting for camera...');
    });

    socket!.on('camera_available', (data) {
      _addDebugLog('📹 Camera is available and ready');
      _updateStatus('Camera ready - waiting for call...');
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
      _addDebugLog('🔗 Setting up peer connection...');
      
      final Map<String, dynamic> config = {
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'},
        ],
        'iceCandidatePoolSize': 10,
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
        _addDebugLog('📹 Remote stream has ${remoteStream.getTracks().length} tracks');
        
        // Debug track information
        remoteStream.getTracks().forEach((track) {
          _addDebugLog('🎬 Remote ${track.kind} track - enabled: ${track.enabled}, ID: ${track.id}');
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

  Future<void> _startLocalAudio() async {
    try {
      _addDebugLog('🎤 Starting local audio...');
      
      final Map<String, dynamic> mediaConstraints = {
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false, // Mobile only sends audio
      };
      
      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      
      if (_localStream != null) {
        _localRenderer.srcObject = _localStream;
        
        _addDebugLog('✅ Local audio started successfully');
        _addDebugLog('📊 Local stream tracks: ${_localStream!.getTracks().length}');
        
        // Log track details
        _localStream!.getTracks().forEach((track) {
          _addDebugLog('🎬 Local ${track.kind} track: ${track.id} - enabled: ${track.enabled}');
        });
        
      } else {
        throw Exception('Failed to get audio stream');
      }
      
    } catch (e) {
      _addDebugLog('❌ Audio error: $e');
    }
  }

  Future<void> _handleOffer(dynamic data) async {
    try {
      _addDebugLog('📞 Processing offer from camera...');
      _addDebugLog('📄 Offer SDP type: ${data['sdp']['type']}');
      
      final offer = RTCSessionDescription(data['sdp']['sdp'], data['sdp']['type']);
      await _peerConnection!.setRemoteDescription(offer);
      _addDebugLog('✅ Remote description (offer) set');
      
      // Add local stream tracks to peer connection BEFORE creating answer
      if (_localStream != null) {
        _localStream!.getTracks().forEach((track) {
          _peerConnection!.addTrack(track, _localStream!);
          _addDebugLog('➕ Added ${track.kind} track to peer connection: ${track.id}');
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
        'offerToReceiveAudio': true,  // We want to receive audio from camera
        'offerToReceiveVideo': true,  // We want to receive video from camera
      };
      
      final answer = await _peerConnection!.createAnswer(answerOptions);
      
      // Log SDP details for debugging
      _addDebugLog('📄 Answer SDP type: ${answer.type}');
      _addDebugLog('📄 Answer SDP (first 100 chars): ${answer.sdp?.substring(0, 100)}...');
      
      await _peerConnection!.setLocalDescription(answer);
      _addDebugLog('✅ Local description (answer) set');
      
      socket!.emit('answer', {
        'room': widget.cameraCode,
        'sdp': answer.toMap()
      });
      _addDebugLog('📤 Answer sent to camera');
      
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
        title: Text('Video Call - ${widget.cameraCode}'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
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
            color: _isCallActive ? Colors.green.shade100 : Colors.orange.shade100,
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
                        ? RTCVideoView(_remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                        : Container(
                            color: Colors.black,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _isCallActive ? Icons.videocam : Icons.videocam_off,
                                  size: 80,
                                  color: _isCallActive ? Colors.white : Colors.grey,
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
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                  child: const Icon(
                    Icons.call_end,
                    color: Colors.white,
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
}
