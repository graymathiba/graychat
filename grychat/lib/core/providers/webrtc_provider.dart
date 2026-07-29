import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/webrtc_service.dart';
import 'database_provider.dart';
import 'signaling_provider.dart';

// Provides the WebRTCService instance
final webrtcServiceProvider = Provider<WebRTCService>((ref) {
  final signaling = ref.watch(signalingServiceProvider);
  final db = ref.watch(databaseServiceProvider);
  return WebRTCService(signaling, db);
});

// Provides the reactive connection states for peers
final peerConnectionStateProvider = StateNotifierProvider<PeerConnectionNotifier, Map<String, String>>((ref) {
  final webrtcService = ref.watch(webrtcServiceProvider);
  return PeerConnectionNotifier(webrtcService);
});

class PeerConnectionNotifier extends StateNotifier<Map<String, String>> {
  final WebRTCService _webRTCService;

  PeerConnectionNotifier(this._webRTCService) : super({}) {
    _webRTCService.connectionStateStream.listen((update) {
      state = {
        ...state,
        update.peerId: update.state,
      };
    });
  }

  void connectToPeer(String peerId) {
    _webRTCService.connectToPeer(peerId);
  }
}