/// Data Models for Camera/Home Management System
///
/// This file contains all the data model classes used throughout the application:
/// - User model for authentication and profile management
/// - Home model for property/location management
/// - Camera model for camera device management
/// - Activity and event models for logging and history
/// - Settings and configuration models
///
/// All models include:
/// - JSON serialization/deserialization
/// - Data validation and constraints
/// - Utility methods and computed properties
/// - Immutable data structures with copyWith methods
/// - Comprehensive documentation and examples

// ==================== USER MODEL ====================

/**
 * User Model
 * 
 * Represents a user account with authentication and profile information.
 * Used for login, registration, and user management throughout the app.
 */
class User {
  final int? id;
  final String nom;           // User's full name
  final String email;         // Email address (unique)
  final String? phone;        // Optional phone number
  final String? avatar;       // Profile picture URL
  final DateTime? createdAt;  // Account creation date
  final DateTime? updatedAt;  // Last profile update
  final bool isActive;        // Account status
  final String role;          // User role (admin, user, etc.)
  final Map<String, dynamic>? preferences; // User preferences and settings

  const User({
    this.id,
    required this.nom,
    required this.email,
    this.phone,
    this.avatar,
    this.createdAt,
    this.updatedAt,
    this.isActive = true,
    this.role = 'user',
    this.preferences,
  });

  /**
   * Create User from JSON
   * 
   * Deserializes user data from API response or local storage.
   */
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      nom: json['nom'] ?? json['name'] ?? '',
      email: json['email'] ?? '',
      phone: json['phone'],
      avatar: json['avatar'],
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at']) : null,
      isActive: json['is_active'] ?? true,
      role: json['role'] ?? 'user',
      preferences: json['preferences'] is Map<String, dynamic> 
          ? json['preferences'] 
          : null,
    );
  }

  /**
   * Convert User to JSON
   * 
   * Serializes user data for API requests or local storage.
   */
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nom': nom,
      'email': email,
      'phone': phone,
      'avatar': avatar,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'is_active': isActive,
      'role': role,
      'preferences': preferences,
    };
  }

  /**
   * Create a copy with modified fields
   * 
   * Returns a new User instance with updated values while keeping
   * other fields unchanged. Useful for state management.
   */
  User copyWith({
    int? id,
    String? nom,
    String? email,
    String? phone,
    String? avatar,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isActive,
    String? role,
    Map<String, dynamic>? preferences,
  }) {
    return User(
      id: id ?? this.id,
      nom: nom ?? this.nom,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      avatar: avatar ?? this.avatar,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isActive: isActive ?? this.isActive,
      role: role ?? this.role,
      preferences: preferences ?? this.preferences,
    );
  }

  /**
   * Get display name
   * 
   * Returns the user's display name, falling back to email if name is empty.
   */
  String get displayName => nom.isNotEmpty ? nom : email;

  /**
   * Get initials
   * 
   * Returns user initials for avatar placeholders.
   */
  String get initials {
    if (nom.isEmpty) return email.isNotEmpty ? email[0].toUpperCase() : '?';
    final parts = nom.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return nom[0].toUpperCase();
  }

  /**
   * Check if user is admin
   * 
   * Returns true if the user has admin privileges.
   */
  bool get isAdmin => role == 'admin' || role == 'super_admin';

  @override
  String toString() => 'User(id: $id, nom: $nom, email: $email)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is User && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

// ==================== HOME MODEL ====================

/**
 * Home Model
 * 
 * Represents a home/property with associated cameras and security settings.
 * Each home can have multiple cameras and its own security configuration.
 */
class Home {
  final int? id;
  final String name;              // Home name/identifier
  final String address;           // Full address
  final double superficie;        // Surface area in square meters
  final double? longitude;        // GPS longitude
  final double? latitude;         // GPS latitude
  final int numCameras;          // Number of cameras (from num_cam field)
  final int idUser;              // Owner user ID (from id_user field)
  final DateTime? createdAt;     // Creation timestamp
  final DateTime? updatedAt;     // Last update timestamp
  final bool isActive;           // Home status
  final String status;           // Current status (active, inactive, maintenance)
  final Map<String, dynamic>? settings; // Home-specific settings
  final List<Camera>? cameras;   // Associated cameras (optional, loaded separately)

