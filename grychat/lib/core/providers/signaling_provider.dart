import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/signaling_service.dart';
import 'chat_provider.dart';

final signalingServiceProvider = Provider<SignalingService>((ref) {
  final chatService = ref.watch(chatServiceProvider);
  final localUserId = ref.watch(localUserIdProvider);
  final service = SignalingService(
    socket: chatService.socket,
    localPeerId: localUserId,
  );
  ref.onDispose(() => service.dispose());
  return service;
});
