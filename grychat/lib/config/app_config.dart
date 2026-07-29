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
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://peaoxjefltucmyibmgnn.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_GzSVIBbE318iyLPpbbSa9A_rMYNysAW',
  );

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
}