  const Home({
    this.id,
    required this.name,
    required this.address,
    required this.superficie,
    this.longitude,
    this.latitude,
    required this.numCameras,
    required this.idUser,
    this.createdAt,
    this.updatedAt,
    this.isActive = true,
    this.status = 'active',
    this.settings,
    this.cameras,
  });

  /**
   * Create Home from JSON
   * 
   * Deserializes home data from API response.
   */
  factory Home.fromJson(Map<String, dynamic> json) {
    return Home(
      id: json['id'],
      name: json['name'] ?? 'Unnamed Home',
      address: json['address'] ?? '',
      superficie: (json['superficie'] ?? 0).toDouble(),
      longitude: json['longitude']?.toDouble(),
      latitude: json['latitude']?.toDouble(),
      numCameras: json['num_cam'] ?? json['num_cameras'] ?? 0,
      idUser: json['id_user'] ?? json['user_id'] ?? 0,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at']) : null,
      isActive: json['is_active'] ?? true,
      status: json['status'] ?? 'active',
      settings: json['settings'] is Map<String, dynamic> 
          ? json['settings'] 
          : null,
      cameras: json['cameras'] != null 
          ? (json['cameras'] as List).map((c) => Camera.fromJson(c)).toList()
          : null,
    );
  }

  /**
   * Convert Home to JSON
   * 
   * Serializes home data for API requests.
   */
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'address': address,
      'superficie': superficie,
      'longitude': longitude,
      'latitude': latitude,
      'num_cam': numCameras,
      'id_user': idUser,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'is_active': isActive,
      'status': status,
      'settings': settings,
      if (cameras != null) 'cameras': cameras!.map((c) => c.toJson()).toList(),
    };
  }

  /**
   * Create a copy with modified fields
   */
  Home copyWith({
    int? id,
    String? name,
    String? address,
    double? superficie,
    double? longitude,
    double? latitude,
    int? numCameras,
    int? idUser,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isActive,
    String? status,
    Map<String, dynamic>? settings,
    List<Camera>? cameras,
  }) {
    return Home(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      superficie: superficie ?? this.superficie,
      longitude: longitude ?? this.longitude,
      latitude: latitude ?? this.latitude,
      numCameras: numCameras ?? this.numCameras,
      idUser: idUser ?? this.idUser,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isActive: isActive ?? this.isActive,
      status: status ?? this.status,
      settings: settings ?? this.settings,
      cameras: cameras ?? this.cameras,
    );
  }

  /**
   * Get online cameras count
   * 
   * Returns the number of cameras that are currently online.
   */
  int get onlineCamerasCount {
    if (cameras == null) return 0;
    return cameras!.where((camera) => camera.isOnline).length;
  }

  /**
   * Get recording cameras count
   * 
   * Returns the number of cameras that are currently recording.
   */
  int get recordingCamerasCount {
    if (cameras == null) return 0;
    return cameras!.where((camera) => camera.isRecording).length;
  }

  /**
   * Check if home has location data
   * 
   * Returns true if the home has valid GPS coordinates.
   */
  bool get hasLocation => longitude != null && latitude != null;

  /**
   * Get formatted address
   * 
   * Returns a formatted address string for display.
   */
  String get formattedAddress {
    if (address.isEmpty) return 'No address provided';
    return address;
  }

  /**
   * Get surface area formatted
   * 
   * Returns formatted surface area with units.
   */
  String get formattedSurface => '${superficie.toStringAsFixed(1)} m²';

  @override
  String toString() => 'Home(id: $id, name: $name, cameras: $numCameras)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Home && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

// ==================== CAMERA MODEL ====================

/**
 * Camera Model
 * 
 * Represents a security camera with its status, settings, and capabilities.
 * Each camera belongs to a home and has real-time status information.
 */
class Camera {
  final int? id;
  final String name;                    // Camera display name
  final String camCode;                 // Unique camera code/identifier
  final DateTime? dateCreation;         // Installation/creation date
  final bool isActive;                  // Camera enabled status
  final bool isOnline;                  // Current connectivity status
  final bool isRecording;               // Current recording status
  final bool isStreaming;               // Current streaming status
  final double? longitude;              // GPS longitude
  final double? latitude;               // GPS latitude
  final int homeId;                     // Associated home ID (from id_home field)
  final String homeName;                // Associated home name (for display)
  final DateTime? createdAt;            // Database creation timestamp
  final DateTime? updatedAt;            // Last update timestamp
  final String locationDescription;     // Human-readable location
  final String healthStatus;            // Camera health (excellent, good, warning, critical, offline)
  final Map<String, dynamic>? settings; // Camera-specific settings
  final List<String>? capabilities;     // Camera capabilities (night_vision, motion_detection, etc.)

