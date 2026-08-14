import 'dart:async';
import 'dart:io';
import 'package:hive_flutter/hive_flutter.dart';
import 'models.dart';
import '../models/chat_message.dart';
import '../models/group.dart';

class DatabaseService {
  static const String peersBoxName = 'peers';
  static const String messagesBoxName = 'messages';
  static const String chatMessagesBoxName = 'chat_messages';
  static const String profileBoxName = 'profile';
  static const String settingsBoxName = 'settings';
  static const String groupsBoxName = 'groups';

  late Box<PeerModel> _peersBox;
  late Box<MessageModel> _messagesBox;
  late Box<ChatMessage> _chatMessagesBox;
  late Box<UserProfile> _profileBox;
  late Box<String> _settingsBox;
  late Box<Group> _groupsBox;

  bool _initialized = false;
  bool get isInitialized => _initialized;

  Box<PeerModel> get peersBox => _peersBox;
  Box<MessageModel> get messagesBox => _messagesBox;
  Box<ChatMessage> get chatMessagesBox => _chatMessagesBox;
  Box<UserProfile> get profileBox => _profileBox;
  Box<String> get settingsBox => _settingsBox;
  Box<Group> get groupsBox => _groupsBox;

  /// Initialize Hive boxes for peers, messages, chat messages, profile, and settings.
  /// Retries on file-lock errors, deletes and recreates on corruption.
  Future<void> initializeBoxes() async {
    const maxRetries = 5;
    var attempt = 0;

    while (attempt < maxRetries) {
      attempt++;
      try {
        _peersBox = await _openBoxSafe<PeerModel>(peersBoxName);
        _messagesBox = await _openBoxSafe<MessageModel>(messagesBoxName);
        _chatMessagesBox = await _openBoxSafe<ChatMessage>(chatMessagesBoxName);
        _profileBox = await _openBoxSafe<UserProfile>(profileBoxName);
        _settingsBox = await _openBoxSafe<String>(settingsBoxName);
        _groupsBox = await _openBoxSafe<Group>(groupsBoxName);
        _initialized = true;
        print('[DatabaseService] Boxes initialized successfully');
        return;
      } on FileSystemException catch (e) {
        // File lock (errno 32 on Windows) — close everything, wait, and retry
        print('[DatabaseService] File lock on attempt $attempt: $e');
        await _closeAllOpenBoxes();
        if (attempt < maxRetries) {
          final delay = Duration(seconds: attempt);
          print('[DatabaseService] Retrying in ${delay.inSeconds}s...');
          await Future.delayed(delay);
        }
      } catch (e) {
        print('[DatabaseService] FATAL error initializing boxes: $e');
        rethrow;
      }
    }
    throw Exception(
      'Failed to initialize database after $maxRetries attempts. '
      'Close other GryChat instances and try again.',
    );
  }

  /// Close all boxes that are currently open.
  Future<void> _closeAllOpenBoxes() async {
    for (final name in [
      peersBoxName,
      messagesBoxName,
      chatMessagesBoxName,
      profileBoxName,
      settingsBoxName,
      groupsBoxName,
    ]) {
      if (Hive.isBoxOpen(name)) {
        try {
          await Hive.box(name).close();
          print('[DatabaseService] Closed box: $name');
        } catch (_) {}
      }
    }
  }

  /// Open a Hive box with smart error recovery.
  /// - File lock (PathException): lets the caller retry.
  /// - Corruption (HiveError / unknown typeId): deletes and recreates.
  Future<Box<T>> _openBoxSafe<T>(String name) async {
    try {
      return await Hive.openBox<T>(name);
    } on FileSystemException {
      // Re-throw file-lock errors so initializeBoxes can retry
      rethrow;
    } catch (e) {
      // Corruption or unknown typeId — delete and recreate
      print('[DatabaseService] Box "$name" corrupted, recreating: $e');
      if (Hive.isBoxOpen(name)) {
        try {
          await Hive.box<T>(name).close();
        } catch (_) {}
      }
      await Hive.deleteBoxFromDisk(name);
      return await Hive.openBox<T>(name);
    }
  }

  /// Get the user profile for a specific userId (Firebase UID).
  /// Returns null if no profile exists for that user.
  UserProfile? getUserProfile(String userId) {
    try {
      if (userId.isEmpty) return null;
      return _profileBox.get(userId);
    } catch (e) {
      print('[DatabaseService] ERROR getting profile: $e');
      return null;
    }
  }

