/**
 * Utility Functions and Helper Classes
 * 
 * This file contains utility functions and helper classes used throughout
 * the camera/home management application:
 * 
 * - Date and time formatting utilities
 * - Validation functions for user input
 * - String manipulation and formatting
 * - Color and theme utilities
 * - Network and connectivity helpers
 * - File and storage utilities
 * - Encryption and security helpers
 * - UI and widget utilities
 * - Constants and configuration
 * 
 * All utilities are well-documented and include usage examples.
 */

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';
import 'package:intl/intl.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:permission_handler/permission_handler.dart';

// ==================== DATE AND TIME UTILITIES ====================

/**
 * Date Time Utilities
 * 
 * Provides comprehensive date and time formatting and manipulation functions.
 */
class DateTimeUtils {
  
  /**
   * Format timestamp for display
   * 
   * Converts a DateTime to a human-readable relative time string.
   * Examples: "Just now", "5m ago", "2h ago", "3d ago", "12/25/2023"
   */
  static String formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return '${weeks}w ago';
    } else {
      return DateFormat('MM/dd/yyyy').format(dateTime);
    }
  }
  
  /**
   * Format timestamp for detailed display
   * 
   * Returns a detailed timestamp string with date and time.
   * Example: "Dec 25, 2023 at 3:45 PM"
   */
  static String formatDetailedTime(DateTime dateTime) {
    return DateFormat('MMM dd, yyyy \'at\' h:mm a').format(dateTime);
  }
  
  /**
   * Format time only
   * 
   * Returns just the time portion in 12-hour format.
   * Example: "3:45 PM"
   */
  static String formatTimeOnly(DateTime dateTime) {
    return DateFormat('h:mm a').format(dateTime);
  }
  
  /**
   * Format date only
   * 
   * Returns just the date portion in a readable format.
   * Example: "December 25, 2023"
   */
  static String formatDateOnly(DateTime dateTime) {
    return DateFormat('MMMM dd, yyyy').format(dateTime);
  }
  
  /**
   * Format duration
   * 
   * Converts a Duration to a human-readable string.
   * Examples: "2h 30m", "45m 20s", "1d 5h"
   */
  static String formatDuration(Duration duration) {
    if (duration.inDays > 0) {
      final hours = duration.inHours % 24;
      return '${duration.inDays}d ${hours}h';
    } else if (duration.inHours > 0) {
      final minutes = duration.inMinutes % 60;
      return '${duration.inHours}h ${minutes}m';
    } else if (duration.inMinutes > 0) {
      final seconds = duration.inSeconds % 60;
      return '${duration.inMinutes}m ${seconds}s';
    } else {
      return '${duration.inSeconds}s';
    }
  }
  
  /**
   * Check if date is today
   * 
   * Returns true if the given date is today.
   */
  static bool isToday(DateTime dateTime) {
    final now = DateTime.now();
    return dateTime.year == now.year &&
           dateTime.month == now.month &&
           dateTime.day == now.day;
  }
  
  /**
   * Check if date is yesterday
   * 
   * Returns true if the given date is yesterday.
   */
  static bool isYesterday(DateTime dateTime) {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    return dateTime.year == yesterday.year &&
           dateTime.month == yesterday.month &&
           dateTime.day == yesterday.day;
  }
  
  /**
   * Get start of day
   * 
   * Returns a DateTime representing the start of the given day (00:00:00).
   */
  static DateTime startOfDay(DateTime dateTime) {
    return DateTime(dateTime.year, dateTime.month, dateTime.day);
  }
  
  /**
   * Get end of day
   * 
   * Returns a DateTime representing the end of the given day (23:59:59).
   */
  static DateTime endOfDay(DateTime dateTime) {
    return DateTime(dateTime.year, dateTime.month, dateTime.day, 23, 59, 59);
  }
}

// ==================== VALIDATION UTILITIES ====================

/**
 * Validation Utilities
 * 
 * Provides input validation functions for forms and user data.
 */
class ValidationUtils {
  
