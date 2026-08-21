import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import '../../config/app_config.dart';
import '../../core/models/chat_message.dart';
import '../../core/models/group.dart';
import '../../core/database/models.dart';
import '../../core/providers/database_provider.dart';
import '../../core/providers/chat_provider.dart';
import '../../core/network/auth_service.dart';
import 'chat_screen.dart';
import 'group_chat_screen.dart';
import 'contacts_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final TextEditingController _shortCodeController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  String _searchQuery = '';
  StreamSubscription? _resolveSub;

  @override
  void dispose() {
    _shortCodeController.dispose();
    _searchController.dispose();
    _resolveSub?.cancel();
    super.dispose();
  }

  void _showNewChatDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                _buildActionTile(
                  icon: Icons.person_add_alt,
                  title: 'New Chat',
                  subtitle: 'Connect with a friend using their invite code',
                  onTap: () {
                    Navigator.pop(ctx);
                    _showShortCodeDialog();
                  },
                ),
                const SizedBox(height: 8),
                _buildActionTile(
                  icon: Icons.group_add,
                  title: 'Create Group',
                  subtitle: 'Start a group conversation',
                  onTap: () {
                    Navigator.pop(ctx);
                    _showCreateGroupDialog();
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xFFF4F6FA),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: Color(0xFF1B4EBA),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
            ],
          ),
        ),
      ),
    );
  }

  void _showShortCodeDialog() {
    _shortCodeController.clear();
    String? errorText;
    bool isSearching = false;
    List<Map<String, dynamic>> searchResults = [];

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(
                'New Chat',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Enter a username to find a friend',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _shortCodeController,
                    autofocus: true,
                    textCapitalization: TextCapitalization.none,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                    decoration: InputDecoration(
                      hintText: 'username',
                      hintStyle: TextStyle(
                        color: const Color(0xFFC4C8D3),
                        letterSpacing: 1,
                        fontWeight: FontWeight.normal,
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF4F6FA),
                      errorText: errorText,
                      prefixIcon: const Icon(
                        Icons.search,
                        color: Color(0xFF1B4EBA),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFF1B4EBA),
                          width: 1.5,
                        ),
                      ),
                    ),
                    onChanged: (v) {
                      setDialogState(() {
                        errorText = null;
                        searchResults = [];
                      });
                    },
                  ),
                  if (isSearching)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  if (searchResults.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Container(
                        constraints: const BoxConstraints(maxHeight: 250),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: searchResults.length,
                          itemBuilder: (context, index) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _buildUserCard(searchResults[index], ctx, setDialogState),
                            );
                          },
                        ),
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    _resolveSub?.cancel();
                    Navigator.pop(ctx);
                  },
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Color(0xFF7E8494)),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B4EBA),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: isSearching
                      ? null
                      : () {
                          final query = _shortCodeController.text.trim();
                          if (query.length < 2) {
                            setDialogState(
                              () => errorText = 'Enter a username (min 2 chars)',
                            );
                            return;
                          }
                          setDialogState(() {
                            isSearching = true;
                            errorText = null;
                            searchResults = [];
                          });
                          Future.delayed(const Duration(seconds: 8), () {
                            if (!ctx.mounted || !isSearching) return;
                            setDialogState(() {
                              isSearching = false;
                              errorText = 'Search timed out. Try again.';
                            });
                          });
                          _resolveSub?.cancel();
                          _resolveSub = ref
                              .read(chatServiceProvider)
                              .searchResultStream
                              .listen((results) {
                                _resolveSub?.cancel();
                                setDialogState(() {
                                  isSearching = false;
                                  searchResults = results;
                                  if (results.isEmpty) {
                                    errorText = 'No users found with that username.';
                                  }
                                });
                              });
                          ref.read(chatServiceProvider).searchUsers(query);
                        },
                  child: const Text('Find'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user, BuildContext ctx, StateSetter setDialogState) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF1B4EBA).withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: Color(0xFF1B4EBA),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              (user['displayName'] as String? ?? '?').isNotEmpty
                  ? (user['displayName'] as String)[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user['displayName'] as String? ?? 'Unknown',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                Text(
                  '@${user['username'] as String? ?? user['email'] as String? ?? ''}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              final targetId = user['userId'] as String;
              _resolveSub?.cancel();
              Navigator.pop(ctx);
              final localUserId = ref.read(localUserIdProvider);
              final roomId = ChatMessage.deriveRoomId(localUserId, targetId);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ChatScreen(
                    peerId: targetId,
                    roomId: roomId,
                    peerName: user['displayName'] as String?,
                  ),
                ),
              );
            },
            child: const Icon(
              Icons.arrow_forward_ios,
              color: Color(0xFF1B4EBA),
              size: 18,
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateGroupDialog() {
    final groupNameController = TextEditingController();
    final Set<String> selectedMemberIds = {};

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final onlineUsers = ref.read(userPresenceProvider);
            final peers = ref.read(peersProvider);
            final localUserId = ref.read(localUserIdProvider);
            final candidates = <Map<String, dynamic>>[];

            for (final entry in onlineUsers.entries) {
              if (entry.key == localUserId) continue;
              candidates.add({
                'userId': entry.key,
                'displayName':
                    entry.value['displayName'] ?? entry.key.substring(0, 8),
              });
            }
            for (final peer in peers) {
              if (peer.id == localUserId) continue;
              if (candidates.any((c) => c['userId'] == peer.id)) continue;
              candidates.add({
                'userId': peer.id,
                'displayName': peer.deviceName,
              });
            }

            return AlertDialog(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(
                'Create Group',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: groupNameController,
                      decoration: const InputDecoration(
                        labelText: 'Group Name',
                        hintText: 'e.g., Project Team',
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (candidates.isEmpty)
                      const Text(
                        'No online contacts to add',
                        style: TextStyle(color: Color(0xFF7E8494)),
                      )
                    else
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: candidates.length,
                          itemBuilder: (context, index) {
                            final c = candidates[index];
                            final isSelected = selectedMemberIds.contains(
                              c['userId'],
                            );
                            return CheckboxListTile(
                              value: isSelected,
                              onChanged: (val) {
                                setDialogState(() {
                                  if (isSelected) {
                                    selectedMemberIds.remove(c['userId']);
                                  } else {
                                    selectedMemberIds.add(c['userId']);
                                  }
                                });
                              },
                              title: Text(c['displayName'] as String),
                              secondary: CircleAvatar(
                                child: Text((c['displayName'] as String)[0]),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Color(0xFF7E8494)),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B4EBA),
                    foregroundColor: Colors.white,
                  ),
                  onPressed:
                      selectedMemberIds.isEmpty ||
                          groupNameController.text.trim().isEmpty
                      ? null
                      : () {
                          final groupId = const Uuid().v4();
                          final groupName = groupNameController.text.trim();
                          final memberIds = selectedMemberIds.toList();

                          final newGroup = Group(
                            id: groupId,
                            name: groupName,
                            creatorId: localUserId,
                            memberIds: [localUserId, ...memberIds],
                            createdAt: DateTime.now(),
                          );

                          ref
                              .read(groupsProvider.notifier)
                              .createGroup(
                                groupId: groupId,
                                groupName: groupName,
                                memberIds: memberIds,
                              );
                          final dbService = ref.read(databaseServiceProvider);
                          dbService.addGroup(newGroup);
                          Navigator.pop(ctx);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => GroupChatScreen(group: newGroup),
                            ),
                          );
                        },
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showSettingsModal(UserProfile userProfile) {
    final fNameController = TextEditingController(text: userProfile.firstName);
    final lNameController = TextEditingController(text: userProfile.lastName);
    String? currentBase64 = userProfile.profilePicBase64;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SingleChildScrollView(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                top: 24,
                left: 24,
                right: 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Edit Profile',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: Stack(
                      children: [
                        _buildAvatar(
                          '${fNameController.text} ${lNameController.text}',
                          null,
                          currentBase64,
                          size: 80,
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: GestureDetector(
                            onTap: () async {
                              final result = await FilePicker.pickFiles(
                                type: FileType.image,
                              );
                              if (result != null) {
                                final file = result.files.single;
                                final bytes = file.path != null
                                    ? await File(file.path!).readAsBytes()
                                    : await file.readAsBytes();
                                setModalState(() {
                                  currentBase64 = base64Encode(bytes);
                                });
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: Color(0xFF1B4EBA),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.camera_alt,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: fNameController,
                    decoration: const InputDecoration(labelText: 'First Name'),
                    onChanged: (v) => setModalState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: lNameController,
                    decoration: const InputDecoration(labelText: 'Last Name'),
                    onChanged: (v) => setModalState(() {}),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  _buildSettingTile(
                    icon: Icons.alternate_email,
                    title: 'Change Username',
                    subtitle: userProfile.username != null ? '@${userProfile.username}' : 'Not set',
                    onTap: () => _showChangeUsernameDialog(context, userProfile, setModalState),
                  ),
                  const SizedBox(height: 4),
                  _buildSettingTile(
                    icon: Icons.email_outlined,
                    title: 'Change Email',
                    subtitle: authService.currentEmail ?? 'Not set',
                    onTap: () => _showChangeEmailDialog(context),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B4EBA),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    onPressed: () async {
                      final newProfile = userProfile.copyWith(
                        firstName: fNameController.text.trim(),
                        lastName: lNameController.text.trim(),
                        profilePicBase64: currentBase64,
                      );
                      await ref
                          .read(userProfileProvider.notifier)
                          .saveProfile(newProfile);
                      ref.read(chatServiceProvider).updateProfilePresence();
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Profile updated successfully'),
                          ),
                        );
                      }
                    },
                    child: const Text('Save Changes'),
                  ),
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: () async {
                      await ref
                          .read(userProfileProvider.notifier)
                          .clearProfile();
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: const Text(
                      'Log Out / Reset Profile',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF1B4EBA).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: const Color(0xFF1B4EBA), size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurface,
          fontSize: 15,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
          fontSize: 13,
        ),
      ),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
    );
  }

  void _showChangeUsernameDialog(BuildContext context, UserProfile userProfile, StateSetter setModalState) {
    final controller = TextEditingController(text: userProfile.username ?? '');
    bool isChecking = false;
    bool isAvailable = false;
    bool isChecked = false;
    String? errorText;
    List<String> suggestions = [];

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text('Change Username', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: controller,
                    textCapitalization: TextCapitalization.none,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                    decoration: InputDecoration(
                      hintText: 'New username',
                      prefixIcon: const Icon(Icons.alternate_email, color: Color(0xFF1B4EBA)),
                      suffixIcon: isChecking
                          ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                          : isChecked
                              ? Icon(isAvailable ? Icons.check_circle : Icons.cancel, color: isAvailable ? Colors.green : Colors.redAccent)
                              : null,
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surface,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1B4EBA), width: 1.5)),
                    ),
                    onChanged: (v) async {
                      if (v.length < 3) {
                        setDialogState(() { isChecking = false; isChecked = false; isAvailable = false; errorText = null; suggestions = []; });
                        return;
                      }
                      setDialogState(() { isChecking = true; errorText = null; suggestions = []; });
                      await Future.delayed(const Duration(milliseconds: 500));
                      try {
                        final url = '${AppConfig.backendUrl}/api/check-username/$v';
                        final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
                        if (response.statusCode == 200 && ctx.mounted) {
                          final result = jsonDecode(response.body);
                          setDialogState(() {
                            isChecking = false;
                            isChecked = true;
                            isAvailable = result['available'] == true;
                            suggestions = List<String>.from(result['suggestions'] ?? []);
                            errorText = isAvailable ? null : (suggestions.isEmpty ? 'Username is taken' : null);
                          });
                        }
                      } catch (_) {
                        if (ctx.mounted) setDialogState(() { isChecking = false; isChecked = false; });
                      }
                    },
                  ),
                  if (errorText != null && !isChecking)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(errorText!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                          if (suggestions.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: suggestions.map((s) => GestureDetector(
                                onTap: () => controller.text = s,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1B4EBA).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(s, style: const TextStyle(color: Color(0xFF1B4EBA), fontSize: 12)),
                                ),
                              )).toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel', style: TextStyle(color: Color(0xFF7E8494))),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B4EBA),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: (!isAvailable || isChecking) ? null : () async {
                    final newUsername = controller.text.trim().toLowerCase();
                    setDialogState(() { isChecking = true; });
                    try {
                      final token = await authService.accessToken;
                      final response = await http.post(
                        Uri.parse('${AppConfig.backendUrl}/api/update-username'),
                        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
                        body: jsonEncode({'username': newUsername}),
                      ).timeout(const Duration(seconds: 10));
                      final result = jsonDecode(response.body);
                      if (response.statusCode == 200 && result['success'] == true) {
                        final updatedProfile = userProfile.copyWith(username: newUsername);
                        await ref.read(userProfileProvider.notifier).saveProfile(updatedProfile);
                        ref.read(chatServiceProvider).updateProfilePresence();
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Username updated successfully')),
                          );
                          setModalState(() {});
                        }
                      } else {
                        if (ctx.mounted) {
                          setDialogState(() {
                            isChecking = false;
                            errorText = result['error'] ?? 'Failed to update username';
                          });
                        }
                      }
                    } catch (e) {
                      if (ctx.mounted) setDialogState(() { isChecking = false; errorText = 'Network error'; });
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showChangeEmailDialog(BuildContext context) {
    final controller = TextEditingController();
    bool isSending = false;
    bool emailSent = false;
    String? errorText;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text('Change Email', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!emailSent) ...[
                    Text(
                      'A verification link will be sent to your new email address. After verifying, your email will be updated.',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 13),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: controller,
                      keyboardType: TextInputType.emailAddress,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                      decoration: InputDecoration(
                        hintText: 'New email address',
                        prefixIcon: const Icon(Icons.email_outlined, color: Color(0xFF1B4EBA)),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surface,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1B4EBA), width: 1.5)),
                      ),
                    ),
                  ] else ...[
                    const Icon(Icons.mark_email_read, color: Color(0xFF1B4EBA), size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'Verification email sent to:',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      controller.text,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Click the verification link in the email, then come back and tap "Confirm Update" below.',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 13),
                    ),
                  ],
                  if (errorText != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(errorText!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel', style: TextStyle(color: Color(0xFF7E8494))),
                ),
                if (!emailSent)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B4EBA),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: isSending ? null : () async {
                      final newEmail = controller.text.trim();
                      if (!newEmail.contains('@') || !newEmail.contains('.')) {
                        setDialogState(() => errorText = 'Please enter a valid email');
                        return;
                      }
                      setDialogState(() { isSending = true; errorText = null; });
                      try {
                        await authService.sendEmailVerification(newEmail);
                        setDialogState(() { isSending = false; emailSent = true; errorText = null; });
                      } catch (e) {
                        setDialogState(() {
                          isSending = false;
                          errorText = e.toString().contains('recently')
                              ? 'Please wait before requesting another verification email'
                              : 'Failed to send verification: ${e.toString().split('\n').first}';
                        });
                      }
                    },
                    child: isSending
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Send Verification'),
                  )
                else
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B4EBA),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: isSending ? null : () async {
                      setDialogState(() { isSending = true; errorText = null; });
                      try {
                        await authService.confirmEmailUpdate();
                        final newEmail = controller.text.trim();
                        final token = await authService.accessToken;
                        await http.post(
                          Uri.parse('${AppConfig.backendUrl}/api/update-email'),
                          headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
                          body: jsonEncode({'newEmail': newEmail}),
                        ).timeout(const Duration(seconds: 10));
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Email updated successfully')),
                          );
                        }
                      } catch (e) {
                        setDialogState(() {
                          isSending = false;
                          errorText = e.toString().contains('not yet verified')
                              ? 'Email not yet verified. Please check your inbox and click the link first.'
                              : 'Failed to confirm: ${e.toString().split('\n').first}';
                        });
                      }
                    },
                    child: isSending
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Confirm Update'),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildAvatar(
    String name,
    String? pathOrUrl,
    String? base64Str, {
    double size = 48,
  }) {
    if (base64Str != null && base64Str.isNotEmpty) {
      try {
        final bytes = base64Decode(base64Str);
        return ClipRRect(
          borderRadius: BorderRadius.circular(size / 2),
          child: Image.memory(
            bytes,
            width: size,
            height: size,
            fit: BoxFit.cover,
          ),
        );
      } catch (_) {}
    }

    if (pathOrUrl != null && pathOrUrl.isNotEmpty) {
      if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(size / 2),
          child: Image.network(
            pathOrUrl,
            width: size,
            height: size,
            fit: BoxFit.cover,
          ),
        );
      } else {
        final file = File(pathOrUrl);
        if (file.existsSync()) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(size / 2),
            child: Image.file(
              file,
              width: size,
              height: size,
              fit: BoxFit.cover,
            ),
          );
        }
      }
    }
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final colors = [
      const Color(0xFF1B4EBA),
      const Color(0xFF10B981),
      const Color(0xFFF59E0B),
      const Color(0xFFEF4444),
      const Color(0xFF8B5CF6),
      const Color(0xFFEC4899),
    ];
    final color = colors[name.hashCode % colors.length];

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.45,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localUserId = ref.watch(localUserIdProvider);
    final myShortCode = ref.watch(myShortCodeProvider);
    final conversations = ref.watch(conversationListProvider);
    final chatConnected = ref.watch(chatConnectionProvider);
    final userProfile = ref.watch(userProfileProvider);
    final presenceMap = ref.watch(userPresenceProvider);
    final peers = ref.watch(peersProvider);
    final groups = ref.watch(groupsProvider);

    final userName = userProfile != null
        ? '${userProfile.firstName} ${userProfile.lastName}'
        : 'User';
    final filteredConversations = conversations.where((conv) {
      if (_searchQuery.isEmpty) return true;
      final query = _searchQuery.toLowerCase();
      final peerId = conv['peerId'] as String;
      final lastMsg = conv['lastMessage'] as ChatMessage;
      final peerMatch = peers.where((p) => p.id == peerId);
      final peerName = peerMatch.isNotEmpty
          ? peerMatch.first.deviceName
          : peerId;

      return peerName.toLowerCase().contains(query) ||
          lastMsg.content.toLowerCase().contains(query) ||
          peerId.toLowerCase().contains(query);
    }).toList();
    final filteredGroups = groups.where((group) {
      if (_searchQuery.isEmpty) return true;
      return group.name.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B4EBA),
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                cursorColor: Colors.white,
                decoration: const InputDecoration(
                  hintText: 'Search chats...',
                  hintStyle: TextStyle(color: Colors.white54),
                  border: InputBorder.none,
                ),
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val;
                  });
                },
              )
            : const Text(
                'Grychat',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  fontSize: 20,
                ),
              ),
        actions: [
          IconButton(
            icon: Icon(
              _isSearching ? Icons.close : Icons.search,
              color: Colors.white,
            ),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _searchQuery = '';
                  _searchController.clear();
                }
                _isSearching = !_isSearching;
              });
            },
          ),
        ],
      ),
      drawer: Drawer(
        width: MediaQuery.of(context).size.width,
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Container(
                color: const Color(0xFF1B4EBA),
                child: SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 12.0,
                        ),
                        child: InkWell(
                          onTap: () {
                            Navigator.pop(context);
                            _showSettingsModal(
                              userProfile ?? UserProfile(
                                firstName: '',
                                lastName: '',
                                phoneNumber: '',
                                userId: localUserId,
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Row(
                              children: [
                                _buildAvatar(
                                  userName,
                                  userProfile?.profilePicPath,
                                  userProfile?.profilePicBase64,
                                  size: 50,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        userName,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      const Text(
                                        'Tap to edit profile',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.edit,
                                  color: Colors.white54,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const Divider(color: Colors.white12, thickness: 1),
                      Expanded(
                        child: Material(
                          color: const Color(0xFF1B4EBA),
                          child: ListView(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            children: [
                              _buildDrawerItem(Icons.home_outlined, 'Home', () {
                                Navigator.pop(context);
                              }),
                              _buildDrawerItem(
                                Icons.bookmark_border_outlined,
                                'Saved Messages',
                                () {
                                  Navigator.pop(context);
                                  final roomId = ChatMessage.deriveRoomId(
                                    localUserId,
                                    localUserId,
                                  );
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ChatScreen(
                                        peerId: localUserId,
                                        roomId: roomId,
                                      ),
                                    ),
                                  );
                                },
                              ),
                              _buildDrawerItem(
                                Icons.contacts_outlined,
                                'Contacts',
                                () {
                                  Navigator.pop(context);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const ContactsScreen(),
                                    ),
                                  );
                                },
                              ),
                              _buildDrawerItem(
                                Icons.person_add_alt_1_outlined,
                                'Invite Friends',
                                () {
                                  Navigator.pop(context);
                                  Clipboard.setData(
                                    ClipboardData(text: myShortCode),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Copied $myShortCode — share with friends!',
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const Divider(
                                color: Colors.white12,
                                thickness: 1,
                              ),
                              _buildDrawerItem(
                                Icons.settings_outlined,
                                'Settings',
                                () {
                                  Navigator.pop(context);
                                  _showSettingsModal(
                                    userProfile ?? UserProfile(
                                      firstName: '',
                                      lastName: '',
                                      phoneNumber: '',
                                      userId: localUserId,
                                    ),
                                  );
                                },
                              ),
                              _buildDarkModeToggle(),
                              const Divider(
                                color: Colors.white12,
                                thickness: 1,
                              ),
                              _buildDrawerItem(Icons.logout, 'Sign Out', () {
                                Navigator.pop(context);
                                authService.signOut();
                              }),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 1,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.5),
                  child: SafeArea(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(height: 16),
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 28,
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const SizedBox(height: 8),
                        const RotatedBox(
                          quarterTurns: 0,
                          child: Text(
                            'Grychat',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
            color: chatConnected
                ? const Color(0xFF10B981).withValues(alpha: 0.1)
                : const Color(0xFFEF4444).withValues(alpha: 0.1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  chatConnected ? Icons.cloud_done : Icons.cloud_off,
                  color: chatConnected
                      ? const Color(0xFF10B981)
                      : const Color(0xFFEF4444),
                  size: 13,
                ),
                const SizedBox(width: 6),
                Text(
                  chatConnected
                      ? 'Chat Server Connected'
                      : 'Connecting to server...',
                  style: TextStyle(
                    color: chatConnected
                        ? const Color(0xFF10B981)
                        : const Color(0xFFEF4444),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: filteredConversations.isEmpty && filteredGroups.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 54,
                          color: const Color(0xFF1B4EBA).withValues(alpha: 0.2),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No conversations yet',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _showNewChatDialog,
                          child: const Text(
                            'Start a New Chat',
                            style: TextStyle(
                              color: Color(0xFF1B4EBA),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: filteredGroups.length + filteredConversations.length,
                    separatorBuilder: (context, index) => const Divider(
                      height: 1,
                      indent: 84,
                      color: Color(0xFFF1F3F7),
                    ),
                    itemBuilder: (context, index) {
                      if (index < filteredGroups.length) {
                        final group = filteredGroups[index];
                        return _buildGroupTile(group);
                      }

                      final convIndex = index - filteredGroups.length;
                      final conv = filteredConversations[convIndex];
                      final roomId = conv['roomId'] as String;
                      final peerId = conv['peerId'] as String;
                      final lastMsg = conv['lastMessage'] as ChatMessage;
                      final unreadCount = conv['unreadCount'] as int;
                      final presenceData = presenceMap[peerId];
                      final peerMatch = peers.where((p) => p.id == peerId);
                      final peerName =
                          presenceData?['displayName'] as String? ??
                          (peerMatch.isNotEmpty
                              ? peerMatch.first.deviceName
                              : 'User ${peerId.length >= 8 ? peerId.substring(0, 8) : peerId}');
                      final peerPic =
                          presenceData?['profilePicBase64'] as String? ??
                          (peerMatch.isNotEmpty
                              ? peerMatch.first.profilePicBase64
                              : null);
                      final presence = presenceMap[peerId];
                      final isOnline =
                          presence != null && presence['status'] == 'online';
                      final subtext = lastMsg.senderId == localUserId
                          ? 'You: ${lastMsg.content}'
                          : lastMsg.content;
                      final timeText = DateFormat(
                        'hh:mm a',
                      ).format(lastMsg.timestamp);

                      return ListTile(
                        leading: Stack(
                          children: [
                            _buildAvatar(peerName, null, peerPic),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: isOnline
                                      ? const Color(0xFF10B981)
                                      : Colors.grey,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        title: Text(
                          peerName,
                          style: TextStyle(
                            color: const Color(0xFF171B24),
                            fontWeight: unreadCount > 0
                                ? FontWeight.w800
                                : FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        subtitle: Text(
                          subtext,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: unreadCount > 0
                                ? const Color(0xFF171B24)
                                : const Color(0xFF7E8494),
                            fontSize: 13,
                            fontWeight: unreadCount > 0
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              timeText,
                              style: TextStyle(
                                color: unreadCount > 0
                                    ? const Color(0xFF1B4EBA)
                                    : const Color(0xFFB0B5C1),
                                fontSize: 11,
                                fontWeight: unreadCount > 0
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            if (unreadCount > 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1B4EBA),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    unreadCount > 99 ? '99+' : '$unreadCount',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  ChatScreen(peerId: peerId, roomId: roomId),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF1B4EBA),
        foregroundColor: Colors.white,
        shape: const CircleBorder(),
        onPressed: _showNewChatDialog,
        child: const Icon(Icons.edit, size: 24),
      ),
    );
  }

  Widget _buildDarkModeToggle() {
    final isDark = ref.watch(darkModeProvider);
    return ListTile(
      leading: Icon(
        isDark ? Icons.dark_mode : Icons.light_mode,
        color: Colors.white.withValues(alpha: 0.85),
        size: 22,
      ),
      title: Text(
        isDark ? 'Dark Mode' : 'Light Mode',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: Switch(
        value: isDark,
        onChanged: (val) => ref.read(darkModeProvider.notifier).toggle(),
        activeThumbColor: Colors.white,
      ),
      onTap: () => ref.read(darkModeProvider.notifier).toggle(),
    );
  }

  Widget _buildDrawerItem(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(
        icon,
        color: Colors.white.withValues(alpha: 0.85),
        size: 22,
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
      horizontalTitleGap: 0,
      dense: true,
      onTap: onTap,
    );
  }

  Widget _buildGroupTile(Group group) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        radius: 26,
        backgroundColor: const Color(0xFF1B4EBA).withValues(alpha: 0.15),
        child: Text(
          group.name[0].toUpperCase(),
          style: const TextStyle(
            color: Color(0xFF1B4EBA),
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      title: Text(
        group.name,
        style: TextStyle(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
      subtitle: Text(
        '${group.memberIds.length} members',
        style: TextStyle(
          color: colorScheme.onSurface.withValues(alpha: 0.6),
          fontSize: 13,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: colorScheme.onSurface.withValues(alpha: 0.4),
      ),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => GroupChatScreen(group: group),
          ),
        );
      },
    );
  }
}
