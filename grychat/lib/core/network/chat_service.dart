import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:firebase_auth/firebase_auth.dart';
import '../database/database_service.dart';
import '../models/chat_message.dart';
import '../utils/app_logger.dart';

/// ChatService handles server-routed messaging via Socket.io.
/// Supports short code discovery, presence tracking, typing, read receipts.
class ChatService {
  final String serverUrl;
  final String localUserId;
  final DatabaseService? databaseService;

  late io.Socket _socket;
  bool _isDisposed = false;
  bool _isConnecting = false;
  Timer? _reconnectTimer;
  Timer? _presenceHeartbeat;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  static const Duration _baseReconnectDelay = Duration(seconds: 2);

  // ─── Stream controllers ──────────────────────────────────────────
  final _connectionController = StreamController<bool>.broadcast();
  final _messageController = StreamController<ChatMessage>.broadcast();
  final _ackController = StreamController<Map<String, dynamic>>.broadcast();
  final _typingController = StreamController<Map<String, dynamic>>.broadcast();
  final _readReceiptController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _presenceController =
      StreamController<Map<String, dynamic>>.broadcast();
  final Set<String> _knownPresenceIds = {};
  final Map<String, Map<String, dynamic>> _knownUsersByShortCode = {};
  final _shortCodeController = StreamController<String>.broadcast();
  final _resolveResultController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _reactionController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _groupController = StreamController<Map<String, dynamic>>.broadcast();
  final _forwardedMessageController = StreamController<ChatMessage>.broadcast();

  ChatService({
    required this.serverUrl,
    required this.localUserId,
    this.databaseService,
  });

  // ─── Public streams ──────────────────────────────────────────────
  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<ChatMessage> get messageStream => _messageController.stream;
  Stream<Map<String, dynamic>> get ackStream => _ackController.stream;
  Stream<Map<String, dynamic>> get typingStream => _typingController.stream;
  Stream<Map<String, dynamic>> get readReceiptStream =>
      _readReceiptController.stream;
  Stream<Map<String, dynamic>> get presenceStream => _presenceController.stream;
  Stream<String> get shortCodeStream => _shortCodeController.stream;
  Stream<Map<String, dynamic>> get resolveResultStream =>
      _resolveResultController.stream;
  Stream<Map<String, dynamic>> get reactionStream => _reactionController.stream;
  Stream<Map<String, dynamic>> get groupStream => _groupController.stream;
  Stream<ChatMessage> get forwardedMessageStream =>
      _forwardedMessageController.stream;

  bool get isConnected {
    try {
      return _socket.connected;
    } catch (_) {
      return false;
    }
  }

  io.Socket get socket => _socket;

