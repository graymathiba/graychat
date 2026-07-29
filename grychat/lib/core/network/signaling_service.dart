import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:firebase_auth/firebase_auth.dart';

class SignalingService {
  final String serverUrl;
  final String localPeerId;
  late io.Socket _socket;
  bool _isConnected = false;

  final StreamController<Map<String, dynamic>> _signalController =
      StreamController<Map<String, dynamic>>.broadcast();

  SignalingService({required this.serverUrl, required this.localPeerId});

  bool get isConnected => _isConnected;
  Stream<Map<String, dynamic>> get signalStream => _signalController.stream;

  Future<void> connect() async {
    String? token;
    try {
      final user = FirebaseAuth.instance.currentUser;
      token = await user?.getIdToken();
    } catch (_) {}
    
    _socket = io.io(serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      if (token != null) 'auth': {'token': token},
    });

    _socket.onConnect((_) {
      _isConnected = true;
      _socket.emit('register', {'userId': localPeerId});
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

    _socket.connect();
  }

  void emit(String event, dynamic data) {
    if (_isConnected) {
      _socket.emit(event, data);
    }
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
    _socket.disconnect();
    _socket.dispose();
    _signalController.close();
  }
}