  /**
   * Validate email address
   * 
   * Returns null if valid, error message if invalid.
   */
  static String? validateEmail(String? email) {
    if (email == null || email.isEmpty) {
      return 'Email is required';
    }
    
    final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    if (!emailRegex.hasMatch(email)) {
      return 'Please enter a valid email address';
    }
    
    return null;
  }
  
  /**
   * Validate password
   * 
   * Returns null if valid, error message if invalid.
   * Requires at least 8 characters with uppercase, lowercase, and number.
   */
  static String? validatePassword(String? password) {
    if (password == null || password.isEmpty) {
      return 'Password is required';
    }
    
    if (password.length < 8) {
      return 'Password must be at least 8 characters long';
    }
    
    if (!password.contains(RegExp(r'[A-Z]'))) {
      return 'Password must contain at least one uppercase letter';
    }
    
    if (!password.contains(RegExp(r'[a-z]'))) {
      return 'Password must contain at least one lowercase letter';
    }
    
    if (!password.contains(RegExp(r'[0-9]'))) {
      return 'Password must contain at least one number';
    }
    
    return null;
  }
  
  /**
   * Validate phone number
   * 
   * Returns null if valid, error message if invalid.
   * Accepts various phone number formats.
   */
  static String? validatePhone(String? phone) {
    if (phone == null || phone.isEmpty) {
      return null; // Phone is optional
    }
    
    // Remove all non-digit characters
    final digitsOnly = phone.replaceAll(RegExp(r'[^\d]'), '');
    
    if (digitsOnly.length < 10 || digitsOnly.length > 15) {
      return 'Please enter a valid phone number';
    }
    
    return null;
  }
  
  /**
   * Validate required field
   * 
   * Returns null if not empty, error message if empty.
   */
  static String? validateRequired(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }
  
  /**
   * Validate camera code
   * 
   * Returns null if valid, error message if invalid.
   * Camera codes should be alphanumeric and 3-20 characters.
   */
  static String? validateCameraCode(String? code) {
    if (code == null || code.isEmpty) {
      return 'Camera code is required';
    }
    
    if (code.length < 3 || code.length > 20) {
      return 'Camera code must be 3-20 characters long';
    }
    
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(code)) {
      return 'Camera code can only contain letters, numbers, hyphens, and underscores';
    }
    
    return null;
  }
  
  /**
   * Validate coordinates
   * 
   * Returns null if valid, error message if invalid.
   */
  static String? validateLatitude(String? latitude) {
    if (latitude == null || latitude.isEmpty) {
      return null; // Optional field
    }
    
    final lat = double.tryParse(latitude);
    if (lat == null) {
      return 'Please enter a valid latitude';
    }
    
    if (lat < -90 || lat > 90) {
      return 'Latitude must be between -90 and 90';
    }
    
    return null;
  }
  
  static String? validateLongitude(String? longitude) {
    if (longitude == null || longitude.isEmpty) {
      return null; // Optional field
    }
    
    final lng = double.tryParse(longitude);
    if (lng == null) {
      return 'Please enter a valid longitude';
    }
    
    if (lng < -180 || lng > 180) {
      return 'Longitude must be between -180 and 180';
    }
    
    return null;
  }
}

// ==================== STRING UTILITIES ====================

/**
 * String Utilities
 * 
 * Provides string manipulation and formatting functions.
 */
class StringUtils {
  
  /**
   * Capitalize first letter
   * 
   * Capitalizes the first letter of a string.
   * Example: "hello world" -> "Hello world"
   */
  static String capitalize(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }
  
  /**
   * Title case
   * 
   * Capitalizes the first letter of each word.
   * Example: "hello world" -> "Hello World"
   */
  static String titleCase(String text) {
    if (text.isEmpty) return text;
    return text.split(' ').map((word) => capitalize(word)).join(' ');
  }
  
  /**
   * Truncate text
   * 
   * Truncates text to a maximum length and adds ellipsis if needed.
   * Example: truncate("Hello World", 8) -> "Hello..."
   */
  static String truncate(String text, int maxLength, {String suffix = '...'}) {
    if (text.length <= maxLength) return text;
    return text.substring(0, maxLength - suffix.length) + suffix;
  }
  