  const Camera({
    this.id,
    required this.name,
    required this.camCode,
    this.dateCreation,
    this.isActive = true,
    this.isOnline = false,
    this.isRecording = false,
    this.isStreaming = false,
    this.longitude,
    this.latitude,
    required this.homeId,
    required this.homeName,
    this.createdAt,
    this.updatedAt,
    this.locationDescription = '',
    this.healthStatus = 'offline',
    this.settings,
    this.capabilities,
  });

  /**
   * Create Camera from JSON
   * 
   * Deserializes camera data from API response.
   */
  factory Camera.fromJson(Map<String, dynamic> json) {
    bool parseBool(dynamic value) {
      if (value is bool) return value;
      if (value is int) return value == 1;
      if (value is String) return value == '1' || value.toLowerCase() == 'true';
      return false;
    }
    return Camera(
      id: json['id'],
      name: (json['name'] ?? 'Camera').toString(),
      camCode: (json['cam_code'] ?? '').toString(),
      dateCreation: json['date_creation'] != null ? DateTime.tryParse(json['date_creation']) : null,
      isActive: parseBool(json['is_active']),
      isOnline: parseBool(json['is_online']),
      isRecording: parseBool(json['is_recording']),
      isStreaming: parseBool(json['is_streaming']),
      longitude: (json['longitude'] as num?)?.toDouble(),
      latitude: (json['latitude'] as num?)?.toDouble(),
      homeId: json['id_home'] ?? 0,
      homeName: (json['home_name'] ?? '').toString(),
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at']) : null,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at']) : null,
      locationDescription: (json['location_description'] ?? '').toString(),
      healthStatus: (json['health_status'] ?? 'offline').toString(),
      settings: json['settings'],
      capabilities: (json['capabilities'] as List?)?.map((e) => e.toString()).toList(),
    );
  }

  /**
   * Convert Camera to JSON
   * 
   * Serializes camera data for API requests.
   */
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'cam_code': camCode,
      'date_creation': dateCreation?.toIso8601String(),
      'is_active': isActive,
      'is_online': isOnline,
      'is_recording': isRecording,
      'is_streaming': isStreaming,
      'longitude': longitude,
      'latitude': latitude,
      'id_home': homeId,
      'home_name': homeName,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'location_description': locationDescription,
      'health_status': healthStatus,
      'settings': settings,
      'capabilities': capabilities,
    };
  }

  /**
   * Create a copy with modified fields
   */
  Camera copyWith({
    int? id,
    String? name,
    String? camCode,
    DateTime? dateCreation,
    bool? isActive,
    bool? isOnline,
    bool? isRecording,
    bool? isStreaming,
    double? longitude,
    double? latitude,
    int? homeId,
    String? homeName,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? locationDescription,
    String? healthStatus,
    Map<String, dynamic>? settings,
    List<String>? capabilities,
  }) {
    return Camera(
      id: id ?? this.id,
      name: name ?? this.name,
      camCode: camCode ?? this.camCode,
      dateCreation: dateCreation ?? this.dateCreation,
      isActive: isActive ?? this.isActive,
      isOnline: isOnline ?? this.isOnline,
      isRecording: isRecording ?? this.isRecording,
      isStreaming: isStreaming ?? this.isStreaming,
      longitude: longitude ?? this.longitude,
      latitude: latitude ?? this.latitude,
      homeId: homeId ?? this.homeId,
      homeName: homeName ?? this.homeName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      locationDescription: locationDescription ?? this.locationDescription,
      healthStatus: healthStatus ?? this.healthStatus,
      settings: settings ?? this.settings,
      capabilities: capabilities ?? this.capabilities,
    );
  }

  /**
   * Create empty Camera instance
   * 
   * Returns an empty camera instance for error handling.
   */
  factory Camera.empty() {
    return const Camera(
      name: 'Unknown Camera',
      camCode: 'unknown',
      homeId: 0,
      homeName: 'Unknown Home',
    );
  }

  /**
   * Check if camera has location data
   * 
   * Returns true if the camera has valid GPS coordinates.
   */
  bool get hasLocation => longitude != null && latitude != null;

  /**
   * Get status color
   * 
   * Returns appropriate color for camera status display.
   */
  String get statusColor {
    if (!isOnline) return 'red';
    if (isRecording) return 'red';
    if (isStreaming) return 'blue';
    return 'green';
  }

  /**
   * Get status text
   * 
   * Returns human-readable status text.
   */
  String get statusText {
    if (!isOnline) return 'Offline';
    if (isRecording) return 'Recording';
    if (isStreaming) return 'Streaming';
    return 'Online';
  }

  /**
   * Check if camera supports capability
   * 
   * Returns true if the camera supports the specified capability.
   */
  bool hasCapability(String capability) {
    return capabilities?.contains(capability) ?? false;
  }

  /**
   * Get formatted installation date
   * 
   * Returns formatted installation date for display.
   */
  String get formattedInstallDate {
    if (dateCreation == null) return 'Unknown';
    return '${dateCreation!.day}/${dateCreation!.month}/${dateCreation!.year}';
  }

  @override
  String toString() => 'Camera(id: $id, name: $name, code: $camCode, online: $isOnline)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Camera && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

