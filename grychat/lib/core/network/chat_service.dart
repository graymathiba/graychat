import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:firebase_auth/firebase_auth.dart';
import '../database/database_service.dart';
import '../models/chat_message.dart';
import '../utils/app_logger.dart';

class ChatService {
  final String serverUrl;
  final String localUserId;
  final DatabaseService? databaseService;

  io.Socket? _socket;
  bool _isDisposed = false;
  bool _isConnecting = false;
  Timer? _reconnectTimer;
  Timer? _presenceHeartbeat;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  static const Duration _baseReconnectDelay = Duration(seconds: 2);

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
  final _searchResultController =
      StreamController<List<Map<String, dynamic>>>.broadcast();
  final _reactionController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _groupController = StreamController<Map<String, dynamic>>.broadcast();
  final _forwardedMessageController = StreamController<ChatMessage>.broadcast();
  final _errorController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _messageHistoryController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _usernameCheckController =
      StreamController<Map<String, dynamic>>.broadcast();

  ChatService({
    required this.serverUrl,
    required this.localUserId,
    this.databaseService,
  });

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
  Stream<List<Map<String, dynamic>>> get searchResultStream =>
      _searchResultController.stream;
  Stream<Map<String, dynamic>> get reactionStream => _reactionController.stream;
  Stream<Map<String, dynamic>> get groupStream => _groupController.stream;
  Stream<ChatMessage> get forwardedMessageStream =>
      _forwardedMessageController.stream;
  Stream<Map<String, dynamic>> get errorStream => _errorController.stream;
  Stream<Map<String, dynamic>> get messageHistoryStream => _messageHistoryController.stream;
  Stream<Map<String, dynamic>> get usernameCheckStream => _usernameCheckController.stream;

  bool get isConnected {
    if (_isDisposed) return false;
    try {
      return _socket?.connected ?? false;
    } catch (_) {
      return false;
    }
  }

  io.Socket get socket {
    assert(!_isDisposed, 'ChatService is disposed');
    if (_socket == null) throw StateError('Socket not connected');
    return _socket!;
  }