  /**
   * Generate random string
   * 
   * Generates a random alphanumeric string of specified length.
   */
  static String generateRandomString(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return String.fromCharCodes(
      Iterable.generate(length, (_) => chars.codeUnitAt(random.nextInt(chars.length)))
    );
  }
  
  /**
   * Format file size
   * 
   * Converts bytes to human-readable file size.
   * Example: formatFileSize(1024) -> "1.0 KB"
   */
  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  
  /**
   * Remove special characters
   * 
   * Removes special characters from a string, keeping only alphanumeric and spaces.
   */
  static String removeSpecialCharacters(String text) {
    return text.replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), '');
  }
  
  /**
   * Generate initials
   * 
   * Generates initials from a full name.
   * Example: "John Doe" -> "JD"
   */
  static String generateInitials(String name) {
    if (name.isEmpty) return '?';
    
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }
  
  /**
   * Mask sensitive data
   * 
   * Masks sensitive information like email or phone numbers.
   * Example: maskEmail("john@example.com") -> "j***@example.com"
   */
  static String maskEmail(String email) {
    if (email.isEmpty) return email;
    
    final parts = email.split('@');
    if (parts.length != 2) return email;
    
    final username = parts[0];
    final domain = parts[1];
    
    if (username.length <= 2) return email;
    
    final maskedUsername = username[0] + '*' * (username.length - 2) + username[username.length - 1];
    return '$maskedUsername@$domain';
  }
  
  static String maskPhone(String phone) {
    if (phone.length < 4) return phone;
    
    final visibleDigits = 2;
    final maskedPart = '*' * (phone.length - visibleDigits * 2);
    return phone.substring(0, visibleDigits) + maskedPart + phone.substring(phone.length - visibleDigits);
  }
}

// ==================== COLOR AND THEME UTILITIES ====================

/**
 * Color Utilities
 * 
 * Provides color manipulation and theme-related functions.
 */
class ColorUtils {
  
  /**
   * Get status color
   * 
   * Returns appropriate color for different status types.
   */
  static Color getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'online':
      case 'active':
      case 'connected':
      case 'excellent':
        return Colors.green;
      case 'offline':
      case 'inactive':
      case 'disconnected':
      case 'critical':
        return Colors.red;
      case 'warning':
      case 'degraded':
        return Colors.orange;
      case 'recording':
        return Colors.red;
      case 'streaming':
        return Colors.blue;
      case 'idle':
      case 'standby':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }
  
  /**
   * Get severity color
   * 
   * Returns color based on severity level.
   */
  static Color getSeverityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return Colors.red[800]!;
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.orange;
      case 'low':
        return Colors.yellow[700]!;
      case 'info':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }
  
  /**
   * Lighten color
   * 
   * Makes a color lighter by the specified amount (0.0 to 1.0).
   */
  static Color lighten(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    final lightness = (hsl.lightness + amount).clamp(0.0, 1.0);
    return hsl.withLightness(lightness).toColor();
  }
  
  /**
   * Darken color
   * 
   * Makes a color darker by the specified amount (0.0 to 1.0).
   */
  static Color darken(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    final lightness = (hsl.lightness - amount).clamp(0.0, 1.0);
    return hsl.withLightness(lightness).toColor();
  }
  
  /**
   * Get contrasting text color
   * 
   * Returns white or black text color based on background brightness.
   */
  static Color getContrastingTextColor(Color backgroundColor) {
    final luminance = backgroundColor.computeLuminance();
    return luminance > 0.5 ? Colors.black : Colors.white;
  }
  
  /**
   * Generate color from string
   * 
   * Generates a consistent color based on a string (useful for avatars).
   */
  static Color generateColorFromString(String text) {
    final hash = text.hashCode;
    final hue = (hash % 360).toDouble();
    return HSLColor.fromAHSL(1.0, hue, 0.7, 0.6).toColor();
  }
}

// ==================== NETWORK UTILITIES ====================

/**
 * Network Utilities
 * 
 * Provides network connectivity and status checking functions.
 */
class NetworkUtils {
  
