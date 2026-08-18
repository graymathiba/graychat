import 'package:flutter_test/flutter_test.dart';
import 'package:grychat/config/app_config.dart';

void main() {
  group('AppConfig', () {
    test('backendUrl has default value', () {
      expect(AppConfig.backendUrl, isNotEmpty);
    });

    test('getBackendUrl returns correct URLs per environment', () {
      expect(AppConfig.getBackendUrl(environment: 'production'), contains('https://'));
      expect(AppConfig.getBackendUrl(environment: 'staging'), contains('https://'));
      expect(AppConfig.getBackendUrl(environment: 'development'), isNotEmpty);
      expect(AppConfig.getBackendUrl(), isNotEmpty); // default
    });

    test('iceServers contains STUN servers', () {
      final iceServers = AppConfig.iceServers;
      expect(iceServers, contains('iceServers'));
      final servers = iceServers['iceServers'] as List;
      expect(servers.isNotEmpty, isTrue);
      final urls = (servers.first as Map)['urls'] as List;
      expect(urls.any((u) => u.toString().contains('stun')), isTrue);
    });

    test('appName and appVersion are set', () {
      expect(AppConfig.appName, equals('Grychat'));
      expect(AppConfig.appVersion, isNotEmpty);
    });
  });
}
