import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:device_info_plus/device_info_plus.dart';
import '../../config/app_config.dart';

class CrashReport {
  final String error;
  final String stackTrace;
  final String screen;
  final String userId;
  final String timestamp;
  final String appVersion;
  final String deviceModel;
  final String osVersion;
  final Map<String, dynamic> extra;

  CrashReport({
    required this.error,
    this.stackTrace = '',
    this.screen = '',
    this.userId = '',
    String? timestamp,
    this.appVersion = '1.0.0',
    this.deviceModel = 'unknown',
    this.osVersion = 'unknown',
    this.extra = const {},
  }) : timestamp = timestamp ?? DateTime.now().toUtc().toIso8601String();

  Map<String, dynamic> toJson() => {
    'error': error,
    'stackTrace': stackTrace,
    'screen': screen,
    'userId': userId,
    'timestamp': timestamp,
    'appVersion': appVersion,
    'deviceModel': deviceModel,
    'osVersion': osVersion,
    'extra': extra,
  };
}

class CrashReportService {
  static final CrashReportService _instance = CrashReportService._internal();
  factory CrashReportService() => _instance;
  CrashReportService._internal();

  String _currentScreen = 'unknown';
  String _userId = '';
  bool _initialized = false;
  String _deviceModel = 'unknown';
  String _osVersion = 'unknown';

  void setCurrentScreen(String screen) => _currentScreen = screen;
  void setUserId(String userId) => _userId = userId;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isWindows) {
        final info = await deviceInfo.windowsInfo;
        _deviceModel = info.productName;
        _osVersion = '${info.productName} ${info.displayVersion}';
      } else if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        _deviceModel = '${info.manufacturer} ${info.model}';
        _osVersion = 'Android ${info.version.release}';
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        _deviceModel = info.model;
        _osVersion = '${info.systemName} ${info.systemVersion}';
      } else if (Platform.isLinux) {
        final info = await deviceInfo.linuxInfo;
        _deviceModel = info.name;
        _osVersion = info.versionId ?? 'unknown';
      } else if (Platform.isMacOS) {
        final info = await deviceInfo.macOsInfo;
        _deviceModel = info.model;
        _osVersion = '${info.osRelease} (${info.majorVersion}.${info.minorVersion})';
      }
    } catch (_) {}
  }

  Future<void> reportError(
    Object error,
    StackTrace stackTrace, {
    String? screen,
    Map<String, dynamic>? extra,
  }) async {
    try {
      await initialize();

      final report = CrashReport(
        error: error.toString(),
        stackTrace: stackTrace.toString(),
        screen: screen ?? _currentScreen,
        userId: _userId,
        appVersion: AppConfig.appVersion,
        deviceModel: _deviceModel,
        osVersion: _osVersion,
        extra: extra ?? {},
      );

      _sendToBackend(report);
    } catch (_) {}
  }

  Future<void> _sendToBackend(CrashReport report) async {
    try {
      final url = '${AppConfig.backendUrl}/api/crash-report';
      await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(report.toJson()),
      ).timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  void setupErrorHandlers() {
    FlutterError.onError = (details) {
      reportError(
        details.exception,
        details.stack ?? StackTrace.empty,
        extra: {
          'library': details.library,
          'context': details.context?.toString() ?? '',
        },
      );

      if (kDebugMode) {
        FlutterError.presentError(details);
      }
    };

    PlatformDispatcher.instance.onError = (error, stackTrace) {
      reportError(error, stackTrace);
      return true;
    };
  }
}

final crashReportService = CrashReportService();