  /**
   * Check internet connectivity
   * 
   * Returns true if device has internet connection.
   */
  static Future<bool> hasInternetConnection() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        return false;
      }
      
      // Additional check by trying to reach a reliable server
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (e) {
      return false;
    }
  }
  
  /**
   * Get connection type
   * 
   * Returns the type of network connection (wifi, mobile, none).
   */
  static Future<String> getConnectionType() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    switch (connectivityResult) {
      case ConnectivityResult.wifi:
        return 'wifi';
      case ConnectivityResult.mobile:
        return 'mobile';
      case ConnectivityResult.ethernet:
        return 'ethernet';
      case ConnectivityResult.none:
        return 'none';
      default:
        return 'unknown';
    }
  }
  
  /**
   * Format URL
   * 
   * Ensures URL has proper protocol prefix.
   */
  static String formatUrl(String url) {
    if (url.isEmpty) return url;
    
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return 'https://$url';
    }
    
    return url;
  }
  
  /**
   * Extract domain from URL
   * 
   * Extracts the domain name from a URL.
   * Example: "https://api.example.com/path" -> "api.example.com"
   */
  static String extractDomain(String url) {
    try {
      final uri = Uri.parse(formatUrl(url));
      return uri.host;
    } catch (e) {
      return url;
    }
  }
}

// ==================== SECURITY UTILITIES ====================

/**
 * Security Utilities
 * 
 * Provides encryption, hashing, and security-related functions.
 */
class SecurityUtils {
  
  /**
   * Hash password
   * 
   * Creates a secure hash of a password using SHA-256.
   */
  static String hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
  
  /**
   * Generate secure token
   * 
   * Generates a cryptographically secure random token.
   */
  static String generateSecureToken(int length) {
    final random = Random.secure();
    final bytes = List<int>.generate(length, (_) => random.nextInt(256));
    return base64Url.encode(bytes).substring(0, length);
  }
  
  /**
   * Validate token format
   * 
   * Validates if a token has the expected format.
   */
  static bool isValidTokenFormat(String token) {
    if (token.isEmpty) return false;
    
    // Check if token is base64url encoded and has reasonable length
    try {
      base64Url.decode(token);
      return token.length >= 16 && token.length <= 128;
    } catch (e) {
      return false;
    }
  }
  
  /**
   * Sanitize input
   * 
   * Removes potentially dangerous characters from user input.
   */
  static String sanitizeInput(String input) {
    return input
        .replaceAll(RegExp(r'[<>"\\]'), '')
        .replaceAll(RegExp(r'[&]'), '&amp;')
        .trim();
  }
  
  /**
   * Check password strength
   * 
   * Returns password strength score (0-4) and feedback.
   */
  static Map<String, dynamic> checkPasswordStrength(String password) {
    int score = 0;
    List<String> feedback = [];
    
    if (password.length >= 8) {
      score++;
    } else {
      feedback.add('Use at least 8 characters');
    }
    
    if (password.contains(RegExp(r'[a-z]'))) {
      score++;
    } else {
      feedback.add('Add lowercase letters');
    }
    
    if (password.contains(RegExp(r'[A-Z]'))) {
      score++;
    } else {
      feedback.add('Add uppercase letters');
    }
    
    if (password.contains(RegExp(r'[0-9]'))) {
      score++;
    } else {
      feedback.add('Add numbers');
    }
    
    if (password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>_]'))) {
      score++;
    } else {
      feedback.add('Add special characters');
    }
    
    String strength;
    switch (score) {
      case 0:
      case 1:
        strength = 'Very Weak';
        break;
      case 2:
        strength = 'Weak';
        break;
      case 3:
        strength = 'Fair';
        break;
      case 4:
        strength = 'Good';
        break;
      case 5:
        strength = 'Strong';
        break;
      default:
        strength = 'Unknown';
    }
    
    return {
      'score': score,
      'strength': strength,
      'feedback': feedback,
    };
  }
}

// ==================== PERMISSION UTILITIES ====================

/**
 * Permission Utilities
 * 
 * Provides functions for handling app permissions.
 */
class PermissionUtils {
  
