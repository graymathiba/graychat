class AppConfig {
  static const String backendUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'https://graychat.onrender.com',
  );

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static const String appName = 'Grychat';
  static const String appVersion = '1.0.0';

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

  static const Map<String, dynamic> iceServers = {
    'iceServers': [
      {
        'urls': [
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
        ],
      },
    ],
  };
}
