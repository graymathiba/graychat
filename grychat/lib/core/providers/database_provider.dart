import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../database/database_service.dart';
import '../database/models.dart';
final databaseServiceProvider = Provider<DatabaseService>((ref) {
  return DatabaseService();
});
final storageProfileProvider = Provider<String>((ref) => 'main_peer');
final databaseInitProvider = FutureProvider<void>((ref) async {
  final dbService = ref.watch(databaseServiceProvider);
  final profile = ref.watch(storageProfileProvider);
  await dbService.initializeBoxes(profileName: profile);
});
final peersProvider = StateNotifierProvider<PeersNotifier, List<PeerModel>>((ref) {
  final dbService = ref.watch(databaseServiceProvider);
  return PeersNotifier(dbService);
});
final messagesProvider = StateNotifierProvider.family<
    MessagesNotifier,
    List<MessageModel>,
    String>((ref, peerId) {
  final dbService = ref.watch(databaseServiceProvider);
  return MessagesNotifier(dbService, peerId);
});
final dbStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final dbService = ref.watch(databaseServiceProvider);
  await ref.watch(databaseInitProvider.future);
  return dbService.getStats();
});
final currentUserIdProvider = Provider<String>((ref) {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) return user.uid;
  } catch (_) {}
  return '';
});
final userProfileProvider =
    StateNotifierProvider<UserProfileNotifier, UserProfile?>((ref) {
  final dbService = ref.watch(databaseServiceProvider);
  final userId = ref.watch(currentUserIdProvider);
  final notifier = UserProfileNotifier(dbService, userId);
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
    } catch (e) {
      // best-effort: keep previous state on load failure
    }
  }

  Future<void> addOrUpdatePeer(PeerModel peer) async {
    try {
      await _dbService.addOrUpdatePeer(peer);
      _loadPeers();

    } catch (e) {

      rethrow;
    }
  }

  Future<void> deletePeer(String peerId) async {
    try {
      await _dbService.deletePeer(peerId);
      _loadPeers();

    } catch (e) {

      rethrow;
    }
  }

  Future<void> clearAllPeers() async {
    try {
      await _dbService.clearAllPeers();
      state = [];

    } catch (e) {

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
    } catch (e) {
      // best-effort: keep previous state on load failure
    }
  }

  Future<void> addMessage(MessageModel message) async {
    try {
      await _dbService.addMessage(message);
      _loadMessages();

    } catch (e) {

      rethrow;
    }
  }

  Future<void> updateMessage(MessageModel message) async {
    try {
      await _dbService.updateMessage(message);
      _loadMessages();

    } catch (e) {

      rethrow;
    }
  }

  Future<void> deleteMessage(String messageId) async {
    try {
      await _dbService.deleteMessage(messageId);
      _loadMessages();

    } catch (e) {

      rethrow;
    }
  }

  Future<void> clearAllMessages() async {
    try {
      await _dbService.deleteMessagesByPeerId(_peerId);
      state = [];

    } catch (e) {

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

    } catch (e) {

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

    } catch (e) {

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

        state = null;
        return;
      }
      final profile = _dbService.getUserProfile(_currentUserId);
      state = profile;
    } catch (e) {
      // best-effort: keep previous profile on load failure
    }
  }
  void onUserChanged(String userId) {
    if (userId == _currentUserId) return;
    _currentUserId = userId;
    _loadProfile();
  }

  Future<void> saveProfile(UserProfile profile) async {
    try {
      await _dbService.saveUserProfile(profile);
      state = profile;

    } catch (e) {

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

    } catch (e) {

      rethrow;
    }
  }
}