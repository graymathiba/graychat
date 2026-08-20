library;

import 'package:flutter/foundation.dart';

class AppLogger {
  static const String _prefix = '[Grychat]';
  static bool _debugMode = true;

  static void setDebugMode(bool enabled) => _debugMode = enabled;
  static void info(String section, String message, [Map<String, dynamic>? context]) {
    if (!_debugMode) return;
    final ctx = context != null ? ' | ${context.entries.map((e) => '${e.key}=${e.value}').join(', ')}' : '';
    debugPrint('$_prefix INFO [$section] $message$ctx');
  }
  static void warn(String section, String message, [dynamic error]) {
    if (!_debugMode) return;
    final errStr = error != null ? ' | ERROR: $error' : '';
    debugPrint('$_prefix WARN [$section] $message$errStr');
  }
  static void error(String section, String message, [dynamic error, StackTrace? stackTrace]) {
    final errStr = error != null ? ' | ERROR: $error' : '';
    final stackStr = stackTrace != null ? '\n$stackTrace' : '';
    debugPrint('$_prefix ERROR [$section] $message$errStr$stackStr');
  }
  static void success(String section, String message, [Map<String, dynamic>? context]) {
    if (!_debugMode) return;
    final ctx = context != null ? ' | ${context.entries.map((e) => '${e.key}=${e.value}').join(', ')}' : '';
    debugPrint('$_prefix OK [$section] $message$ctx');
  }
  static void debug(String section, String message, [Map<String, dynamic>? context]) {
    if (!_debugMode) return;
    final ctx = context != null ? ' | ${context.entries.map((e) => '${e.key}=${e.value}').join(', ')}' : '';
    debugPrint('$_prefix DEBUG [$section] $message$ctx');
  }
}
