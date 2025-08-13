import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:bellui/services/api_service.dart';
import 'package:bellui/models/models.dart';
import 'package:bellui/utils/utils.dart';
import 'package:bellui/pages/login_register_page.dart';
import 'package:bellui/pages/account_settings_page.dart';

/// Settings Page
/// 
/// This page provides access to various app settings and user account options.
/// Features include:
/// - Logout functionality
/// - Account Settings navigation
/// - App Settings (placeholder)
/// - Other settings (placeholder)
/// 
/// The page follows the same design pattern as other detail pages in the app.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  
  // Loading state
  bool _isLoading = false;
  
  // API service instance
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
  }

  /**
   * Show Logout Confirmation Dialog
   * 
   * Shows a confirmation dialog before logging out the user.
   */
  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _logout();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );
  }

  /**
   * Logout User
   * 
   * Logs out the user and navigates to the login page.
   */
  Future<void> _logout() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await _apiService.logout();
      
      if (mounted) {
        // Navigate to login page and clear navigation stack
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginRegisterPage()),
          (Route<dynamic> route) => false,
        );
      }
    } catch (e) {
      debugPrint('Error during logout: $e');
      UIUtils.showSnackBar(
        context,
        'Error during logout: $e',
        backgroundColor: Colors.red,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /**
   * Navigate to Account Settings
   * 
   * Navigates to the account settings page after fetching user data from API.
   */
  Future<void> _navigateToAccountSettings() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Get user email from Hive
      final box = Hive.box('authBox');
      final userData = box.get('user');
      
      if (userData != null && userData['email'] != null) {
        final email = userData['email'] as String;
        
        // Fetch user info from API
        final response = await _apiService.getUserInfo(email);
        
        if (response.success) {
          final user = response.data as User;
          
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => AccountSettingsPage(user: user),
              ),
            );
          }
        } else {
          throw Exception(response.error);
        }
      } else {
        throw Exception('User email not found in local storage');
      }
    } catch (e) {
      debugPrint('Error navigating to account settings: $e');
      UIUtils.showSnackBar(
        context,
        'Error loading user data: $e',
        backgroundColor: Colors.red,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /**
   * Show Coming Soon Dialog
   * 
   * Shows a dialog indicating that the feature is coming soon.
   */
  void _showComingSoonDialog(String feature) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(feature),
          content: const Text('This feature will be added in the future.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: _buildBody(),
    );
  }

  /// Build App Bar
  /// 
  /// Creates the app bar with settings title.
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Text('Settings'),
      backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
      foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
    );
  }

  /// Build Body
  /// 
  /// Creates the main content area with settings options.
  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSettingsOptionsCard(),
          const SizedBox(height: 16),
          _buildLogoutCard(),
        ],
      ),
    );
  }

  /// Build Settings Options Card
  /// 
  /// Creates a card with the three main settings options.
  Widget _buildSettingsOptionsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.settings, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  'Settings Options',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Account Settings
            _buildSettingsOption(
              icon: Icons.account_circle,
              title: 'Account Settings',
              subtitle: 'Manage your account information and preferences',
              onTap: _navigateToAccountSettings,
            ),
            
            const Divider(),
            
            // App Settings
            _buildSettingsOption(
              icon: Icons.app_settings_alt,
              title: 'App Settings',
              subtitle: 'Configure app preferences and notifications',
              onTap: () => _showComingSoonDialog('App Settings'),
            ),
            
            const Divider(),
            
            // Other Settings
            _buildSettingsOption(
              icon: Icons.more_horiz,
              title: 'Other',
              subtitle: 'Additional settings and options',
              onTap: () => _showComingSoonDialog('Other Settings'),
            ),
          ],
        ),
      ),
    );
  }

  /// Build Settings Option
  /// 
  /// Creates a settings option list item.
  Widget _buildSettingsOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.blue),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
    );
  }

  /// Build Logout Card
  /// 
  /// Creates a card with the logout button.
  Widget _buildLogoutCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.logout, color: Colors.red),
                const SizedBox(width: 8),
                const Text(
                  'Account Actions',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Logout button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _showLogoutDialog,
                icon: const Icon(Icons.logout),
                label: const Text('Logout'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
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
}