  /// Save user profile, keyed by the profile's userId.
  Future<void> saveUserProfile(UserProfile profile) async {
    try {
      if (profile.userId.isEmpty) {
        print('[DatabaseService] WARNING: saving profile with empty userId');
      }
      await _profileBox.put(profile.userId.isNotEmpty ? profile.userId : 'user_profile', profile);
      print('[DatabaseService] User profile saved/updated for userId=${profile.userId}: ${profile.firstName}');
    } catch (e) {
      print('[DatabaseService] ERROR saving profile: $e');
      rethrow;
    }
  }

  /// Add or update a peer
  Future<void> addOrUpdatePeer(PeerModel peer) async {
    try {
      await _peersBox.put(peer.id, peer);
      print('[DatabaseService] Peer added/updated: ${peer.deviceName}');
    } catch (e) {
      print('[DatabaseService] ERROR adding peer: $e');
      rethrow;
    }
  }

  /// Get a peer by ID
  PeerModel? getPeerById(String peerId) {
    try {
      return _peersBox.get(peerId);
    } catch (e) {
      print('[DatabaseService] ERROR getting peer: $e');
      return null;
    }
  }

  /// Get all peers
  List<PeerModel> getAllPeers() {
    try {
      return _peersBox.values.toList();
    } catch (e) {
      print('[DatabaseService] ERROR getting all peers: $e');
      return [];
    }
  }

  /// Delete a peer by ID
  Future<void> deletePeer(String peerId) async {
    try {
      await _peersBox.delete(peerId);
      print('[DatabaseService] Peer deleted: $peerId');
    } catch (e) {
      print('[DatabaseService] ERROR deleting peer: $e');
      rethrow;
    }
  }

  /// Clear all peers
  Future<void> clearAllPeers() async {
    try {
      await _peersBox.clear();
      print('[DatabaseService] All peers cleared');
    } catch (e) {
      print('[DatabaseService] ERROR clearing peers: $e');
      rethrow;
    }
  }

  /// Add a message
  Future<void> addMessage(MessageModel message) async {
    try {
      await _messagesBox.put(message.id, message);
      print('[DatabaseService] Message added: ${message.id}');
    } catch (e) {
      print('[DatabaseService] ERROR adding message: $e');
      rethrow;
    }
  }

  /// Update a message (for tracking progress)
  Future<void> updateMessage(MessageModel message) async {
    try {
      await _messagesBox.put(message.id, message);
      print('[DatabaseService] Message updated: ${message.id}');
    } catch (e) {
      print('[DatabaseService] ERROR updating message: $e');
      rethrow;
    }
  }

  /// Get a message by ID
  MessageModel? getMessageById(String messageId) {
    try {
      return _messagesBox.get(messageId);
    } catch (e) {
      print('[DatabaseService] ERROR getting message: $e');
      return null;
    }
  }

  /// Get all messages for a peer
  List<MessageModel> getMessagesByPeerId(String peerId) {
    try {
      return _messagesBox.values
          .where((msg) => msg.peerId == peerId)
          .toList();
    } catch (e) {
      print('[DatabaseService] ERROR getting messages: $e');
      return [];
    }
  }

  /// Get messages sorted by timestamp (newest first)
  List<MessageModel> getMessagesByPeerIdSorted(String peerId) {
    try {
      final messages = getMessagesByPeerId(peerId);
      messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return messages;
    } catch (e) {
      print('[DatabaseService] ERROR getting sorted messages: $e');
      return [];
    }
  }

  /// Delete a message by ID
  Future<void> deleteMessage(String messageId) async {
    try {
      await _messagesBox.delete(messageId);
      print('[DatabaseService] Message deleted: $messageId');
    } catch (e) {
      print('[DatabaseService] ERROR deleting message: $e');
      rethrow;
    }
  }

  /// Delete all messages for a peer
  Future<void> deleteMessagesByPeerId(String peerId) async {
    try {
      final keysToDelete = _messagesBox.keys
          .where((key) => _messagesBox.get(key)?.peerId == peerId)
          .toList();
      await _messagesBox.deleteAll(keysToDelete);
      print('[DatabaseService] All messages deleted for peer: $peerId');
    } catch (e) {
      print('[DatabaseService] ERROR deleting peer messages: $e');
      rethrow;
    }
  }