  // ─── Connect ─────────────────────────────────────────────────────
  Future<void> connect() async {
    if (_isDisposed || _isConnecting || isConnected) return;
    _isConnecting = true;

    try {
      String? token;
      try {
        final user = FirebaseAuth.instance.currentUser;
        token = await user?.getIdToken();
      } catch (_) {}

      _socket = io.io(serverUrl, {
        'transports': ['websocket'],
        'autoConnect': false,
        'maxHttpBufferSize': 100e6,
        if (token != null) 'auth': {'token': token},
      });

      // ── Connection events ─────────────────────────────────────
      _socket.on('connect', (_) {
        AppLogger.success('ChatService', 'Connected', {'socketId': _socket.id});
        _isConnecting = false;
        _reconnectAttempts = 0; // Reset on successful connection
        _connectionController.add(true);
        _registerPresence();
        _startPresenceHeartbeat();
      });

      _socket.on('disconnect', (_) {
        AppLogger.warn('ChatService', 'Disconnected');
        _connectionController.add(false);
        _stopPresenceHeartbeat();
        _handleDisconnect();
      });

      _socket.on('connect_error', (error) {
        AppLogger.error('ChatService', 'Connection error', error);
        _isConnecting = false;
        _connectionController.add(false);
        _handleDisconnect();
      });

      // ── My short code from server ─────────────────────────────
      _socket.on('myShortCode', (data) {
        final code = data['shortCode'] as String;
        print('[ChatService] 🔑 My short code: $code');
        _shortCodeController.add(code);
      });

      // ── Full online users list (sent on connect) ──────────────
      _socket.on('onlineUsersList', (data) {
        final list = (data as List)
            .map((user) => Map<String, dynamic>.from(user as Map))
            .toList();
        final currentIds = list
            .map((user) => user['userId'] as String?)
            .whereType<String>()
            .toSet();
        for (final userId in _knownPresenceIds.difference(currentIds)) {
          _presenceController.add({
            'userId': userId,
            'status': 'offline',
            'lastSeen': DateTime.now().toIso8601String(),
          });
        }
        _knownPresenceIds
          ..clear()
          ..addAll(currentIds);
        _knownUsersByShortCode.clear();
        for (final user in list) {
          final shortCode = user['shortCode'] as String?;
          if (shortCode != null && shortCode.isNotEmpty) {
            _knownUsersByShortCode[shortCode.toUpperCase()] = user;
          }
          _presenceController.add(Map<String, dynamic>.from(user));
        }
      });

      // ── Messaging events ──────────────────────────────────────
      _socket.on('newMessage', (data) {
        final message = ChatMessage.fromJson(
          Map<String, dynamic>.from(data as Map),
        );
        if (message.senderId != localUserId &&
            message.receiverId != localUserId) {
          AppLogger.warn(
            'ChatService',
            'Ignoring message for another conversation',
            message.id,
          );
          return;
        }
        print('[ChatService] 📨 New message from ${message.senderId}');
        databaseService?.addChatMessage(message);
        _messageController.add(message);
      });

      _socket.on('messageAck', (data) {
        print('[ChatService] ✓ Message acknowledged: ${data['id']}');
        final messageId = data['id'] as String;
        final status = data['status'] as String;
        final serverTs = data['serverTimestamp'] != null
            ? DateTime.parse(data['serverTimestamp'] as String)
            : null;
        databaseService?.updateChatMessageStatus(
          messageId,
          status,
          serverTimestamp: serverTs,
        );
        _ackController.add(Map<String, dynamic>.from(data as Map));
      });

      // ── Typing events ─────────────────────────────────────────
      _socket.on('typingStatus', (data) {
        _typingController.add(Map<String, dynamic>.from(data as Map));
      });

      // ── Read receipt events ───────────────────────────────────
      _socket.on('readReceipt', (data) {
        final messageId = data['messageId'] as String?;
        if (messageId != null) {
          databaseService?.updateChatMessageStatus(messageId, 'read');
        }
        _readReceiptController.add(Map<String, dynamic>.from(data as Map));
      });

      // ── Presence events ───────────────────────────────────────
      _socket.on('userPresence', (data) {
        final presence = Map<String, dynamic>.from(data as Map);
        final userId = presence['userId'] as String?;
        if (userId != null) {
          if (presence['status'] == 'online') {
            _knownPresenceIds.add(userId);
          } else {
            _knownPresenceIds.remove(userId);
          }
        }
        final shortCode = presence['shortCode'] as String?;
        if (shortCode != null && presence['status'] == 'online') {
          _knownUsersByShortCode[shortCode.toUpperCase()] = presence;
        } else if (shortCode != null) {
          _knownUsersByShortCode.remove(shortCode.toUpperCase());
        }
        _presenceController.add(presence);
      });

      // ── Short code resolve result ─────────────────────────────
      _socket.on('resolveShortCodeResult', (data) {
        _resolveResultController.add(Map<String, dynamic>.from(data as Map));
      });

      // ── Reaction events ──────────────────────────────────────
      _socket.on('reaction', (data) {
        _reactionController.add(Map<String, dynamic>.from(data as Map));
      });

      // ── Group events ─────────────────────────────────────────
      _socket.on('groupCreated', (data) {
        _groupController.add({
          ...Map<String, dynamic>.from(data as Map),
          'event': 'created',
        });
      });
      _socket.on('groupInfo', (data) {
        _groupController.add({
          ...Map<String, dynamic>.from(data as Map),
          'event': 'info',
        });
      });
      _socket.on('groupMemberLeft', (data) {
        _groupController.add({
          ...Map<String, dynamic>.from(data as Map),
          'event': 'memberLeft',
        });
      });

      // ── Group messages (routed via socket room) ──────────────
      _socket.on('newGroupMessage', (data) {
        final message = ChatMessage.fromJson(
          Map<String, dynamic>.from(data as Map),
        );
        print('[ChatService] 📨 New group message from ${message.senderId}');
        databaseService?.addChatMessage(message);
        _messageController.add(message);
      });

      _socket.connect();
    } catch (e) {
      print('[ChatService] 🔴 Connection failed: $e');
      _isConnecting = false;
      _handleDisconnect();
    }
  }

