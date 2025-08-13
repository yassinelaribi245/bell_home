import 'package:flutter/material.dart';
import 'package:bellui/services/api_service.dart';
import 'package:bellui/models/models.dart';
import 'package:bellui/utils/utils.dart';

/// Account Settings Page
/// 
/// This page displays user account information and provides options to manage
/// account settings. The layout follows the same design pattern as camera
/// and home detail pages for consistency.
/// 
/// Features include:
/// - User information display
/// - Change password option (placeholder)
/// - Account management options
/// - Consistent UI design with other detail pages
class AccountSettingsPage extends StatefulWidget {
  final User user;

  const AccountSettingsPage({
    super.key,
    required this.user,
  });

  @override
  State<AccountSettingsPage> createState() => _AccountSettingsPageState();
}

class _AccountSettingsPageState extends State<AccountSettingsPage> {
  
  // User state management
  late User _user;
  bool _isLoading = false;
  
  // API service instance
  final ApiService _apiService = ApiService();

  // Debug logs
  final List<String> _debugLogs = [];

  @override
  void initState() {
    super.initState();
    _user = widget.user;
    _addDebugLog('Account settings page initialized for user ${_user.email}');
  }

  /**
   * Show Change Password Dialog
   * 
   * Shows a dialog indicating that password change will be added in the future.
   */
  void _showChangePasswordDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Change Password'),
          content: const Text('Password change functionality will be added in the future.'),
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

  /**
   * Add Debug Log
   * 
   * Adds a timestamped debug message to the debug log list.
   */
  void _addDebugLog(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    setState(() {
      _debugLogs.insert(0, '[$timestamp] $message');
      if (_debugLogs.length > 100) {
        _debugLogs.removeLast();
      }
    });
    debugPrint(message);
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
  /// Creates the app bar with account settings title.
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Text('Account Settings'),
      backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
      foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
    );
  }

  /// Build Body
  /// 
  /// Creates the main content area with user information and account options.
  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildUserInfoCard(),
          const SizedBox(height: 16),
          _buildAccountActionsCard(),
          const SizedBox(height: 16),
          _buildDebugCard(),
        ],
      ),
    );
  }

  /// Build User Info Card
  /// 
  /// Creates a card with detailed user information similar to camera/home info cards.
  Widget _buildUserInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.person, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  'User Information',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInfoRow('User ID', _user.id.toString()),
            _buildInfoRow('First Name', _user.prenom),
            _buildInfoRow('Last Name', _user.nom),
            _buildInfoRow('Full Name', '${_user.prenom} ${_user.nom}'),
            _buildInfoRow('Email', _user.email),
            _buildInfoRow('Phone', _user.formattedPhone),
            _buildInfoRow('Birth Date', _user.formattedBirthDate),
            if (_user.age != null) _buildInfoRow('Age', '${_user.age} years'),
            _buildInfoRow('City ID', _user.idVille?.toString() ?? 'Not provided'),
            _buildInfoRow('Postal Code', _user.codePostal?.toString() ?? 'Not provided'),
            _buildInfoRow('Role', _user.role),
            _buildInfoRow('Active', _user.isActive ? 'Yes' : 'No'),
            _buildInfoRow('Banned', _user.isBanned ? 'Yes' : 'No'),
            _buildInfoRow('Verified', _user.isVerified ? 'Yes' : 'No'),
            _buildInfoRow('Last Login', _user.lastLoginAt?.toString() ?? 'Never'),
            _buildInfoRow('Created At', _user.createdAt?.toString() ?? 'N/A'),
            _buildInfoRow('Updated At', _user.updatedAt?.toString() ?? 'N/A'),
          ],
        ),
      ),
    );
  }

  /// Build Account Actions Card
  /// 
  /// Creates a card with account management actions.
  Widget _buildAccountActionsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.security, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  'Account Actions',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Change Password button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _showChangePasswordDialog,
                icon: const Icon(Icons.lock),
                label: const Text('Change Password'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 48),
                ),
              ),
            ),
            
            const SizedBox(height: 8),
            
            // Info text
            const Text(
              'Password change functionality will be added in the future.',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// Build Debug Card
  /// 
  /// Creates a card with debug logs for troubleshooting.
  Widget _buildDebugCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bug_report, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  'Debug Log',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
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
            const SizedBox(height: 16),
            Container(
              height: 150,
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: _debugLogs.isEmpty
                  ? const Center(
                      child: Text(
                        'No debug messages',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
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
    );
  }

  /// Build Info Row
  /// 
  /// Creates a row with label and value for displaying information.
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label + ':',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

