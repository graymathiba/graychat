/// Structured logging for the application
/// 
/// Usage:
///   AppLogger.info('Chat loaded', {'roomId': roomId});
///   AppLogger.error('Connection failed', error);
library;

class AppLogger {
  static const String _prefix = '[Grychat]';
  static bool _debugMode = true;

  static void setDebugMode(bool enabled) => _debugMode = enabled;

  /// Log info level messages
  static void info(String section, String message, [Map<String, dynamic>? context]) {
    if (!_debugMode) return;
    final ctx = context != null ? ' | ${context.entries.map((e) => '${e.key}=${e.value}').join(', ')}' : '';
    print('$_prefix ℹ️  [$section] $message$ctx');
  }

  /// Log warning level messages
  static void warn(String section, String message, [dynamic error]) {
    if (!_debugMode) return;
    final errStr = error != null ? ' | ERROR: $error' : '';
    print('$_prefix ⚠️  [$section] $message$errStr');
  }

  /// Log error level messages
  static void error(String section, String message, [dynamic error, StackTrace? stackTrace]) {
    final errStr = error != null ? ' | ERROR: $error' : '';
    final stackStr = stackTrace != null ? '\n$stackTrace' : '';
    print('$_prefix ❌ [$section] $message$errStr$stackStr');
  }

  /// Log success messages
  static void success(String section, String message, [Map<String, dynamic>? context]) {
    if (!_debugMode) return;
    final ctx = context != null ? ' | ${context.entries.map((e) => '${e.key}=${e.value}').join(', ')}' : '';
    print('$_prefix ✅ [$section] $message$ctx');
  }

  /// Log debug messages (only in debug mode)
  static void debug(String section, String message, [Map<String, dynamic>? context]) {
    if (!_debugMode) return;
    final ctx = context != null ? ' | ${context.entries.map((e) => '${e.key}=${e.value}').join(', ')}' : '';
    print('$_prefix 🐛 [$section] $message$ctx');
  }
}