  // ─── Presence Registration ───────────────────────────────────────
  void _registerPresence() {
    final profile = databaseService?.getUserProfile();
    final data = <String, dynamic>{
      'userId': localUserId,
      'timestamp': DateTime.now().toIso8601String(),
    };
    if (profile != null) {
      data['deviceName'] = '${profile.firstName} ${profile.lastName}'.trim();
      data['phoneNumber'] = profile.phoneNumber;
      data['profilePicBase64'] = profile.profilePicBase64 ?? '';
    }
    if (isConnected) {
      _socket.emit('register', data);
    }
  }

  /// Re-register presence after a profile update
  void updateProfilePresence() {
    if (isConnected) _registerPresence();
  }

  // ─── Presence Heartbeat ────────────────────────────────────────
  // Periodically re-register presence to recover from missed events.
  void _startPresenceHeartbeat() {
    _stopPresenceHeartbeat();
    _presenceHeartbeat = Timer.periodic(const Duration(seconds: 30), (_) {
      if (isConnected) _registerPresence();
    });
  }

  void _stopPresenceHeartbeat() {
    _presenceHeartbeat?.cancel();
    _presenceHeartbeat = null;
  }

  // ─── Short Code Resolution ───────────────────────────────────────
  void resolveShortCode(String shortCode) {
    final normalizedCode = shortCode.trim().toUpperCase();
    final knownUser = _knownUsersByShortCode[normalizedCode];
    if (knownUser != null) {
      _resolveResultController.add({
        'found': true,
        'shortCode': normalizedCode,
        'userId': knownUser['userId'],
        'displayName': knownUser['displayName'] ?? '',
        'profilePicBase64': knownUser['profilePicBase64'] ?? '',
      });
      return;
    }
    if (!isConnected) {
      print('[ChatService] Cannot resolve short code: Not connected');
      return;
    }
    _socket.emit('resolveShortCode', {
      'shortCode': normalizedCode,
    });
  }

  // ─── Room Management ─────────────────────────────────────────────
  void joinRoom(String roomId) {
    if (!isConnected) {
      print('[ChatService] Cannot join room: Not connected');
      return;
    }
    _socket.emit('join-room', roomId);
    print('[ChatService] 🏠 Joining room: $roomId');
  }

  // ─── Send Message ────────────────────────────────────────────────
  void sendMessage(ChatMessage message) {
    if (!isConnected) {
      print('[ChatService] Cannot send message: Not connected');
      return;
    }
    _socket.emit('sendMessage', message.toJson());
    print('[ChatService] 💬 Sent message: ${message.id}');
  }

  // ─── Typing Status ──────────────────────────────────────────────
  void sendTypingStatus(String roomId, bool isTyping) {
    if (!isConnected) return;
    _socket.emit('typingStatus', {
      'roomId': roomId,
      'userId': localUserId,
      'isTyping': isTyping,
    });
  }