  /**
   * Request camera permission
   * 
   * Requests camera permission and returns the result.
   */
  static Future<bool> requestCameraPermission() async {
    final status = await Permission.camera.request();
    return status == PermissionStatus.granted;
  }
  
  /**
   * Request microphone permission
   * 
   * Requests microphone permission and returns the result.
   */
  static Future<bool> requestMicrophonePermission() async {
    final status = await Permission.microphone.request();
    return status == PermissionStatus.granted;
  }
  
  /**
   * Request location permission
   * 
   * Requests location permission and returns the result.
   */
  static Future<bool> requestLocationPermission() async {
    final status = await Permission.location.request();
    return status == PermissionStatus.granted;
  }
  
  /**
   * Request notification permission
   * 
   * Requests notification permission and returns the result.
   */
  static Future<bool> requestNotificationPermission() async {
    final status = await Permission.notification.request();
    return status == PermissionStatus.granted;
  }
  
  /**
   * Check if permission is granted
   * 
   * Checks if a specific permission is currently granted.
   */
  static Future<bool> isPermissionGranted(Permission permission) async {
    final status = await permission.status;
    return status == PermissionStatus.granted;
  }
  
  /**
   * Open app settings
   * 
   * Opens the app settings page where user can manually grant permissions.
   */
  static Future<bool> openAppSettings() async {
    return await openAppSettings();
  }
}

// ==================== UI UTILITIES ====================

/**
 * UI Utilities
 * 
 * Provides UI-related helper functions and widgets.
 */
class UIUtils {
  
  /**
   * Show snack bar
   * 
   * Shows a snack bar with the specified message and color.
   */
  static void showSnackBar(
    BuildContext context,
    String message, {
    Color? backgroundColor,
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        duration: duration,
        action: action,
      ),
    );
  }
  
  /**
   * Show loading dialog
   * 
   * Shows a loading dialog with optional message.
   */
  static void showLoadingDialog(
    BuildContext context, {
    String message = 'Loading...',
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Text(message),
          ],
        ),
      ),
    );
  }
  
  /**
   * Hide loading dialog
   * 
   * Hides the currently displayed loading dialog.
   */
  static void hideLoadingDialog(BuildContext context) {
    Navigator.of(context).pop();
  }
  
  /**
   * Show confirmation dialog
   * 
   * Shows a confirmation dialog and returns the user's choice.
   */
  static Future<bool> showConfirmationDialog(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = 'Confirm',
    String cancelText = 'Cancel',
    Color? confirmColor,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(cancelText),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: confirmColor != null
                ? ElevatedButton.styleFrom(backgroundColor: confirmColor)
                : null,
            child: Text(confirmText),
          ),
        ],
      ),
    );
    
    return result ?? false;
  }
  
  /**
   * Get screen size
   * 
   * Returns the screen size as a Size object.
   */
  static Size getScreenSize(BuildContext context) {
    return MediaQuery.of(context).size;
  }
  
  /**
   * Check if device is tablet
   * 
   * Returns true if the device is likely a tablet based on screen size.
   */
  static bool isTablet(BuildContext context) {
    final size = getScreenSize(context);
    return size.shortestSide >= 600;
  }
  
  /**
   * Get safe area padding
   * 
   * Returns the safe area padding for the current device.
   */
  static EdgeInsets getSafeAreaPadding(BuildContext context) {
    return MediaQuery.of(context).padding;
  }

  /// Format a timestamp for display (used in camera/home detail pages)
  static String formatTimestamp(DateTime dateTime) {
    return DateTimeUtils.formatRelativeTime(dateTime);
  }
}

// ==================== CONSTANTS ====================

/**
 * App Constants
 * 
 * Contains application-wide constants and configuration values.
 */
class AppConstants {
  
  // API Configuration
  static const String apiBaseUrl = 'https://your-api-server.com/api';
  static const String socketUrl = 'https://your-socket-server.com';
  static const Duration apiTimeout = Duration(seconds: 30);
  static const int maxRetries = 3;
  
  // UI Constants
  static const double defaultPadding = 16.0;
  static const double smallPadding = 8.0;
  static const double largePadding = 24.0;
  static const double borderRadius = 8.0;
  static const double cardElevation = 2.0;
  
