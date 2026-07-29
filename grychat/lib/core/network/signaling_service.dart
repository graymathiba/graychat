import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as io;

class SignalingService {
  final String localPeerId;
  final io.Socket _socket;
  bool _isConnected = false;

  final StreamController<Map<String, dynamic>> _signalController =
      StreamController<Map<String, dynamic>>.broadcast();

  SignalingService({required io.Socket socket, required this.localPeerId})
      : _socket = socket {
    _setupListeners();
  }

  bool get isConnected => _isConnected;
  Stream<Map<String, dynamic>> get signalStream => _signalController.stream;

  void _setupListeners() {
    _socket.onConnect((_) {
      _isConnected = true;
      _signalController.add({'type': 'server_connection', 'data': {'connected': true}});
    });

    for (final type in ['offer', 'answer', 'ice_candidate']) {
      _socket.on(type, (payload) {
        final message = Map<String, dynamic>.from(payload as Map);
        message['type'] = type;
        _signalController.add(message);
      });
    }

    _socket.onDisconnect((_) {
      _isConnected = false;
      _signalController.add({'type': 'server_connection', 'data': {'connected': false}});
    });
  }

  void emit(String event, dynamic data) {
    _socket.emit(event, data);
  }

  void joinRoom(String roomId) {
    emit('join-room', roomId);
  }

  void sendOffer(String roomId, Map<String, dynamic> data) {
    _sendPeerSignal('offer', roomId, data);
  }

  void sendAnswer(String roomId, Map<String, dynamic> data) {
    _sendPeerSignal('answer', roomId, data);
  }

  void sendIceCandidate(String roomId, Map<String, dynamic> data) {
    _sendPeerSignal('ice_candidate', roomId, data);
  }

  void _sendPeerSignal(String type, String roomId, Map<String, dynamic> data) {
    emit(type, {
      'roomId': roomId,
      'senderId': localPeerId,
      'data': data,
    });
  }

  void dispose() {
    _signalController.close();
  }
}
