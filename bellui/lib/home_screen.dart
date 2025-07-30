import 'package:bellui/models/models.dart';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive/hive.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'pages/login_register.dart' as login_register;
import 'pages/video_call_page.dart';
import 'services/api_service.dart';
import 'dart:async';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? userName;
  String callStatus = 'No active calls';
  io.Socket? socket;
  bool isSocketConnected = false;
  bool isCameraAvailable = false;
  List<String> recentCalls = [];
  Timer? _connectionStatusTimer;
  String? _socketErrorMessage;

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  final String cameraCode = 'cam123';

  @override
  void initState() {
    super.initState();
    _initLocalNotifications();
    _setupFirebaseMessaging();
    _loadUserName();
    _initSocket();
    _loadRecentCalls();
    _startConnectionStatusTimer();
  }

  void _startConnectionStatusTimer() {
    _connectionStatusTimer?.cancel();
    _connectionStatusTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (socket != null) {
        debugPrint('Socket connection state: '
          'connected=${socket!.connected}, '
          'disconnected=${socket!.disconnected}, '
          'id=${socket!.id}');
      } else {
        debugPrint('Socket is null');
      }
    });
  }

  void _initLocalNotifications() {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    flutterLocalNotificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Handle notification tap
        if (response.payload != null) {
          _handleNotificationTap(response.payload!);
        }
      },
    );
  }

  void _setupFirebaseMessaging() async {
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    final token = await FirebaseMessaging.instance.getToken();
    debugPrint("FCM Token: $token");

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint("Received foreground message: ${message.data}");
      
      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;

      if (notification != null && android != null) {
        flutterLocalNotificationsPlugin.show(
          notification.hashCode,
          notification.title,
          notification.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              'smart_bell_channel',
              'Smart Bell Notifications',
              channelDescription: 'Notifications for Smart Bell calls',
              importance: Importance.max,
              priority: Priority.high,
              icon: '@mipmap/ic_launcher',
              fullScreenIntent: true,
              category: AndroidNotificationCategory.call,
            ),
          ),
          payload: message.data['camera_code'],
        );
      }

      // Show call dialog for smart bell notifications
      if (message.data['type'] == 'smart_bell_call') {
        _showCallDialog(
          notification?.title ?? 'Smart Bell',
          notification?.body ?? 'Someone is at your door',
          message.data['camera_code'] ?? cameraCode,
        );
      }
    });

    // Handle background message taps
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint("Opened app from notification: ${message.data}");
      
      if (message.data['type'] == 'smart_bell_call') {
        _showCallDialog(
          message.notification?.title ?? 'Smart Bell',
          message.notification?.body ?? 'Someone is at your door',
          message.data['camera_code'] ?? cameraCode,
        );
      }
    });

    // Check for initial message when app is opened from terminated state
    RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      debugPrint("App opened from terminated state: ${initialMessage.data}");
      
      if (initialMessage.data['type'] == 'smart_bell_call') {
        // Delay to ensure UI is ready
        Future.delayed(const Duration(seconds: 1), () {
          _showCallDialog(
            initialMessage.notification?.title ?? 'Smart Bell',
            initialMessage.notification?.body ?? 'Someone is at your door',
            initialMessage.data['camera_code'] ?? cameraCode,
          );
        });
      }
    }
  }

  void _handleNotificationTap(String payload) {
    debugPrint("Notification tapped with payload: $payload");
    // You can navigate to video call or show dialog based on payload
    _showCallDialog(
      'Smart Bell',
      'Someone is at your door',
      payload,
    );
  }

  void _showCallDialog(String title, String body, String cameraCode) {
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.doorbell, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(child: Text(title)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(body),
            const SizedBox(height: 16),
            Text(
              'Camera: $cameraCode',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              _respondToCall('rejected', cameraCode);
              Navigator.pop(context);
              _addToRecentCalls('Rejected', cameraCode);
            },
            icon: const Icon(Icons.call_end, color: Colors.red),
            label: const Text('Reject'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
          ElevatedButton.icon(
            onPressed: () {
              _respondToCall('accepted', cameraCode);
              Navigator.pop(context);
              _addToRecentCalls('Accepted', cameraCode);
              _startVideoCall(cameraCode);
            },
            icon: const Icon(Icons.video_call),
            label: const Text('Accept'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void _respondToCall(String response, String cameraCode) {
    if (socket != null && isSocketConnected) {
      socket!.emit('camera_response', {
        'response': response,
        'room': cameraCode,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      setState(() {
        callStatus = response == 'accepted' 
            ? 'Call accepted. Starting video...' 
            : 'Call rejected';
      });
      
      debugPrint("Sent camera response: $response for room: $cameraCode");
    } else {
      debugPrint("Socket not connected, cannot send response");
      setState(() {
        callStatus = 'Connection error - cannot respond to call';
      });
    }
  }

  void _loadUserName() {
    var box = Hive.box('authBox');
    final user = box.get('user');
    setState(() {
      userName = user != null ? user['nom'] : 'Unknown User';
    });
  }

  void _loadRecentCalls() {
    var box = Hive.box('authBox');
    final calls = box.get('recent_calls', defaultValue: <String>[]);
    setState(() {
      recentCalls = List<String>.from(calls);
    });
  }

  void _addToRecentCalls(String action, String cameraCode) {
    final timestamp = DateTime.now().toString().substring(0, 19);
    final callEntry = '$timestamp - $action call from $cameraCode';
    
    setState(() {
      recentCalls.insert(0, callEntry);
      if (recentCalls.length > 10) {
        recentCalls.removeLast();
      }
    });
    
    // Save to storage
    var box = Hive.box('authBox');
    box.put('recent_calls', recentCalls);
  }

  void _initSocket() {
    try {
      debugPrint('Attempting to connect to Node.js server at https://22565d3033e2.ngrok-free.app');
      socket = io.io('https://4216fd06f48d.ngrok-free.app', <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': false,
        'timeout': 20000,
      });

      socket!.onConnecting((_) {
        debugPrint('Socket connecting...');
      });

      socket!.onConnect((_) {
        debugPrint('Socket connected (Home Screen)');
        setState(() {
          isSocketConnected = true;
          callStatus = 'Connected - Ready for calls';
          _socketErrorMessage = null;
        });
        // Join room as mobile client
        socket!.emit('join_room', {
          'room': cameraCode,
          'client_type': 'mobile',
        });
      });

      socket!.onDisconnect((_) {
        debugPrint('Socket disconnected (Home Screen)');
        setState(() {
          isSocketConnected = false;
          callStatus = 'Disconnected from server';
          _socketErrorMessage = 'Disconnected from Node.js server.';
        });
        _showSocketError('Disconnected from Node.js server.');
      });

      socket!.onError((err) {
        debugPrint('Socket general error: $err');
        setState(() {
          isSocketConnected = false;
          callStatus = 'Error connecting to server';
          _socketErrorMessage = 'Error: $err';
        });
        _showSocketError('Error connecting to Node.js server: $err');
      });

      socket!.onConnectError((err) {
        debugPrint('Socket connection error: $err');
        setState(() {
          isSocketConnected = false;
          callStatus = 'Connection error';
          _socketErrorMessage = 'Connection error: $err';
        });
        _showSocketError('Connection error to Node.js server: $err');
      });

      debugPrint('Socket connect() called');
      socket!.connect();
    } catch (e) {
      debugPrint('Socket initialization error: $e');
      setState(() {
        isSocketConnected = false;
        callStatus = 'Socket initialization error';
        _socketErrorMessage = 'Socket initialization error: $e';
      });
      _showSocketError('Socket initialization error: $e');
    }
  }

  void _showSocketError(String message) {
    if (mounted) {
      final context = this.context;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _startVideoCall(String cameraCode) {
    // Find or create a Camera object to pass to VideoCallPage
    final camera = Camera(
      name: 'Smart Bell Camera',
      camCode: cameraCode,
      homeId: 0,
      homeName: 'Unknown Home',
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoCallPage(roomId: cameraCode, cameraCode: cameraCode, camera: camera),
      ),
    ).then((_) {
      setState(() {
        callStatus = isSocketConnected 
            ? 'Connected - Ready for calls' 
            : 'Disconnected from server';
      });
    });
  }

  void _reconnectSocket() {
    if (socket != null) {
      socket!.disconnect();
    }
    _initSocket();
  }

  void _testCall() {
    // Simulate a test call for debugging
    _showCallDialog(
      'Test Call',
      'This is a test smart bell notification',
      cameraCode,
    );
    // Trigger a notification for testing
    ApiService.triggerNotification(cameraCode);
  }

  Future<void> _logout() async {
    // Disconnect socket
    if (socket != null) {
      socket!.disconnect();
    }
    
    // Clear stored data
    var box = Hive.box('authBox');
    await box.clear();
    
    // Navigate to login
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const login_register.HomePage()),
        (route) => false,
      );
    }
  }

  @override
  void dispose() {
    _connectionStatusTimer?.cancel();
    socket?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Show error message in the UI if present
    if (_socketErrorMessage != null) {
      return Column(
        children: [
          Container(
            color: Colors.red,
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            child: Text(
              _socketErrorMessage!,
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ),
          Scaffold(
      appBar: AppBar(
              title: const Text('Vamera 1'),
        backgroundColor: const Color.fromARGB(255, 70, 46, 37),
        foregroundColor: Colors.white,
        actions: [
          Icon(
            isSocketConnected ? Icons.wifi : Icons.wifi_off,
            color: isSocketConnected ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'test':
                  _testCall();
                  break;
                case 'reconnect':
                  _reconnectSocket();
                  break;
                case 'logout':
                  _logout();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'test',
                child: Row(
                  children: [
                    Icon(Icons.bug_report),
                    SizedBox(width: 8),
                    Text('Test Call'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'reconnect',
                child: Row(
                  children: [
                    Icon(Icons.refresh),
                    SizedBox(width: 8),
                    Text('Reconnect'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout),
                    SizedBox(width: 8),
                    Text('Logout'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.person, size: 24),
                        const SizedBox(width: 8),
                        Text(
                          userName != null ? 'Welcome, $userName!' : 'Loading...',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                            'Vamera 1',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Status section
                  Card(
                    color: _getStatusCardColor(),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _getStatusIcon(),
                                color: _getStatusIconColor(),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Status',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            callStatus,
                            style: const TextStyle(fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Recent calls section
                  const Text(
                    'Recent Calls',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  
                  Expanded(
                    child: Card(
                      child: recentCalls.isEmpty
                          ? const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.call, size: 48, color: Colors.grey),
                                  SizedBox(height: 8),
                                  Text(
                                    'No recent calls',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: recentCalls.length,
                              itemBuilder: (context, index) {
                                final call = recentCalls[index];
                                final isAccepted = call.contains('Accepted');
                                
                                return ListTile(
                                  leading: Icon(
                                    isAccepted ? Icons.call_received : Icons.call_end,
                                    color: isAccepted ? Colors.green : Colors.red,
                                  ),
                                  title: Text(
                                    call,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete, size: 16),
                                    onPressed: () {
                                      setState(() {
                                        recentCalls.removeAt(index);
                                      });
                                      var box = Hive.box('authBox');
                                      box.put('recent_calls', recentCalls);
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                ],
              ),
            ),
            floatingActionButton: FloatingActionButton(
              onPressed: () => _startVideoCall(cameraCode),
              backgroundColor: const Color.fromARGB(255, 70, 46, 37),
              foregroundColor: Colors.white,
              child: const Icon(Icons.video_call),
            ),
          ),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vamera 1'),
        backgroundColor: const Color.fromARGB(255, 70, 46, 37),
        foregroundColor: Colors.white,
        actions: [
          PopupMenuButton<String>(
            icon: Icon(
              isSocketConnected ? Icons.wifi : Icons.wifi_off,
              color: isSocketConnected ? Colors.green : Colors.red,
            ),
            onSelected: (value) {
              if (value == 'status') {
                showDialog(
                  context: context,
                  builder: (context) {
                    return AlertDialog(
                      title: const Text('Node.js Server Connection Info'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                isSocketConnected ? Icons.check_circle : Icons.cancel,
                                color: isSocketConnected ? Colors.green : Colors.red,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                isSocketConnected ? 'Connected' : 'Not Connected',
                                style: TextStyle(
                                  color: isSocketConnected ? Colors.green : Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Text('Server URL:'),
                          const SizedBox(height: 4),
                          Text('https://22565d3033e2.ngrok-free.app', style: TextStyle(fontSize: 13, color: Colors.blueGrey)),
                          const SizedBox(height: 12),
                          if (_socketErrorMessage != null) ...[
                            const Text('Last Error:', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(_socketErrorMessage!, style: const TextStyle(color: Colors.red)),
                          ],
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Close'),
                        ),
                      ],
                    );
                  },
                );
              }
            },
            itemBuilder: (context) {
              List<PopupMenuEntry<String>> items = [
                PopupMenuItem<String>(
                  value: 'status',
                  child: Row(
                    children: [
                      Icon(
                        isSocketConnected ? Icons.check_circle : Icons.cancel,
                        color: isSocketConnected ? Colors.green : Colors.red,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isSocketConnected ? 'Connected to Node.js server' : 'Not connected to Node.js server',
                        style: TextStyle(
                          color: isSocketConnected ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ];
              if (_socketErrorMessage != null) {
                items.add(
                  PopupMenuItem<String>(
                    value: 'error',
                    child: SizedBox(
                      width: 250,
                      child: Text(
                        _socketErrorMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ),
                );
              }
              return items;
            },
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'test':
                  _testCall();
                  break;
                case 'reconnect':
                  _reconnectSocket();
                  break;
                case 'logout':
                  _logout();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'test',
                child: Row(
                  children: [
                    Icon(Icons.bug_report),
                    SizedBox(width: 8),
                    Text('Test Call'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'reconnect',
                child: Row(
                  children: [
                    Icon(Icons.refresh),
                    SizedBox(width: 8),
                    Text('Reconnect'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'logout0',
                child: Row(
                  children: [
                    Icon(Icons.logout),
                    SizedBox(width: 8),
                    Text('Logout0'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.person, size: 24),
                        const SizedBox(width: 8),
                        Text(
                          userName != null ? 'Welcome, $userName!' : 'Loading...',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Vamera 1',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Status section
            Card(
              color: _getStatusCardColor(),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _getStatusIcon(),
                          color: _getStatusIconColor(),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Status',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      callStatus,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Recent calls section
            const Text(
              'Recent Calls',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            
            Expanded(
              child: Card(
                child: recentCalls.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.call, size: 48, color: Colors.grey),
                            SizedBox(height: 8),
                            Text(
                              'No recent calls',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: recentCalls.length,
                        itemBuilder: (context, index) {
                          final call = recentCalls[index];
                          final isAccepted = call.contains('Accepted');
                          
                          return ListTile(
                            leading: Icon(
                              isAccepted ? Icons.call_received : Icons.call_end,
                              color: isAccepted ? Colors.green : Colors.red,
                            ),
                            title: Text(
                              call,
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, size: 16),
                              onPressed: () {
                                setState(() {
                                  recentCalls.removeAt(index);
                                });
                                var box = Hive.box('authBox');
                                box.put('recent_calls', recentCalls);
                              },
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _startVideoCall(cameraCode),
        backgroundColor: const Color.fromARGB(255, 70, 46, 37),
        foregroundColor: Colors.white,
        child: const Icon(Icons.video_call),
      ),
    );
  }

  Color _getStatusCardColor() {
    if (isSocketConnected && isCameraAvailable) {
      return Colors.green.shade50;
    } else if (isSocketConnected) {
      return Colors.yellow.shade50;
    } else {
      return Colors.red.shade50;
    }
  }

  IconData _getStatusIcon() {
    if (isSocketConnected && isCameraAvailable) {
      return Icons.check_circle;
    } else if (isSocketConnected) {
      return Icons.warning;
    } else {
      return Icons.error;
    }
  }

  Color _getStatusIconColor() {
    if (isSocketConnected && isCameraAvailable) {
      return Colors.green;
    } else if (isSocketConnected) {
      return Colors.orange;
    } else {
      return Colors.red;
    }
  }
}