  // ─── Read Receipt ────────────────────────────────────────────────
  void sendReadReceipt(String roomId, String messageId) {
    if (!isConnected) return;
    _socket.emit('readReceipt', {
      'roomId': roomId,
      'userId': localUserId,
      'messageId': messageId,
    });
  }

  // ─── Reaction ────────────────────────────────────────────────────
  void sendReaction({
    required String targetId,
    required String messageId,
    required String emoji,
    required String action, // 'add' or 'remove'
    String? groupId,
  }) {
    if (!isConnected) return;
    _socket.emit('reaction', {
      'targetId': targetId,
      'messageId': messageId,
      'emoji': emoji,
      'action': action,
      if (groupId != null) 'groupId': groupId,
    });
  }

  // ─── Group Management ────────────────────────────────────────────
  void createGroup({
    required String groupId,
    required String groupName,
    required List<String> memberIds,
  }) {
    if (!isConnected) return;
    _socket.emit('createGroup', {
      'groupId': groupId,
      'groupName': groupName,
      'memberIds': memberIds,
    });
  }

  void joinGroup(String groupId) {
    if (!isConnected) return;
    _socket.emit('joinGroup', {'groupId': groupId});
  }

  void leaveGroup(String groupId) {
    if (!isConnected) return;
    _socket.emit('leaveGroup', {'groupId': groupId});
  }

  // ─── Profile Update ──────────────────────────────────────────────
  void updateProfile({
    required String displayName,
    String? profilePicBase64,
  }) {
    if (!isConnected) return;
    _socket.emit('updateProfile', {
      'displayName': displayName,
      'profilePicBase64': profilePicBase64,
    });
    // Also update local presence registration
    _registerPresence();
  }

  // ─── Message Forwarding ──────────────────────────────────────────
  void forwardMessage(ChatMessage original, List<String> targetUserIds) {
    if (!isConnected) return;
    for (final targetId in targetUserIds) {
      final forwarded = original.copyWith(
        receiverId: targetId,
        forwardedFrom: original.senderId,
        timestamp: DateTime.now(),
        status: 'sending',
      );
      _socket.emit('sendMessage', forwarded.toJson());
      databaseService?.addChatMessage(forwarded);
    }
  }

  // ─── Reconnection with Exponential Backoff ──────────────────────
  void _handleDisconnect() {
    if (_isDisposed) return;
    _reconnectTimer?.cancel();

    if (_reconnectAttempts >= _maxReconnectAttempts) {
      AppLogger.error(
        'ChatService',
        'Max reconnection attempts reached',
        'gave up after $_maxReconnectAttempts attempts',
      );
      return;
    }

    _reconnectAttempts++;
    // Exponential backoff: 2s, 4s, 8s, 16s, etc (max 2 minutes)
    final delaySeconds =
        (_baseReconnectDelay.inSeconds * (1 << (_reconnectAttempts - 1))).clamp(
          0,
          120,
        );
    final delay = Duration(seconds: delaySeconds);

    AppLogger.warn(
      'ChatService',
      'Scheduling reconnect',
      'attempt $_reconnectAttempts in ${delay.inSeconds}s',
    );

    _reconnectTimer = Timer(delay, () {
      if (!_isDisposed && !isConnected) {
        AppLogger.info('ChatService', 'Attempting auto-reconnect', {
          'attempt': _reconnectAttempts,
          'maxAttempts': _maxReconnectAttempts,
        });
        connect();
      }
    });
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
    _stopPresenceHeartbeat();
    try {
      _socket.disconnect();
    } catch (_) {}
  }

  void dispose() {
    _isDisposed = true;
    disconnect();
    _connectionController.close();
    _messageController.close();
    _ackController.close();
    _typingController.close();
    _readReceiptController.close();
    _presenceController.close();
    _shortCodeController.close();
    _resolveResultController.close();
    _reactionController.close();
    _groupController.close();
    _forwardedMessageController.close();
    AppLogger.success('ChatService', 'Disposed');
  }
}
