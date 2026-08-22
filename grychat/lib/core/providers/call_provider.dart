import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/call_service.dart';
import 'chat_provider.dart';

final callServiceProvider = Provider<CallService>((ref) {
  final chatService = ref.watch(chatServiceProvider);
  final localUserId = ref.watch(localUserIdProvider);

  final service = CallService(
    chatService: chatService,
    localUserId: localUserId,
  );

  ref.onDispose(() => service.dispose());
  return service;
});

final callInfoProvider = StreamProvider<CallInfo?>((ref) {
  final callService = ref.watch(callServiceProvider);
  return callService.callInfoStream;
});
