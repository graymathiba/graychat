import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/app_config.dart';
import '../network/signaling_service.dart';
import 'chat_provider.dart';

final signalingServiceProvider = Provider<SignalingService>((ref) {
  final localUserId = ref.watch(localUserIdProvider);
  final service = SignalingService(
    serverUrl: AppConfig.backendUrl,
    localPeerId: localUserId,
  );
  service.connect();
  ref.onDispose(() => service.dispose());
  return service;
});