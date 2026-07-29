import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../config/app_config.dart';
import '../network/chat_service.dart';
import '../database/database_service.dart';
import '../models/chat_message.dart';
import '../utils/app_logger.dart';
import 'database_provider.dart';

// ─── Firebase Auth State ──────────────────────────────────────────
final currentUserProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

// ─── Stable User ID ────────────────────────────────────────────────
final localUserIdProvider = Provider<String>((ref) {
  // Try Firebase Auth first (only if initialized)
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) return user.uid;
  } catch (_) {}

  // Try to load from Hive if initialized
  if (Hive.isBoxOpen(DatabaseService.settingsBoxName)) {
    final settingsBox = Hive.box<String>(DatabaseService.settingsBoxName);
    var storedId = settingsBox.get('local_user_id');
    if (storedId == null) {
      storedId = const Uuid().v4();
      settingsBox.put('local_user_id', storedId);
    }
    return storedId;
  }

  return const Uuid().v4();
});

// ─── ChatService Singleton ─────────────────────────────────────────
final chatServiceProvider = Provider<ChatService>((ref) {
  final dbService = ref.watch(databaseServiceProvider);
  final localUserId = ref.watch(localUserIdProvider);

  final serverUrl = AppConfig.backendUrl;

  AppLogger.info('ChatService', 'Initializing', {
    'serverUrl': serverUrl,
    'localUserId': localUserId.substring(0, 8),
  });

  final service = ChatService(
    serverUrl: serverUrl,
    localUserId: localUserId,
    databaseService: dbService,
  );

  service.connect();
  ref.onDispose(() => service.dispose());

  return service;
});

// ─── Connection State ──────────────────────────────────────────────
final chatConnectionProvider =
    StateNotifierProvider<ChatConnectionNotifier, bool>((ref) {
      final chatService = ref.watch(chatServiceProvider);
      return ChatConnectionNotifier(chatService);
    });

class ChatConnectionNotifier extends StateNotifier<bool> {
  late final StreamSubscription _sub;