  /// Clear all messages
  Future<void> clearAllMessages() async {
    try {
      await _messagesBox.clear();
      print('[DatabaseService] All messages cleared');
    } catch (e) {
      print('[DatabaseService] ERROR clearing messages: $e');
      rethrow;
    }
  }

  // ─── ChatMessage CRUD ──────────────────────────────────────────────

  /// Add or update a chat message
  Future<void> addChatMessage(ChatMessage message) async {
    try {
      await _chatMessagesBox.put(message.id, message);
    } catch (e) {
      print('[DatabaseService] ERROR adding chat message: $e');
      rethrow;
    }
  }

  /// Update the status of an existing chat message (optimistic UI sync)
  Future<void> updateChatMessageStatus(String messageId, String status, {DateTime? serverTimestamp}) async {
    try {
      final existing = _chatMessagesBox.get(messageId);
      if (existing != null) {
        final updated = existing.copyWith(
          status: status,
          serverTimestamp: serverTimestamp,
        );
        await _chatMessagesBox.put(messageId, updated);
      }
    } catch (e) {
      print('[DatabaseService] ERROR updating chat message status: $e');
      rethrow;
    }
  }

  /// Marks incoming messages in a room as read for the current user.
  Future<List<ChatMessage>> markIncomingMessagesRead(
    String roomId,
    String currentUserId,
  ) async {
    final unreadMessages = _chatMessagesBox.values
        .where((message) =>
            message.roomId == roomId &&
            message.receiverId == currentUserId &&
            message.status != 'read')
        .toList();

    for (final message in unreadMessages) {
      await _chatMessagesBox.put(message.id, message.copyWith(status: 'read'));
    }
    return unreadMessages;
  }

  /// Get all chat messages for a room, sorted oldest → newest
  List<ChatMessage> getChatMessagesByRoomId(String roomId) {
    try {
      final messages = _chatMessagesBox.values
          .where((msg) => msg.roomId == roomId)
          .toList();
      messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return messages;
    } catch (e) {
      print('[DatabaseService] ERROR getting chat messages: $e');
      return [];
    }
  }

  /// Get a distinct list of conversations with the last message and unread count.
  /// Only returns conversations where [currentUserId] is a participant.
  /// Returns a list of maps: {roomId, peerId, lastMessage, unreadCount}
  List<Map<String, dynamic>> getConversationList(String currentUserId) {
    try {
      // ✅ CRITICAL: Only include messages where this user is sender OR receiver.
      // This prevents cross-user chat leakage when multiple profiles share a device.
      final myMessages = _chatMessagesBox.values
          .where((msg) =>
              msg.senderId == currentUserId || msg.receiverId == currentUserId)
          .toList();

      final Map<String, List<ChatMessage>> grouped = {};
      for (final msg in myMessages) {
        grouped.putIfAbsent(msg.roomId, () => []).add(msg);
      }

      final conversations = <Map<String, dynamic>>[];
      for (final entry in grouped.entries) {
        final msgs = entry.value..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        final lastMsg = msgs.first;
        // The "peer" is whoever ISN'T the current user in this room
        final peerId = lastMsg.senderId == currentUserId
            ? lastMsg.receiverId
            : lastMsg.senderId;
        final unreadCount = msgs.where((m) =>
            m.senderId != currentUserId &&
            m.status != 'read').length;
        conversations.add({
          'roomId': entry.key,
          'peerId': peerId,
          'lastMessage': lastMsg,
          'unreadCount': unreadCount,
        });
      }

      // Sort by last message timestamp (newest first)
      conversations.sort((a, b) {
        final aTime = (a['lastMessage'] as ChatMessage).timestamp;
        final bTime = (b['lastMessage'] as ChatMessage).timestamp;
        return bTime.compareTo(aTime);
      });

      return conversations;
    } catch (e) {
      print('[DatabaseService] ERROR getting conversation list: $e');
      return [];
    }
  }


  /// Delete all chat messages for a specific room
  Future<void> deleteChatMessagesByRoomId(String roomId) async {
    try {
      final keysToDelete = _chatMessagesBox.keys
          .where((key) => _chatMessagesBox.get(key)?.roomId == roomId)
          .toList();
      await _chatMessagesBox.deleteAll(keysToDelete);
      print('[DatabaseService] Chat messages cleared for room: $roomId');
    } catch (e) {
      print('[DatabaseService] ERROR deleting chat messages: $e');
      rethrow;
    }
  }