// ==================== ACTIVITY MODELS ====================

/**
 * Base Activity Model
 * 
 * Base class for all activity and event logging.
 */
abstract class BaseActivity {
  final int id;
  final String type;
  final String description;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;

  const BaseActivity({
    required this.id,
    required this.type,
    required this.description,
    required this.timestamp,
    this.metadata,
  });

  /**
   * Get formatted timestamp
   * 
   * Returns human-readable timestamp for display.
   */
  String get formattedTimestamp {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    
    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    }
  }
}

/**
 * Camera Activity Model
 * 
 * Represents activities and events related to specific cameras.
 */
class CameraActivity extends BaseActivity {
  final String? cameraCode;
  final String? cameraName;

  const CameraActivity({
    required super.id,
    required super.type,
    required super.description,
    required super.timestamp,
    super.metadata,
    this.cameraCode,
    this.cameraName,
  });

  factory CameraActivity.fromJson(Map<String, dynamic> json) {
    return CameraActivity(
      id: json['id'],
      type: json['type'] ?? 'unknown',
      description: json['description'] ?? 'Unknown activity',
      timestamp: DateTime.parse(json['timestamp']),
      metadata: json['metadata'],
      cameraCode: json['camera_code'],
      cameraName: json['camera_name'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'description': description,
      'timestamp': timestamp.toIso8601String(),
      'metadata': metadata,
      'camera_code': cameraCode,
      'camera_name': cameraName,
    };
  }
}

/**
 * Home Activity Model
 * 
 * Represents activities and events related to specific homes.
 */
class HomeActivity extends BaseActivity {
  final int? homeId;
  final String? homeName;

  const HomeActivity({
    required super.id,
    required super.type,
    required super.description,
    required super.timestamp,
    super.metadata,
    this.homeId,
    this.homeName,
  });

  factory HomeActivity.fromJson(Map<String, dynamic> json) {
    return HomeActivity(
      id: json['id'],
      type: json['type'] ?? 'unknown',
      description: json['description'] ?? 'Unknown activity',
      timestamp: DateTime.parse(json['timestamp']),
      metadata: json['metadata'],
      homeId: json['home_id'],
      homeName: json['home_name'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'description': description,
      'timestamp': timestamp.toIso8601String(),
      'metadata': metadata,
      'home_id': homeId,
      'home_name': homeName,
    };
  }
}

/**
 * Security Event Model
 * 
 * Represents security-related events and alerts.
 */
class SecurityEvent extends BaseActivity {
  final String severity;      // low, medium, high, critical
  final String? cameraCode;
  final int? homeId;
  final bool acknowledged;
  final String? acknowledgedBy;
  final DateTime? acknowledgedAt;

  const SecurityEvent({
    required super.id,
    required super.type,
    required super.description,
    required super.timestamp,
    super.metadata,
    required this.severity,
    this.cameraCode,
    this.homeId,
    this.acknowledged = false,
    this.acknowledgedBy,
    this.acknowledgedAt,
  });

