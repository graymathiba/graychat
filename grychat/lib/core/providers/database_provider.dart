import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../database/database_service.dart';
import '../database/models.dart';

// Singleton DatabaseService provider
final databaseServiceProvider = Provider<DatabaseService>((ref) {
  return DatabaseService();
});

// Initialize database boxes on app startup
final databaseInitProvider = FutureProvider<void>((ref) async {
  final dbService = ref.watch(databaseServiceProvider);
  await dbService.initializeBoxes();
});

// Get all peers (reactive)
final peersProvider = StateNotifierProvider<PeersNotifier, List<PeerModel>>((ref) {
  final dbService = ref.watch(databaseServiceProvider);
  return PeersNotifier(dbService);
});

// Get all messages for a specific peer (reactive)
final messagesProvider = StateNotifierProvider.family<
    MessagesNotifier,
    List<MessageModel>,
    String>((ref, peerId) {
  final dbService = ref.watch(databaseServiceProvider);
  return MessagesNotifier(dbService, peerId);
});

// Database statistics
final dbStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final dbService = ref.watch(databaseServiceProvider);
  await ref.watch(databaseInitProvider.future);
  return dbService.getStats();
});

// Current Firebase user ID (or empty for guests)
final currentUserIdProvider = Provider<String>((ref) {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) return user.uid;
  } catch (_) {}
  return '';
});

// User Profile provider — scoped to the current Firebase user
final userProfileProvider =
    StateNotifierProvider<UserProfileNotifier, UserProfile?>((ref) {
  final dbService = ref.watch(databaseServiceProvider);
  final userId = ref.watch(currentUserIdProvider);
  final notifier = UserProfileNotifier(dbService, userId);
  // React to auth changes: reload profile for new user
  ref.listen(currentUserIdProvider, (String? prev, String next) {
    notifier.onUserChanged(next);
  });
  return notifier;
});

class PeersNotifier extends StateNotifier<List<PeerModel>> {
  final DatabaseService _dbService;

  PeersNotifier(this._dbService) : super([]) {
    _loadPeers();
  }

  void _loadPeers() {
    try {
      final peers = _dbService.getAllPeers();
      state = peers;
      print('[PeersNotifier] Loaded ${peers.length} peers');
    } catch (e) {
      print('[PeersNotifier] ERROR loading peers: $e');
    }
  }

  Future<void> addOrUpdatePeer(PeerModel peer) async {
    try {
      await _dbService.addOrUpdatePeer(peer);
      _loadPeers();
      print('[PeersNotifier] Peer updated: ${peer.deviceName}');
    } catch (e) {
      print('[PeersNotifier] ERROR adding peer: $e');
      rethrow;
    }
  }

  Future<void> deletePeer(String peerId) async {
    try {
      await _dbService.deletePeer(peerId);
      _loadPeers();
      print('[PeersNotifier] Peer deleted: $peerId');
    } catch (e) {
      print('[PeersNotifier] ERROR deleting peer: $e');
      rethrow;
    }
  }

  Future<void> clearAllPeers() async {
    try {
      await _dbService.clearAllPeers();
      state = [];
      print('[PeersNotifier] All peers cleared');
    } catch (e) {
      print('[PeersNotifier] ERROR clearing peers: $e');
      rethrow;
    }
  }

  List<PeerModel> getOnlinePeers() {
    return state.where((peer) => peer.isOnline).toList();
  }

  List<PeerModel> getOfflinePeers() {
    return state.where((peer) => !peer.isOnline).toList();
  }
}

class MessagesNotifier extends StateNotifier<List<MessageModel>> {
  final DatabaseService _dbService;
  final String _peerId;

  MessagesNotifier(this._dbService, this._peerId) : super([]) {
    _loadMessages();
  }

  void _loadMessages() {
    try {
      final messages = _dbService.getMessagesByPeerIdSorted(_peerId);
      state = messages;
      print('[MessagesNotifier] Loaded ${messages.length} messages for peer: $_peerId');
    } catch (e) {
      print('[MessagesNotifier] ERROR loading messages: $e');
    }
  }

  Future<void> addMessage(MessageModel message) async {
    try {
      await _dbService.addMessage(message);
      _loadMessages();
      print('[MessagesNotifier] Message added: ${message.id}');
    } catch (e) {
      print('[MessagesNotifier] ERROR adding message: $e');
      rethrow;
    }
  }