  /// Clear all chat messages
  Future<void> clearAllChatMessages() async {
    try {
      await _chatMessagesBox.clear();
      print('[DatabaseService] All chat messages cleared');
    } catch (e) {
      print('[DatabaseService] ERROR clearing chat messages: $e');
      rethrow;
    }
  }

  // ─── Stats ─────────────────────────────────────────────────────────

  /// Get box statistics
  Map<String, dynamic> getStats() {
    try {
      return {
        'peersCount': _peersBox.length,
        'messagesCount': _messagesBox.length,
        'chatMessagesCount': _chatMessagesBox.length,
        'onlinePeersCount': _peersBox.values.where((p) => p.isOnline).length,
        'groupsCount': _groupsBox.length,
      };
    } catch (e) {
      print('[DatabaseService] ERROR getting stats: $e');
      return {};
    }
  }

  // ─── Group CRUD ────────────────────────────────────────────────────

  Future<void> addGroup(Group group) async {
    try {
      await _groupsBox.put(group.id, group);
    } catch (e) {
      print('[DatabaseService] ERROR adding group: $e');
      rethrow;
    }
  }

  Group? getGroupById(String groupId) {
    try {
      return _groupsBox.get(groupId);
    } catch (e) {
      print('[DatabaseService] ERROR getting group: $e');
      return null;
    }
  }

  List<Group> getAllGroups() {
    try {
      return _groupsBox.values.toList();
    } catch (e) {
      print('[DatabaseService] ERROR getting all groups: $e');
      return [];
    }
  }

  List<Group> getGroupsForUser(String userId) {
    try {
      return _groupsBox.values
          .where((g) => g.memberIds.contains(userId))
          .toList();
    } catch (e) {
      print('[DatabaseService] ERROR getting user groups: $e');
      return [];
    }
  }

  Future<void> deleteGroup(String groupId) async {
    try {
      await _groupsBox.delete(groupId);
    } catch (e) {
      print('[DatabaseService] ERROR deleting group: $e');
      rethrow;
    }
  }

  // ─── Message Search ────────────────────────────────────────────────

  List<ChatMessage> searchMessages(String query, String currentUserId) {
    try {
      final lowerQuery = query.toLowerCase();
      return _chatMessagesBox.values
          .where((msg) =>
              (msg.senderId == currentUserId ||
                  msg.receiverId == currentUserId ||
                  (msg.groupId != null)) &&
              msg.content.toLowerCase().contains(lowerQuery))
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    } catch (e) {
      print('[DatabaseService] ERROR searching messages: $e');
      return [];
    }
  }

  // ─── Favorites ─────────────────────────────────────────────────────

  List<ChatMessage> getFavoriteMessages(String currentUserId) {
    try {
      return _chatMessagesBox.values
          .where((msg) =>
              msg.isFavorite &&
              (msg.senderId == currentUserId || msg.receiverId == currentUserId))
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    } catch (e) {
      print('[DatabaseService] ERROR getting favorites: $e');
      return [];
    }
  }

  Future<void> toggleFavorite(String messageId) async {
    try {
      final msg = _chatMessagesBox.get(messageId);
      if (msg != null) {
        await _chatMessagesBox.put(
            messageId, msg.copyWith(isFavorite: !msg.isFavorite));
      }
    } catch (e) {
      print('[DatabaseService] ERROR toggling favorite: $e');
      rethrow;
    }
  }

  // ─── Update a ChatMessage (general) ────────────────────────────────

  Future<void> updateChatMessage(ChatMessage message) async {
    try {
      await _chatMessagesBox.put(message.id, message);
    } catch (e) {
      print('[DatabaseService] ERROR updating chat message: $e');
      rethrow;
    }
  }

  /// Close all boxes
  Future<void> closeBoxes() async {
    try {
      await _peersBox.close();
      await _messagesBox.close();
      await _chatMessagesBox.close();
      await _profileBox.close();
      await _settingsBox.close();
      await _groupsBox.close();
      print('[DatabaseService] Boxes closed');
    } catch (e) {
      print('[DatabaseService] ERROR closing boxes: $e');
      rethrow;
    }
  }
}