  factory SecurityEvent.fromJson(Map<String, dynamic> json) {
    return SecurityEvent(
      id: json['id'],
      type: json['type'] ?? 'unknown',
      description: json['description'] ?? 'Unknown event',
      timestamp: DateTime.parse(json['timestamp']),
      metadata: json['metadata'],
      severity: json['severity'] ?? 'low',
      cameraCode: json['camera_code'],
      homeId: json['home_id'],
      acknowledged: json['acknowledged'] ?? false,
      acknowledgedBy: json['acknowledged_by'],
      acknowledgedAt: json['acknowledged_at'] != null 
          ? DateTime.parse(json['acknowledged_at']) 
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'description': description,
      'timestamp': timestamp.toIso8601String(),
      'metadata': metadata,
      'severity': severity,
      'camera_code': cameraCode,
      'home_id': homeId,
      'acknowledged': acknowledged,
      'acknowledged_by': acknowledgedBy,
      'acknowledged_at': acknowledgedAt?.toIso8601String(),
    };
  }

  /**
   * Create a copy with acknowledgment
   */
  SecurityEvent acknowledge(String acknowledgedBy) {
    return SecurityEvent(
      id: id,
      type: type,
      description: description,
      timestamp: timestamp,
      metadata: metadata,
      severity: severity,
      cameraCode: cameraCode,
      homeId: homeId,
      acknowledged: true,
      acknowledgedBy: acknowledgedBy,
      acknowledgedAt: DateTime.now(),
    );
  }
}

// ==================== RECORDING MODEL ====================

/**
 * Recording Model
 * 
 * Represents a video recording from a camera.
 */
class Recording {
  final int id;
  final int cameraId;
  final String cameraCode;
  final String filePath;
  final DateTime startTime;
  final DateTime endTime;
  final int durationSeconds;
  final String eventType; // e.g., 'motion_detection', 'manual_record'
  final String? thumbnailUrl;

  const Recording({
    required this.id,
    required this.cameraId,
    required this.cameraCode,
    required this.filePath,
    required this.startTime,
    required this.endTime,
    required this.durationSeconds,
    required this.eventType,
    this.thumbnailUrl,
  });