  // Animation Durations
  static const Duration shortAnimation = Duration(milliseconds: 200);
  static const Duration mediumAnimation = Duration(milliseconds: 400);
  static const Duration longAnimation = Duration(milliseconds: 600);
  
  // Validation Constants
  static const int minPasswordLength = 8;
  static const int maxPasswordLength = 128;
  static const int minCameraCodeLength = 3;
  static const int maxCameraCodeLength = 20;
  
  // Storage Keys
  static const String authTokenKey = 'auth_token';
  static const String userDataKey = 'user_data';
  static const String settingsKey = 'app_settings';
  static const String cacheKey = 'api_cache';
  
  // Default Values
  static const String defaultTheme = 'system';
  static const String defaultLanguage = 'en';
  static const int defaultCacheTimeout = 300; // 5 minutes in seconds
  
  // Camera Settings
  static const double defaultMotionSensitivity = 0.5;
  static const int recordingQuality = 3;
  static const List<String> supportedVideoFormats = ['mp4', 'avi', 'mov'];
  static const List<String> supportedImageFormats = ['jpg', 'jpeg', 'png'];
  
  // Security Settings
  static const int tokenLength = 32;
  static const Duration sessionTimeout = Duration(hours: 24);
  static const int maxLoginAttempts = 5;
  static const Duration lockoutDuration = Duration(minutes: 15);
}

/**
 * App Colors
 * 
 * Contains the application color scheme and theme colors.
 */
class AppColors {
  
  // Primary Colors
  static const Color primary = Color(0xFF462E25); // Brown from original design
  static const Color primaryLight = Color(0xFF6D4C41);
  static const Color primaryDark = Color(0xFF3E2723);
  
  // Secondary Colors
  static const Color secondary = Color(0xFF2196F3); // Blue
  static const Color secondaryLight = Color(0xFF64B5F6);
  static const Color secondaryDark = Color(0xFF1976D2);
  
  // Status Colors
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFF9800);
  static const Color error = Color(0xFFF44336);
  static const Color info = Color(0xFF2196F3);
  
  // Neutral Colors
  static const Color background = Color(0xFFFAFAFA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color onBackground = Color(0xFF212121);
  static const Color onSurface = Color(0xFF757575);
  
  // Camera Status Colors
  static const Color online = Color(0xFF4CAF50);
  static const Color offline = Color(0xFFF44336);
  static const Color recording = Color(0xFFE53935);
  static const Color streaming = Color(0xFF2196F3);
  static const Color idle = Color(0xFF9E9E9E);
  
  // Severity Colors
  static const Color critical = Color(0xFFD32F2F);
  static const Color high = Color(0xFFF44336);
  static const Color medium = Color(0xFFFF9800);
  static const Color low = Color(0xFFFFC107);
  
  // Gradient Colors
  static const List<Color> primaryGradient = [primary, primaryLight];
  static const List<Color> successGradient = [success, Color(0xFF66BB6A)];
  static const List<Color> warningGradient = [warning, Color(0xFFFFB74D)];
  static const List<Color> errorGradient = [error, Color(0xFFEF5350)];
}

/**
 * App Text Styles
 * 
 * Contains predefined text styles for consistent typography.
 */
class AppTextStyles {
  
  // Headings
  static const TextStyle h1 = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.bold,
    color: AppColors.onBackground,
  );
  
  static const TextStyle h2 = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: AppColors.onBackground,
  );
  
  static const TextStyle h3 = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.onBackground,
  );
  
  static const TextStyle h4 = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.onBackground,
  );
  
  // Body Text
  static const TextStyle bodyLarge = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.normal,
    color: AppColors.onBackground,
  );
  
  static const TextStyle bodyMedium = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.normal,
    color: AppColors.onBackground,
  );
  
  static const TextStyle bodySmall = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.normal,
    color: AppColors.onSurface,
  );
  
  // Special Styles
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.normal,
    color: AppColors.onSurface,
  );
  
  static const TextStyle button = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
  );
  
  static const TextStyle overline = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w500,
    letterSpacing: 1.5,
    color: AppColors.onSurface,
  );
}


