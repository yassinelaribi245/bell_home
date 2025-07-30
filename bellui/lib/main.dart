import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:bellui/pages/login_register_page.dart';
import 'package:bellui/pages/enhanced_main_dashboard.dart';
import 'package:bellui/services/api_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  print('App starting...');

  await Firebase.initializeApp();

  await Hive.initFlutter();
  await Hive.openBox('authBox');

  // Initialize ApiService
  await ApiService().initialize();

  // Check for FCM initial message (when app is launched from notification)
  RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    print('FCM initial message detected! Data: ' + initialMessage.data.toString());
  } else {
    print('No FCM initial message.');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final box = Hive.box('authBox');
    final token = box.get('auth_token');

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'My App',
      theme: ThemeData(primarySwatch: Colors.brown),
      home: token != null ? const EnhancedMainDashboard() : const LoginRegisterPage(),
    );
  }
}