  Future<void> connect() async {
    if (_isDisposed || _isConnecting || isConnected) return;
    _isConnecting = true;

    try {
      _socket = io.io(serverUrl, {
        'transports': ['websocket'],
        'autoConnect': false,
        'maxHttpBufferSize': 1e6,
      });

      final s = _socket!;

      s.on('connect', (_) {
        AppLogger.success('ChatService', 'Connected', {'socketId': s.id});
        _isConnecting = false;
        _reconnectAttempts = 0;
        _connectionController.add(true);
        _registerPresence();
        _startPresenceHeartbeat();
        _retryPendingMessages();
      });

      s.on('disconnect', (_) {
        AppLogger.warn('ChatService', 'Disconnected');
        _connectionController.add(false);
        _stopPresenceHeartbeat();
        _handleDisconnect();
      });

      s.on('connect_error', (error) {
        AppLogger.error('ChatService', 'Connection error', error);
        _isConnecting = false;
        _connectionController.add(false);
        _handleDisconnect();
      });

      s.on('myShortCode', (data) {
        final code = data['shortCode'] as String;
        _shortCodeController.add(code);
      });

      s.on('onlineUsersList', (data) {
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

      s.on('newMessage', (data) {
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
        databaseService?.addChatMessage(message);
        _messageController.add(message);
      });

      s.on('messageAck', (data) {
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

      s.on('messageError', (data) {
        final messageData = Map<String, dynamic>.from(data as Map);
        final messageId = messageData['id'] as String?;
        if (messageId != null) {
          databaseService?.updateChatMessageStatus(messageId, 'failed');
        }
        _errorController.add(messageData);
      });

      s.on('typingStatus', (data) {
        _typingController.add(Map<String, dynamic>.from(data as Map));
      });

      s.on('readReceipt', (data) {
        final messageId = data['messageId'] as String?;
        if (messageId != null) {
          databaseService?.updateChatMessageStatus(messageId, 'read');
        }
        _readReceiptController.add(Map<String, dynamic>.from(data as Map));
      });

      s.on('userPresence', (data) {
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

      s.on('resolveShortCodeResult', (data) {
        _resolveResultController.add(Map<String, dynamic>.from(data as Map));
      });

      s.on('searchUsersResult', (data) {
        final results = (data['results'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ?? [];
        _searchResultController.add(results);
      });

      s.on('reaction', (data) {
        _reactionController.add(Map<String, dynamic>.from(data as Map));
      });

      s.on('groupCreated', (data) {
        _groupController.add({
          ...Map<String, dynamic>.from(data as Map),
          'event': 'created',
        });
      });
      s.on('groupInfo', (data) {
        _groupController.add({
          ...Map<String, dynamic>.from(data as Map),
          'event': 'info',
        });
      });
      s.on('groupMemberLeft', (data) {
        _groupController.add({
          ...Map<String, dynamic>.from(data as Map),
          'event': 'memberLeft',
        });
      });

      s.on('newGroupMessage', (data) {
        final message = ChatMessage.fromJson(
          Map<String, dynamic>.from(data as Map),
        );
        databaseService?.addChatMessage(message);
        _messageController.add(message);
      });

      s.on('messagesHistory', (data) {
        final roomId = data['roomId'] as String? ?? '';
        final list = (data['messages'] as List?)
            ?.map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList() ?? [];
        _messageHistoryController.add({'roomId': roomId, 'messages': list});
      });

      s.on('checkUsernameResult', (data) {
        _usernameCheckController.add(Map<String, dynamic>.from(data as Map));
      });

      String? token;
      try {
        final user = FirebaseAuth.instance.currentUser;
        token = await user?.getIdToken();
      } catch (_) {}

      if (token != null && !_isDisposed) {
        try {
          (s.io as dynamic).opts['auth'] = {'token': token};
        } catch (_) {}
      }

      if (!_isDisposed) s.connect();
    } catch (e) {
      _isConnecting = false;
      _handleDisconnect();
    }
  }

  void _registerPresence() {
    final profile = databaseService?.getUserProfile(localUserId);
    final data = <String, dynamic>{
      'userId': localUserId,
      'timestamp': DateTime.now().toIso8601String(),
    };
    if (profile != null) {
      data['deviceName'] = '${profile.firstName} ${profile.lastName}'.trim();
      data['phoneNumber'] = profile.phoneNumber;
      data['profilePicBase64'] = profile.profilePicBase64 ?? '';
      data['username'] = profile.username ?? '';
    }
    if (isConnected) {
      _socket!.emit('register', data);
    }
  }

  void updateProfilePresence() {
    if (isConnected) _registerPresence();
  }

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
    if (!isConnected) return;
    _socket!.emit('resolveShortCode', {'shortCode': normalizedCode});
  }

  void searchUsers(String query) {
    if (!isConnected || query.trim().length < 2) return;
    _socket!.emit('searchUsers', {'query': query.trim()});
  }

  void checkUsername(String username) {
    if (!isConnected || username.trim().length < 3) return;
    _socket!.emit('checkUsername', {'username': username.trim()});
  }

  void getMessages(String roomId, {int limit = 50}) {
    if (!isConnected) return;
    _socket!.emit('getMessages', {'roomId': roomId, 'limit': limit});
  }

  void joinRoom(String roomId) {
    if (!isConnected) return;
    _socket!.emit('join-room', roomId);
  }

  final Set<String> _pendingMessageIds = {};

  void sendMessage(ChatMessage message) {
    if (!isConnected) {
      _pendingMessageIds.add(message.id);
      return;
    }
    _pendingMessageIds.remove(message.id);
    _socket!.emit('sendMessage', message.toJson());
  }

  void _retryPendingMessages() {
    if (_pendingMessageIds.isEmpty || databaseService == null) return;
    for (final messageId in List<String>.from(_pendingMessageIds)) {
      final message = databaseService!.getChatMessageById(messageId);
      if (message != null && message.status == 'sending') {
        sendMessage(message);
      } else {
        _pendingMessageIds.remove(messageId);
      }
    }
  }

  void sendTypingStatus(String roomId, bool isTyping) {
    if (!isConnected) return;
    _socket!.emit('typingStatus', {
      'roomId': roomId,
      'userId': localUserId,
      'isTyping': isTyping,
    });
  }

  void sendReadReceipt(String roomId, String messageId) {
    if (!isConnected) return;
    _socket!.emit('readReceipt', {
      'roomId': roomId,
      'userId': localUserId,
      'messageId': messageId,
    });
  }

  void sendReaction({
    required String targetId,
    required String messageId,
    required String emoji,
    required String action,
    String? groupId,
  }) {
    if (!isConnected) return;
    final data = <String, dynamic>{
      'targetId': targetId,
      'messageId': messageId,
      'emoji': emoji,
      'action': action,
    };
    if (groupId != null) data['groupId'] = groupId;
    _socket!.emit('reaction', data);
  }

  void createGroup({
    required String groupId,
    required String groupName,
    required List<String> memberIds,
  }) {
    if (!isConnected) return;
    _socket!.emit('createGroup', {
      'groupId': groupId,
      'groupName': groupName,
      'memberIds': memberIds,
    });
  }

  void joinGroup(String groupId) {
    if (!isConnected) return;
    _socket!.emit('joinGroup', {'groupId': groupId});
  }

  void leaveGroup(String groupId) {
    if (!isConnected) return;
    _socket!.emit('leaveGroup', {'groupId': groupId});
  }

  void updateProfile({required String displayName, String? profilePicBase64}) {
    if (!isConnected) return;
    _socket!.emit('updateProfile', {
      'displayName': displayName,
      'profilePicBase64': profilePicBase64,
    });
    _registerPresence();
  }

  void forwardMessage(ChatMessage original, List<String> targetUserIds) {
    if (!isConnected) return;
    for (final targetId in targetUserIds) {
      final forwarded = original.copyWith(
        receiverId: targetId,
        roomId: ChatMessage.deriveRoomId(original.senderId, targetId),
        groupId: null,
        forwardedFrom: original.senderId,
        timestamp: DateTime.now(),
        status: 'sending',
      );
      _socket!.emit('sendMessage', forwarded.toJson());
      databaseService?.addChatMessage(forwarded);
    }
  }

  void _handleDisconnect() {
    if (_isDisposed) return;
    _reconnectTimer?.cancel();

    if (_reconnectAttempts >= _maxReconnectAttempts) {
      return;
    }

    _reconnectAttempts++;
    final delaySeconds =
        (_baseReconnectDelay.inSeconds * (1 << (_reconnectAttempts - 1))).clamp(
          0,
          120,
        );
    final delay = Duration(seconds: delaySeconds);

    _reconnectTimer = Timer(delay, () {
      if (!_isDisposed && !isConnected) {
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
      if (!_isDisposed) _socket?.disconnect();
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
    _searchResultController.close();
    _reactionController.close();
    _groupController.close();
    _forwardedMessageController.close();
    _errorController.close();
    _messageHistoryController.close();
    _usernameCheckController.close();
  }
}