  Future<void> updateMessage(MessageModel message) async {
    try {
      await _dbService.updateMessage(message);
      _loadMessages();
      print('[MessagesNotifier] Message updated: ${message.id}');
    } catch (e) {
      print('[MessagesNotifier] ERROR updating message: $e');
      rethrow;
    }
  }

  Future<void> deleteMessage(String messageId) async {
    try {
      await _dbService.deleteMessage(messageId);
      _loadMessages();
      print('[MessagesNotifier] Message deleted: $messageId');
    } catch (e) {
      print('[MessagesNotifier] ERROR deleting message: $e');
      rethrow;
    }
  }

  Future<void> clearAllMessages() async {
    try {
      await _dbService.deleteMessagesByPeerId(_peerId);
      state = [];
      print('[MessagesNotifier] All messages cleared for peer: $_peerId');
    } catch (e) {
      print('[MessagesNotifier] ERROR clearing messages: $e');
      rethrow;
    }
  }

  Future<void> sendMessage(String text) async {
    try {
      final message = MessageModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        peerId: _peerId,
        senderId: 'self',
        content: text,
        messageType: 'TEXT',
        timestamp: DateTime.now(),
        isTransferComplete: true,
      );
      await addMessage(message);
      print('[MessagesNotifier] Text message sent: ${message.id}');
    } catch (e) {
      print('[MessagesNotifier] ERROR sending message: $e');
      rethrow;
    }
  }

  Future<void> sendFile(String filePath) async {
    try {
      final fileName = filePath.split('/').last;
      final message = MessageModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        peerId: _peerId,
        senderId: 'self',
        content: fileName,
        messageType: 'FILE',
        timestamp: DateTime.now(),
        isTransferComplete: false,
      );
      await addMessage(message);
      print('[MessagesNotifier] File message sent: ${message.id}');
    } catch (e) {
      print('[MessagesNotifier] ERROR sending file: $e');
      rethrow;
    }
  }

  int getFileTransferCount() {
    return state.where((msg) => msg.messageType == 'FILE').length;
  }

  int getCompletedTransfersCount() {
    return state
        .where((msg) => msg.messageType == 'FILE' && msg.isTransferComplete)
        .length;
  }

  double getAverageTransferProgress() {
    final fileMessages = state.where((msg) => msg.messageType == 'FILE').toList();
    if (fileMessages.isEmpty) return 0.0;
    final totalProgress = fileMessages.fold<double>(
      0.0,
      (sum, msg) => sum + msg.calculatedProgress,
    );
    return totalProgress / fileMessages.length;
  }
}

class UserProfileNotifier extends StateNotifier<UserProfile?> {
  final DatabaseService _dbService;
  String _currentUserId;

  UserProfileNotifier(this._dbService, this._currentUserId) : super(null) {
    _loadProfile();
  }

  void _loadProfile() {
    try {
      if (_currentUserId.isEmpty) {
        print('[UserProfileNotifier] No user ID — skipping profile load');
        state = null;
        return;
      }
      final profile = _dbService.getUserProfile(_currentUserId);
      state = profile;
      if (profile != null) {
        print('[UserProfileNotifier] Loaded profile for user $_currentUserId: ${profile.firstName}');
      } else {
        print('[UserProfileNotifier] No profile found for user $_currentUserId');
      }
    } catch (e) {
      print('[UserProfileNotifier] ERROR loading profile: $e');
    }
  }

  /// Called when the Firebase auth user changes.
  void onUserChanged(String userId) {
    if (userId == _currentUserId) return;
    _currentUserId = userId;
    _loadProfile();
  }

  Future<void> saveProfile(UserProfile profile) async {
    try {
      await _dbService.saveUserProfile(profile);
      state = profile;
      print('[UserProfileNotifier] Profile saved: ${profile.firstName}');
    } catch (e) {
      print('[UserProfileNotifier] ERROR saving profile: $e');
      rethrow;
    }
  }

  Future<void> clearProfile() async {
    try {
      if (_currentUserId.isNotEmpty) {
        await _dbService.profileBox.delete(_currentUserId);
      } else {
        await _dbService.profileBox.clear();
      }
      state = null;
      print('[UserProfileNotifier] Profile cleared for user $_currentUserId');
    } catch (e) {
      print('[UserProfileNotifier] ERROR clearing profile: $e');
      rethrow;
    }
  }
}