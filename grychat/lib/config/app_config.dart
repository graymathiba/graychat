/// Application configuration
///
/// Values are read from --dart-define at build time.
class AppConfig {
  // Backend Server Configuration
  static const String backendUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://127.0.0.1:3000',
  );

  // Supabase Configuration
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  // App Configuration
  static const String appName = 'Grychat';
  static const String appVersion = '1.0.0';

  /// Get the appropriate URL based on the environment
  static String getBackendUrl({String? environment}) {
    environment ??= 'development';

    switch (environment) {
      case 'production':
        return 'https://api.grychat.com';
      case 'staging':
        return 'https://staging-api.grychat.com';
      case 'development':
      default:
        return backendUrl;
    }
  }

  // WebRTC ICE servers for NAT traversal (STUN) and cross-network relay (TURN).
  static const Map<String, dynamic> iceServers = {
    'iceServers': [
      {
        'urls': [
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
        ],
      },
      {
        'urls': 'turn:free.expressturn.com:3478',
        'username': '000000002102080998',
        'credential': 'WoOD+jCtcbNSn1FI3UiKuwBc+4Y=',
      },
    ],
  };
}