  ChatConnectionNotifier(ChatService chatService)
    : super(chatService.isConnected) {
    _sub = chatService.connectionStream.listen((connected) {
      state = connected;
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

// ─── My Short Code ─────────────────────────────────────────────────
// The server-assigned short code for the local user (e.g., "GRY-4A2F")
final myShortCodeProvider = StateNotifierProvider<MyShortCodeNotifier, String>((
  ref,
) {
  final chatService = ref.watch(chatServiceProvider);
  final localUserId = ref.watch(localUserIdProvider);
  return MyShortCodeNotifier(chatService, localUserId);
});

class MyShortCodeNotifier extends StateNotifier<String> {
  late final StreamSubscription _sub;

  MyShortCodeNotifier(ChatService chatService, String localUserId)
    : super(_deriveShortCode(localUserId)) {
    _sub = chatService.shortCodeStream.listen((code) {
      state = code;
    });
  }

  // Deterministic fallback before server responds (mirrors backend logic)
  static String _deriveShortCode(String userId) {
    int hash = 0;
    for (int i = 0; i < userId.length; i++) {
      hash = ((hash << 5) - hash) + userId.codeUnitAt(i);
      hash = hash.toSigned(32);
    }
    final code = hash.abs().toRadixString(36).toUpperCase().padLeft(4, '0');
    return 'GRY-${code.substring(0, code.length >= 4 ? 4 : code.length).padRight(4, '0')}';
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

// ─── Short Code Resolve Result ─────────────────────────────────────
// One-shot result when resolving a short code to a userId
final shortCodeResolveProvider =
    StateNotifierProvider<ShortCodeResolveNotifier, Map<String, dynamic>?>((
      ref,
    ) {
      final chatService = ref.watch(chatServiceProvider);
      return ShortCodeResolveNotifier(chatService);
    });

class ShortCodeResolveNotifier extends StateNotifier<Map<String, dynamic>?> {
  late final StreamSubscription _sub;
  final ChatService _chatService;

  ShortCodeResolveNotifier(this._chatService) : super(null) {
    _sub = _chatService.resolveResultStream.listen((result) {
      state = result;
    });
  }

  void resolve(String shortCode) {
    state = null; // reset
    _chatService.resolveShortCode(shortCode);
  }

  void clear() => state = null;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

// ─── User Presence ─────────────────────────────────────────────────
// Tracks online/offline + display name + short code for all users
final userPresenceProvider =
    StateNotifierProvider<
      UserPresenceNotifier,
      Map<String, Map<String, dynamic>>
    >((ref) {
      final chatService = ref.watch(chatServiceProvider);
      final dbService = ref.watch(databaseServiceProvider);
      return UserPresenceNotifier(chatService, dbService);
    });

class UserPresenceNotifier
    extends StateNotifier<Map<String, Map<String, dynamic>>> {
  late final StreamSubscription _sub;
  final DatabaseService _dbService;

  UserPresenceNotifier(ChatService chatService, this._dbService) : super({}) {
    _sub = chatService.presenceStream.listen((data) {
      final userId = data['userId'] as String;

      // Merge with existing data so we don't lose displayName/profilePicBase64
      // on offline events that may lack those fields.
      final existing = state[userId];
      final merged = <String, dynamic>{
        if (existing != null) ...existing,
        ...data,
      };
      // If the incoming event has no displayName but we have one cached, keep it.
      if (merged['displayName'] == null && existing != null && existing['displayName'] != null) {
        merged['displayName'] = existing['displayName'];
        merged['profilePicBase64'] = existing['profilePicBase64'];
      }
      state = {...state, userId: merged};

      // Auto-update peer in local database to persist name changes
      if (merged['displayName'] != null) {
        final existingPeer = _dbService
            .getAllPeers()
            .where((p) => p.id == userId)
            .firstOrNull;
        if (existingPeer != null) {
          _dbService.addOrUpdatePeer(
            existingPeer.copyWith(
              deviceName: merged['displayName'] as String,
              profilePicBase64: merged['profilePicBase64'] as String?,
            ),
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

// ─── Typing Status (per room) ──────────────────────────────────────
final typingStatusProvider =
    StateNotifierProvider.family<
      TypingStatusNotifier,
      Map<String, bool>,
      String
    >((ref, roomId) {
      final chatService = ref.watch(chatServiceProvider);
      return TypingStatusNotifier(chatService, roomId);
    });

class TypingStatusNotifier extends StateNotifier<Map<String, bool>> {
  late final StreamSubscription _sub;

  TypingStatusNotifier(ChatService chatService, String roomId) : super({}) {
    _sub = chatService.typingStream.listen((data) {
      if (data['roomId'] == roomId) {
        final userId = data['userId'] as String;
        final isTyping = data['isTyping'] as bool;
        state = {...state, userId: isTyping};
      }
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

// ─── Chat Messages (per room) ──────────────────────────────────────
final chatMessagesProvider =
    StateNotifierProvider.family<
      ChatMessagesNotifier,
      List<ChatMessage>,
      String
    >((ref, roomId) {
      final dbService = ref.watch(databaseServiceProvider);
      final chatService = ref.watch(chatServiceProvider);
      final localUserId = ref.watch(localUserIdProvider);
      return ChatMessagesNotifier(dbService, chatService, roomId, localUserId);
    });

class ChatMessagesNotifier extends StateNotifier<List<ChatMessage>> {
  final DatabaseService _dbService;
  final ChatService _chatService;
  final String _roomId;
  final String _localUserId;
  late final StreamSubscription _messageSub;
  late final StreamSubscription _ackSub;
  late final StreamSubscription _readReceiptSub;
  late final StreamSubscription _reactionSub;

  ChatMessagesNotifier(
    this._dbService,
    this._chatService,
    this._roomId,
    this._localUserId,
  ) : super([]) {
    _loadFromHive();
    _listenToIncoming();
    _listenToReactions();
  }

  void _loadFromHive() {
    try {
      final cached = _dbService.getChatMessagesByRoomId(_roomId);

      // Validate all messages have correct roomId
      for (final msg in cached) {
        if (!msg.validateRoomId()) {
          AppLogger.error(
            'ChatMessages',
            'Invalid message room ID',
            'Expected: ${ChatMessage.deriveRoomId(msg.senderId, msg.receiverId)}, Got: ${msg.roomId}',
          );
          // Skip invalid messages
          continue;
        }
      }

      state = cached.where((msg) => msg.validateRoomId()).toList();
      AppLogger.info('ChatMessages', 'Loaded messages', {
        'roomId': _roomId,
        'count': state.length,
      });
    } catch (e) {
      AppLogger.error('ChatMessages', 'Error loading from Hive', e);
    }
  }

  void _listenToIncoming() {
    _messageSub = _chatService.messageStream.listen(
      (message) {
        try {
          // Validate message before adding
          if (!message.validateRoomId()) {
            AppLogger.warn(
              'ChatMessages',
              'Received message with invalid room ID',
              'Expected: ${ChatMessage.deriveRoomId(message.senderId, message.receiverId)}, Got: ${message.roomId}',
            );
            return;
          }

          if (message.roomId == _roomId) {
            // ChatService already saved it to dbService. Deduplicate room and
            // direct deliveries, which can occur during reconnection.
            if (state.every((existing) => existing.id != message.id)) {
              state = [...state, message];
            }
            AppLogger.debug('ChatMessages', 'Message added', {
              'messageId': message.id.substring(0, 8),
              'roomId': _roomId,
            });
          }
        } catch (e) {
          AppLogger.error(
            'ChatMessages',
            'Error processing incoming message',
            e,
          );
        }
      },
      onError: (error) {
        AppLogger.error('ChatMessages', 'Message stream error', error);
      },
    );

    _ackSub = _chatService.ackStream.listen((data) {
      final messageId = data['id'] as String;
      final status = data['status'] as String;
      final serverTs = data['serverTimestamp'] != null
          ? DateTime.parse(data['serverTimestamp'] as String)
          : null;

      // ChatService already updated dbService

      state = state.map((msg) {
        if (msg.id == messageId) {
          return msg.copyWith(status: status, serverTimestamp: serverTs);
        }
        return msg;
      }).toList();
    });

    _readReceiptSub = _chatService.readReceiptStream.listen((data) {
      if (data['roomId'] == _roomId) {
        final messageId = data['messageId'] as String;
        // ChatService already updated dbService
        state = state.map((msg) {
          if (msg.id == messageId) return msg.copyWith(status: 'read');
          return msg;
        }).toList();
      }
    });
  }

  Future<void> sendMessage(String text, String receiverId, {ChatMessage? replyTo}) async {
    final message = ChatMessage(
      id: const Uuid().v4(),
      roomId: _roomId,
      senderId: _localUserId,
      receiverId: receiverId,
      content: text,
      messageType: 'text',
      status: 'sending',
      timestamp: DateTime.now(),
      replyToMessageId: replyTo?.id,
      replyToContent: replyTo?.content,
      replyToSenderId: replyTo?.senderId,
    );

    await _dbService.addChatMessage(message);
    state = [...state, message];
    _chatService.sendMessage(message);
  }

  Future<void> markIncomingMessagesRead(String peerId) async {
    final unreadMessages = await _dbService.markIncomingMessagesRead(
      _roomId,
      _localUserId,
    );
    if (unreadMessages.isEmpty) return;

    final unreadIds = unreadMessages.map((message) => message.id).toSet();
    state = state
        .map((message) => unreadIds.contains(message.id)
            ? message.copyWith(status: 'read')
            : message)
        .toList();
    for (final message in unreadMessages) {
      _chatService.sendReadReceipt(_roomId, message.id);
    }
  }

  void _listenToReactions() {
    _reactionSub = _chatService.reactionStream.listen((data) {
      final messageId = data['messageId'] as String?;
      final emoji = data['emoji'] as String?;
      final senderId = data['senderId'] as String?;
      final action = data['action'] as String?;
      if (messageId == null || emoji == null || senderId == null || action == null) return;

      state = state.map((msg) {
        if (msg.id == messageId) {
          return msg.toggleReaction(senderId, emoji, action);
        }
        return msg;
      }).toList();
    });
  }

  void toggleReaction(String messageId, String emoji) {
    final message = state.firstWhere(
      (m) => m.id == messageId,
      orElse: () => throw Exception('Message not found'),
    );
    final hasReaction = (message.reactions[emoji] ?? []).contains(_localUserId);
    final action = hasReaction ? 'remove' : 'add';

    state = state.map((msg) {
      if (msg.id == messageId) {
        return msg.toggleReaction(_localUserId, emoji, action);
      }
      return msg;
    }).toList();

    final targetId = message.senderId == _localUserId ? message.receiverId : message.senderId;
    _chatService.sendReaction(
      targetId: targetId,
      messageId: messageId,
      emoji: emoji,
      action: action,
    );
  }

  Future<void> sendAttachment({
    required String receiverId,
    required String fileName,
    required String mimeType,
    required String base64Data,
    required int size,
  }) async {
    final message = ChatMessage(
      id: const Uuid().v4(),
      roomId: _roomId,
      senderId: _localUserId,
      receiverId: receiverId,
      content: fileName,
      messageType: _attachmentType(mimeType),
      fileName: fileName,
      mimeType: mimeType,
      attachmentBase64: base64Data,
      attachmentSize: size,
      status: 'sending',
      timestamp: DateTime.now(),
    );

    await _dbService.addChatMessage(message);
    state = [...state, message];
    _chatService.sendMessage(message);
  }

  static String _attachmentType(String mimeType) {
    if (mimeType.startsWith('image/')) return 'image';
    if (mimeType.startsWith('audio/')) return 'audio';
    if (mimeType.startsWith('video/')) return 'video';
    return 'file';
  }

  Future<void> clearMessages() async {
    await _dbService.deleteChatMessagesByRoomId(_roomId);
    state = [];
  }

  @override
  void dispose() {
    _messageSub.cancel();
    _ackSub.cancel();
    _readReceiptSub.cancel();
    _reactionSub.cancel();
    super.dispose();
  }
}

// ─── Dark Mode ─────────────────────────────────────────────────────
final darkModeProvider =
    StateNotifierProvider<DarkModeNotifier, bool>((ref) {
  final dbService = ref.watch(databaseServiceProvider);
  return DarkModeNotifier(dbService);
});

class DarkModeNotifier extends StateNotifier<bool> {
  final DatabaseService _dbService;
  DarkModeNotifier(this._dbService) : super(false) {
    _loadSaved();
    // Re-check after database finishes initializing (async)
    _pollForInit();
  }

  Future<void> _pollForInit() async {
    for (var i = 0; i < 50; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (_dbService.isInitialized) {
        _loadSaved();
        return;
      }
    }
  }

  void _loadSaved() {
    if (!_dbService.isInitialized) return;
    try {
      final saved = _dbService.settingsBox.get('dark_mode');
      state = saved == 'true';
    } catch (_) {
      state = false;
    }
  }

  void toggle() {
    state = !state;
    if (!_dbService.isInitialized) return;
    try {
      _dbService.settingsBox.put('dark_mode', state.toString());
    } catch (_) {}
  }
}

// ─── Conversation List ─────────────────────────────────────────────
final conversationListProvider =
    StateNotifierProvider<ConversationListNotifier, List<Map<String, dynamic>>>(
      (ref) {
        final dbService = ref.watch(databaseServiceProvider);
        final localUserId = ref.watch(localUserIdProvider);
        final chatService = ref.watch(chatServiceProvider);
        return ConversationListNotifier(dbService, localUserId, chatService);
      },
    );

class ConversationListNotifier
    extends StateNotifier<List<Map<String, dynamic>>> {
  final DatabaseService _dbService;
  final String _localUserId;
  late final StreamSubscription _messageSub;
  late final StreamSubscription _ackSub;

  ConversationListNotifier(
    this._dbService,
    this._localUserId,
    ChatService chatService,
  ) : super([]) {
    _loadFromHive();
    _messageSub = chatService.messageStream.listen((_) => _loadFromHive());
    _ackSub = chatService.ackStream.listen((_) => _loadFromHive());
  }

  void _loadFromHive() {
    state = _dbService.getConversationList(_localUserId);
  }

  void refresh() => _loadFromHive();

  @override
  void dispose() {
    _messageSub.cancel();
    _ackSub.cancel();
    super.dispose();
  }
}
