import 'dart:async';
import 'dart:io';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
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
  String? _storageBasePath;
  String? _activeStoragePath;

  String? get activeStoragePath => _activeStoragePath;
  Future<void> initializeBoxes({String? profileName}) async {
    _storageBasePath = await _resolveStorageBase(profileName);
    _activeStoragePath = _storageBasePath;
    await _ensureDirectory(_activeStoragePath!);

    const maxRetries = 5;
    var attempt = 0;
    var lastLockError = '';

    while (attempt < maxRetries) {
      attempt++;
      try {
        _peersBox = await _openBoxSafe<PeerModel>(peersBoxName, path: _activeStoragePath);
        _messagesBox = await _openBoxSafe<MessageModel>(messagesBoxName, path: _activeStoragePath);
        _chatMessagesBox = await _openBoxSafe<ChatMessage>(chatMessagesBoxName, path: _activeStoragePath);
        _profileBox = await _openBoxSafe<UserProfile>(profileBoxName, path: _activeStoragePath);
        _settingsBox = await _openBoxSafe<String>(settingsBoxName, path: _activeStoragePath);
        _groupsBox = await _openBoxSafe<Group>(groupsBoxName, path: _activeStoragePath);
        _initialized = true;

        return;
      } catch (e) {
        lastLockError = e.toString();

        await _closeAllOpenBoxes();
        if (attempt < maxRetries) {
          final delay = Duration(seconds: attempt);

          await Future.delayed(delay);
        }
      }
    }
    await _failOverToIsolatedStorage();
    attempt = 0;
    while (attempt < maxRetries) {
      attempt++;
      try {
        _peersBox = await _openBoxSafe<PeerModel>(peersBoxName, path: _activeStoragePath);
        _messagesBox = await _openBoxSafe<MessageModel>(messagesBoxName, path: _activeStoragePath);
        _chatMessagesBox = await _openBoxSafe<ChatMessage>(chatMessagesBoxName, path: _activeStoragePath);
        _profileBox = await _openBoxSafe<UserProfile>(profileBoxName, path: _activeStoragePath);
        _settingsBox = await _openBoxSafe<String>(settingsBoxName, path: _activeStoragePath);
        _groupsBox = await _openBoxSafe<Group>(groupsBoxName, path: _activeStoragePath);
        _initialized = true;
        return;
      } on FileSystemException catch (e) {

        await _closeAllOpenBoxes();
        if (attempt < maxRetries) {
          await Future.delayed(Duration(milliseconds: 500 * attempt));
        }
      }
    }

    throw Exception(
      'Failed to initialize database after $maxRetries attempts. '
      'Close other GryChat instances and try again.',
    );
  }
  Future<String> _resolveStorageBase(String? profileName) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final profile = (profileName ?? '').trim();
    if (profile.isEmpty || profile == 'main_peer') {
      return docsDir.path;
    }
    return '${docsDir.path}${Platform.pathSeparator}$profile';
  }

  Future<void> _ensureDirectory(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }
  Future<void> _failOverToIsolatedStorage() async {
    final isolatedPath =
        '${_storageBasePath}_isolated_${DateTime.now().millisecondsSinceEpoch}_$pid';
    _activeStoragePath = isolatedPath;
    await _ensureDirectory(isolatedPath);
  }
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

        } catch (_) {}
      }
    }
  }
  Future<Box<T>> _openBoxSafe<T>(String name, {String? path}) async {
    try {
      return await Hive.openBox<T>(name, path: path);
    } on FileSystemException {
      rethrow;
    } catch (e) {
      if (Hive.isBoxOpen(name)) {
        try {
          await Hive.box<T>(name).close();
        } catch (_) {}
      }
      try {
        await Hive.deleteBoxFromDisk(name, path: path);
        return await Hive.openBox<T>(name, path: path);
      } on FileSystemException {
        rethrow;
      } catch (_) {
        await _quarantineBoxFile(name, path: path);
        return await Hive.openBox<T>(name, path: path);
      }
    }
  }
  Future<void> _quarantineBoxFile(String name, {String? path}) async {
    final dir = path ?? _activeStoragePath;
    if (dir == null) return;
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final suffix = '.bak.$stamp';
    for (final ext in ['hive', 'lock']) {
      final file = File('$dir${Platform.pathSeparator}$name.$ext');
      try {
        if (await file.exists()) {
          await file.rename('$dir${Platform.pathSeparator}$name.$ext$suffix');

        }
      } catch (_) {}
    }
  }
  UserProfile? getUserProfile(String userId) {
    try {
      if (userId.isEmpty) return null;
      return _profileBox.get(userId);
    } catch (e) {

      return null;
    }
  }
  Future<void> saveUserProfile(UserProfile profile) async {
    try {
      if (profile.userId.isEmpty) {

      }
      await _profileBox.put(profile.userId.isNotEmpty ? profile.userId : 'user_profile', profile);

    } catch (e) {

      rethrow;
    }
  }
  Future<void> addOrUpdatePeer(PeerModel peer) async {
    try {
      await _peersBox.put(peer.id, peer);

    } catch (e) {

      rethrow;
    }
  }
  PeerModel? getPeerById(String peerId) {
    try {
      return _peersBox.get(peerId);
    } catch (e) {

      return null;
    }
  }
  List<PeerModel> getAllPeers() {
    try {
      return _peersBox.values.toList();
    } catch (e) {

      return [];
    }
  }
  Future<void> deletePeer(String peerId) async {
    try {
      await _peersBox.delete(peerId);

    } catch (e) {

      rethrow;
    }
  }
  Future<void> clearAllPeers() async {
    try {
      await _peersBox.clear();

    } catch (e) {

      rethrow;
    }
  }
  Future<void> addMessage(MessageModel message) async {
    try {
      await _messagesBox.put(message.id, message);

    } catch (e) {

      rethrow;
    }
  }
  Future<void> updateMessage(MessageModel message) async {
    try {
      await _messagesBox.put(message.id, message);

    } catch (e) {

      rethrow;
    }
  }
  MessageModel? getMessageById(String messageId) {
    try {
      return _messagesBox.get(messageId);
    } catch (e) {

      return null;
    }
  }
  List<MessageModel> getMessagesByPeerId(String peerId) {
    try {
      return _messagesBox.values
          .where((msg) => msg.peerId == peerId)
          .toList();
    } catch (e) {

      return [];
    }
  }
  List<MessageModel> getMessagesByPeerIdSorted(String peerId) {
    try {
      final messages = getMessagesByPeerId(peerId);
      messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return messages;
    } catch (e) {

      return [];
    }
  }
  Future<void> deleteMessage(String messageId) async {
    try {
      await _messagesBox.delete(messageId);

    } catch (e) {

      rethrow;
    }
  }
  Future<void> deleteMessagesByPeerId(String peerId) async {
    try {
      final keysToDelete = _messagesBox.keys
          .where((key) => _messagesBox.get(key)?.peerId == peerId)
          .toList();
      await _messagesBox.deleteAll(keysToDelete);

    } catch (e) {

      rethrow;
    }
  }
  Future<void> clearAllMessages() async {
    try {
      await _messagesBox.clear();

    } catch (e) {

      rethrow;
    }
  }
  Future<void> addChatMessage(ChatMessage message) async {
    try {
      await _chatMessagesBox.put(message.id, message);
    } catch (e) {

      rethrow;
    }
  }
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

      rethrow;
    }
  }
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
  ChatMessage? getChatMessageById(String messageId) {
    try {
      return _chatMessagesBox.get(messageId);
    } catch (e) {

      return null;
    }
  }
  List<ChatMessage> getChatMessagesByRoomId(String roomId) {
    try {
      final messages = _chatMessagesBox.values
          .where((msg) => msg.roomId == roomId)
          .toList();
      messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return messages;
    } catch (e) {

      return [];
    }
  }
  List<Map<String, dynamic>> getConversationList(String currentUserId) {
    try {
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
          'isGroup': lastMsg.groupId != null,
          'groupId': lastMsg.groupId,
        });
      }
      conversations.sort((a, b) {
        final aTime = (a['lastMessage'] as ChatMessage).timestamp;
        final bTime = (b['lastMessage'] as ChatMessage).timestamp;
        return bTime.compareTo(aTime);
      });

      return conversations;
    } catch (e) {

      return [];
    }
  }
  Future<void> deleteChatMessagesByRoomId(String roomId) async {
    try {
      final keysToDelete = _chatMessagesBox.keys
          .where((key) => _chatMessagesBox.get(key)?.roomId == roomId)
          .toList();
      await _chatMessagesBox.deleteAll(keysToDelete);

    } catch (e) {

      rethrow;
    }
  }
  Future<void> clearAllChatMessages() async {
    try {
      await _chatMessagesBox.clear();

    } catch (e) {

      rethrow;
    }
  }
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

      return {};
    }
  }

  Future<void> addGroup(Group group) async {
    try {
      await _groupsBox.put(group.id, group);
    } catch (e) {

      rethrow;
    }
  }

  Group? getGroupById(String groupId) {
    try {
      return _groupsBox.get(groupId);
    } catch (e) {

      return null;
    }
  }

  List<Group> getAllGroups() {
    try {
      return _groupsBox.values.toList();
    } catch (e) {

      return [];
    }
  }

  List<Group> getGroupsForUser(String userId) {
    try {
      return _groupsBox.values
          .where((g) => g.memberIds.contains(userId))
          .toList();
    } catch (e) {

      return [];
    }
  }

  Future<void> deleteGroup(String groupId) async {
    try {
      await _groupsBox.delete(groupId);
    } catch (e) {

      rethrow;
    }
  }

  List<ChatMessage> searchMessages(String query, String currentUserId) {
    try {
      final lowerQuery = query.toLowerCase();
      return _chatMessagesBox.values
          .where((msg) =>
              (msg.senderId == currentUserId ||
                  msg.receiverId == currentUserId) &&
              msg.content.toLowerCase().contains(lowerQuery))
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    } catch (e) {

      return [];
    }
  }

  List<ChatMessage> getFavoriteMessages(String currentUserId) {
    try {
      return _chatMessagesBox.values
          .where((msg) =>
              msg.isFavorite &&
              (msg.senderId == currentUserId || msg.receiverId == currentUserId))
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    } catch (e) {

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

      rethrow;
    }
  }

  Future<void> updateChatMessage(ChatMessage message) async {
    try {
      await _chatMessagesBox.put(message.id, message);
    } catch (e) {

      rethrow;
    }
  }
  Future<void> closeBoxes() async {
    try {
      await _peersBox.close();
      await _messagesBox.close();
      await _chatMessagesBox.close();
      await _profileBox.close();
      await _settingsBox.close();
      await _groupsBox.close();

    } catch (e) {

      rethrow;
    }
  }
}