  factory Recording.fromJson(Map<String, dynamic> json) {
    return Recording(
      id: json['id'],
      cameraId: json['camera_id'],
      cameraCode: json['camera_code'] ?? '',
      filePath: json['file_path'] ?? '',
      startTime: DateTime.parse(json['start_time']),
      endTime: DateTime.parse(json['end_time']),
      durationSeconds: json['duration_seconds'] ?? 0,
      eventType: json['event_type'] ?? 'unknown',
      thumbnailUrl: json['thumbnail_url'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'camera_id': cameraId,
      'camera_code': cameraCode,
      'file_path': filePath,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime.toIso8601String(),
      'duration_seconds': durationSeconds,
      'event_type': eventType,
      'thumbnail_url': thumbnailUrl,
    };
  }

  String get formattedDuration {
    final minutes = (durationSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (durationSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String get formattedStartTime {
    return '${startTime.day}/${startTime.month}/${startTime.year} ${startTime.hour}:${startTime.minute}';
  }
}

// ==================== SETTINGS MODELS ====================

/**
 * User Settings Model
 * 
 * Represents user preferences and application settings.
 */
class UserSettings {
  final bool pushNotifications;
  final bool emailNotifications;
  final bool smsNotifications;
  final bool motionAlerts;
  final bool recordingAlerts;
  final bool systemAlerts;
  final String theme;                    // light, dark, system
  final String language;                 // en, fr, es, etc.
  final Map<String, dynamic>? advanced;  // Advanced settings

  const UserSettings({
    this.pushNotifications = true,
    this.emailNotifications = false,
    this.smsNotifications = false,
    this.motionAlerts = true,
    this.recordingAlerts = true,
    this.systemAlerts = true,
    this.theme = 'system',
    this.language = 'en',
    this.advanced,
  });

  factory UserSettings.fromJson(Map<String, dynamic> json) {
    return UserSettings(
      pushNotifications: json['push_notifications'] ?? true,
      emailNotifications: json['email_notifications'] ?? false,
      smsNotifications: json['sms_notifications'] ?? false,
      motionAlerts: json['motion_alerts'] ?? true,
      recordingAlerts: json['recording_alerts'] ?? true,
      systemAlerts: json['system_alerts'] ?? true,
      theme: json['theme'] ?? 'system',
      language: json['language'] ?? 'en',
      advanced: json['advanced'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'push_notifications': pushNotifications,
      'email_notifications': emailNotifications,
      'sms_notifications': smsNotifications,
      'motion_alerts': motionAlerts,
      'recording_alerts': recordingAlerts,
      'system_alerts': systemAlerts,
      'theme': theme,
      'language': language,
      'advanced': advanced,
    };
  }

  UserSettings copyWith({
    bool? pushNotifications,
    bool? emailNotifications,
    bool? smsNotifications,
    bool? motionAlerts,
    bool? recordingAlerts,
    bool? systemAlerts,
    String? theme,
    String? language,
    Map<String, dynamic>? advanced,
  }) {
    return UserSettings(
      pushNotifications: pushNotifications ?? this.pushNotifications,
      emailNotifications: emailNotifications ?? this.emailNotifications,
      smsNotifications: smsNotifications ?? this.smsNotifications,
      motionAlerts: motionAlerts ?? this.motionAlerts,
      recordingAlerts: recordingAlerts ?? this.recordingAlerts,
      systemAlerts: systemAlerts ?? this.systemAlerts,
      theme: theme ?? this.theme,
      language: language ?? this.language,
      advanced: advanced ?? this.advanced,
    );
  }
}

/**
 * Camera Settings Model
 * 
 * Represents configuration settings for individual cameras.
 */
class CameraSettings {
  final bool motionDetection;
  final bool nightVision;
  final bool audioRecording;
  final bool continuousRecording;
  final double motionSensitivity;        // 0.0 to 1.0
  final int recordingQuality;            // 1-5 (1=lowest, 5=highest)
  final List<String> recordingSchedule;  // Time ranges when recording is active
  final Map<String, dynamic>? advanced;  // Advanced camera-specific settings

  const CameraSettings({
    this.motionDetection = true,
    this.nightVision = false,
    this.audioRecording = true,
    this.continuousRecording = false,
    this.motionSensitivity = 0.5,
    this.recordingQuality = 3,
    this.recordingSchedule = const [],
    this.advanced,
  });

  factory CameraSettings.fromJson(Map<String, dynamic> json) {
    return CameraSettings(
      motionDetection: json['motion_detection'] ?? true,
      nightVision: json['night_vision'] ?? false,
      audioRecording: json['audio_recording'] ?? true,
      continuousRecording: json['continuous_recording'] ?? false,
      motionSensitivity: (json['motion_sensitivity'] ?? 0.5).toDouble(),
      recordingQuality: json['recording_quality'] ?? 3,
      recordingSchedule: json['recording_schedule'] != null 
          ? List<String>.from(json['recording_schedule'])
          : [],
      advanced: json['advanced'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'motion_detection': motionDetection,
      'night_vision': nightVision,
      'audio_recording': audioRecording,
      'continuous_recording': continuousRecording,
      'motion_sensitivity': motionSensitivity,
      'recording_quality': recordingQuality,
      'recording_schedule': recordingSchedule,
      'advanced': advanced,
    };
  }

  CameraSettings copyWith({
    bool? motionDetection,
    bool? nightVision,
    bool? audioRecording,
    bool? continuousRecording,
    double? motionSensitivity,
    int? recordingQuality,
    List<String>? recordingSchedule,
    Map<String, dynamic>? advanced,
  }) {
    return CameraSettings(
      motionDetection: motionDetection ?? this.motionDetection,
      nightVision: nightVision ?? this.nightVision,
      audioRecording: audioRecording ?? this.audioRecording,
      continuousRecording: continuousRecording ?? this.continuousRecording,
      motionSensitivity: motionSensitivity ?? this.motionSensitivity,
      recordingQuality: recordingQuality ?? this.recordingQuality,
      recordingSchedule: recordingSchedule ?? this.recordingSchedule,
      advanced: advanced ?? this.advanced,
    );
  }
}

/**
 * Home Security Settings Model
 * 
 * Represents security system settings for a home.
 */
class HomeSecuritySettings {
  final bool alarmEnabled;
  final String securityMode;             // home, away, sleep, off
  final bool motionAlertsEnabled;
  final bool intrusionDetection;
  final bool automaticArming;
  final String armingSchedule;           // Cron-like schedule for automatic arming
  final List<String> emergencyContacts;  // Phone numbers for emergency alerts
  final Map<String, dynamic>? zones;     // Security zones configuration

  const HomeSecuritySettings({
    this.alarmEnabled = false,
    this.securityMode = 'off',
    this.motionAlertsEnabled = true,
    this.intrusionDetection = true,
    this.automaticArming = false,
    this.armingSchedule = '',
    this.emergencyContacts = const [],
    this.zones,
  });

  factory HomeSecuritySettings.fromJson(Map<String, dynamic> json) {
    return HomeSecuritySettings(
      alarmEnabled: json['alarm_enabled'] ?? false,
      securityMode: json['security_mode'] ?? 'off',
      motionAlertsEnabled: json['motion_alerts_enabled'] ?? true,
      intrusionDetection: json['intrusion_detection'] ?? true,
      automaticArming: json['automatic_arming'] ?? false,
      armingSchedule: json['arming_schedule'] ?? '',
      emergencyContacts: json['emergency_contacts'] != null 
          ? List<String>.from(json['emergency_contacts'])
          : [],
      zones: json['zones'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'alarm_enabled': alarmEnabled,
      'security_mode': securityMode,
      'motion_alerts_enabled': motionAlertsEnabled,
      'intrusion_detection': intrusionDetection,
      'automatic_arming': automaticArming,
      'arming_schedule': armingSchedule,
      'emergency_contacts': emergencyContacts,
      'zones': zones,
    };
  }

  HomeSecuritySettings copyWith({
    bool? alarmEnabled,
    String? securityMode,
    bool? motionAlertsEnabled,
    bool? intrusionDetection,
    bool? automaticArming,
    String? armingSchedule,
    List<String>? emergencyContacts,
    Map<String, dynamic>? zones,
  }) {
    return HomeSecuritySettings(
      alarmEnabled: alarmEnabled ?? this.alarmEnabled,
      securityMode: securityMode ?? this.securityMode,
      motionAlertsEnabled: motionAlertsEnabled ?? this.motionAlertsEnabled,
      intrusionDetection: intrusionDetection ?? this.intrusionDetection,
      automaticArming: automaticArming ?? this.automaticArming,
      armingSchedule: armingSchedule ?? this.armingSchedule,
      emergencyContacts: emergencyContacts ?? this.emergencyContacts,
      zones: zones ?? this.zones,
    );
  }
}

// ==================== UTILITY MODELS ====================

/**
 * API Response Wrapper
 * 
 * Generic wrapper for API responses with success/error handling.
 */
class ApiResponse<T> {
  final bool success;
  final T? data;
  final String? error;
  final int statusCode;
  final Map<String, dynamic>? metadata;

  const ApiResponse({
    required this.success,
    this.data,
    this.error,
    required this.statusCode,
    this.metadata,
  });

  factory ApiResponse.success(T data, int statusCode, {Map<String, dynamic>? metadata}) {
    return ApiResponse(
      success: true,
      data: data,
      statusCode: statusCode,
      metadata: metadata,
    );
  }

  factory ApiResponse.error(String error, int statusCode, {Map<String, dynamic>? metadata}) {
    return ApiResponse(
      success: false,
      error: error,
      statusCode: statusCode,
      metadata: metadata,
    );
  }
}

/**
 * Pagination Info
 * 
 * Contains pagination information for list responses.
 */
class PaginationInfo {
  final int currentPage;
  final int totalPages;
  final int totalItems;
  final int itemsPerPage;
  final bool hasNextPage;
  final bool hasPreviousPage;

  const PaginationInfo({
    required this.currentPage,
    required this.totalPages,
    required this.totalItems,
    required this.itemsPerPage,
    required this.hasNextPage,
    required this.hasPreviousPage,
  });

  factory PaginationInfo.fromJson(Map<String, dynamic> json) {
    return PaginationInfo(
      currentPage: json['current_page'] ?? 1,
      totalPages: json['total_pages'] ?? 1,
      totalItems: json['total_items'] ?? 0,
      itemsPerPage: json['items_per_page'] ?? 10,
      hasNextPage: json['has_next_page'] ?? false,
      hasPreviousPage: json['has_previous_page'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'current_page': currentPage,
      'total_pages': totalPages,
      'total_items': totalItems,
      'items_per_page': itemsPerPage,
      'has_next_page': hasNextPage,
      'has_previous_page': hasPreviousPage,
    };
  }
}

/**
 * Paginated Response
 * 
 * Wrapper for paginated API responses.
 */
class PaginatedResponse<T> {
  final List<T> items;
  final PaginationInfo pagination;

  const PaginatedResponse({
    required this.items,
    required this.pagination,
  });

  factory PaginatedResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) fromJsonT,
  ) {
    return PaginatedResponse(
      items: (json['items'] as List).map((item) => fromJsonT(item)).toList(),
      pagination: PaginationInfo.fromJson(json['pagination']),
    );
  }
}


