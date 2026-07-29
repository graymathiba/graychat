import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/models/chat_message.dart';
import '../../core/models/group.dart';
import '../../core/database/models.dart';
import '../../core/providers/database_provider.dart';
import '../../core/providers/chat_provider.dart';
import '../../core/network/auth_service.dart';
import 'chat_screen.dart';
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
      backgroundColor: Colors.white,
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
                  width: 40, height: 4,
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
                width: 48, height: 48,
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
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Color(0xFF171B24),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(color: Color(0xFF7E8494), fontSize: 13),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF7E8494)),
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
    Map<String, dynamic>? resolvedUser;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text(
              'New Chat',
              style: TextStyle(color: Color(0xFF171B24), fontWeight: FontWeight.bold, fontSize: 18),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Enter a friend\'s invite code (e.g. GRY-4A2F)',
                  style: TextStyle(color: Color(0xFF7E8494), fontSize: 13),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _shortCodeController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(
                    color: Color(0xFF171B24),
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 4,
                  ),
                  decoration: InputDecoration(
                    hintText: 'GRY-????',
                    hintStyle: const TextStyle(color: Color(0xFFC4C8D3), letterSpacing: 4),
                    filled: true,
                    fillColor: const Color(0xFFF4F6FA),
                    errorText: errorText,
                    prefixIcon: const Icon(Icons.tag, color: Color(0xFF1B4EBA)),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF1B4EBA), width: 1.5),
                    ),
                  ),
                  onChanged: (v) {
                    setDialogState(() {
                      errorText = null;
                      resolvedUser = null;
                    });
                  },
                ),
                if (isSearching)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                if (resolvedUser != null && resolvedUser!['found'] == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F7FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF1B4EBA).withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36, height: 36,
                            decoration: const BoxDecoration(
                              color: Color(0xFF1B4EBA),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              (resolvedUser!['displayName'] as String? ?? '?')[0].toUpperCase(),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  resolvedUser!['displayName'] as String? ?? 'Unknown',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF171B24)),
                                ),
                                Text(
                                  resolvedUser!['shortCode'] as String? ?? '',
                                  style: const TextStyle(color: Color(0xFF7E8494), fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 20),
                        ],
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
                child: const Text('Cancel', style: TextStyle(color: Color(0xFF7E8494))),
              ),
              if (resolvedUser != null && resolvedUser!['found'] == true)
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B4EBA),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    final targetId = resolvedUser!['userId'] as String;
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
                          peerName: resolvedUser!['displayName'] as String?,
                        ),
                      ),
                    );
                  },
                  child: const Text('Chat'),
                )
              else
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B4EBA),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: isSearching
                      ? null
                      : () {
                          final code = _shortCodeController.text.trim().toUpperCase();
                          if (code.length < 4) {
                            setDialogState(() => errorText = 'Enter a valid GRY-XXXX code');
                            return;
                          }
                          setDialogState(() {
                            isSearching = true;
                            errorText = null;
                          });
                          Future<void>.delayed(const Duration(seconds: 5), () {
                            if (!ctx.mounted || !isSearching) return;
                            setDialogState(() {
                              isSearching = false;
                              errorText = 'Search timed out. Check the server connection and try again.';
                            });
                          });
                          _resolveSub?.cancel();
                          _resolveSub = ref
                              .read(chatServiceProvider)
                              .resolveResultStream
                              .listen((result) {
                            _resolveSub?.cancel();
                            setDialogState(() {
                              isSearching = false;
                              resolvedUser = result;
                              if (result['found'] == false) {
                                errorText = 'No user found with that code. Are they online?';
                              }
                            });
                          });
                          ref.read(chatServiceProvider).resolveShortCode(code);
                        },
                  child: const Text('Find'),
                ),
            ],
          );
        });
      },
    );
  }

  void _showCreateGroupDialog() {
    final groupNameController = TextEditingController();
    final Set<String> selectedMemberIds = {};

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setDialogState) {
          final onlineUsers = ref.read(userPresenceProvider);
          final peers = ref.read(peersProvider);
          final localUserId = ref.read(localUserIdProvider);
          final candidates = <Map<String, dynamic>>[];

          for (final entry in onlineUsers.entries) {
            if (entry.key == localUserId) continue;
            candidates.add({
              'userId': entry.key,
              'displayName': entry.value['displayName'] ?? entry.key.substring(0, 8),
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
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Create Group', style: TextStyle(color: Color(0xFF171B24), fontWeight: FontWeight.bold)),
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
                    const Text('No online contacts to add', style: TextStyle(color: Color(0xFF7E8494)))
                  else
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: candidates.length,
                        itemBuilder: (context, index) {
                          final c = candidates[index];
                          final isSelected = selectedMemberIds.contains(c['userId']);
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
                child: const Text('Cancel', style: TextStyle(color: Color(0xFF7E8494))),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B4EBA),
                  foregroundColor: Colors.white,
                ),
                onPressed: selectedMemberIds.isEmpty || groupNameController.text.trim().isEmpty
                    ? null
                    : () {
                        final groupId = const Uuid().v4();
                        final groupName = groupNameController.text.trim();
                        final memberIds = selectedMemberIds.toList();
                        ref.read(groupsProvider.notifier).createGroup(
                          groupId: groupId,
                          groupName: groupName,
                          memberIds: memberIds,
                        );
                        final dbService = ref.read(databaseServiceProvider);
                        dbService.addGroup(Group(
                          id: groupId,
                          name: groupName,
                          creatorId: localUserId,
                          memberIds: [localUserId, ...memberIds],
                          createdAt: DateTime.now(),
                        ));
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Group "$groupName" created')),
                        );
                      },
                child: const Text('Create'),
              ),
            ],
          );
        });
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
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
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
                  const Text(
                    'Edit Profile',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF171B24)),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: Stack(
                      children: [
                        _buildAvatar('${fNameController.text} ${lNameController.text}', null, currentBase64, size: 80),
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
                              child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
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
                  const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B4EBA),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
                onPressed: () async {
                  final newProfile = userProfile.copyWith(
                    firstName: fNameController.text.trim(),
                    lastName: lNameController.text.trim(),
                    profilePicBase64: currentBase64,
                  );
                  await ref.read(userProfileProvider.notifier).saveProfile(newProfile);
                  ref.read(chatServiceProvider).updateProfilePresence();
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Profile updated successfully')),
                    );
                  }
                },
                child: const Text('Save Changes'),
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () async {
                  await ref.read(userProfileProvider.notifier).clearProfile();
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Log Out / Reset Profile', style: TextStyle(color: Colors.redAccent)),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
        });
      },
    );
  }

  Widget _buildAvatar(String name, String? pathOrUrl, String? base64Str, {double size = 48}) {
    if (base64Str != null && base64Str.isNotEmpty) {
      try {
        final bytes = base64Decode(base64Str);
        return ClipRRect(
          borderRadius: BorderRadius.circular(size / 2),
          child: Image.memory(bytes, width: size, height: size, fit: BoxFit.cover),
        );
      } catch (_) {}
    }

    if (pathOrUrl != null && pathOrUrl.isNotEmpty) {
      if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(size / 2),
          child: Image.network(pathOrUrl, width: size, height: size, fit: BoxFit.cover),
        );
      } else {
        final file = File(pathOrUrl);
        if (file.existsSync()) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(size / 2),
            child: Image.file(file, width: size, height: size, fit: BoxFit.cover),
          );
        }
      }
    }

    // Fallback colored initial avatar
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
        style: TextStyle(color: Colors.white, fontSize: size * 0.45, fontWeight: FontWeight.bold),
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

    final userName = userProfile != null
        ? '${userProfile.firstName} ${userProfile.lastName}'
        : 'User';

    // Filter conversations based on search query
    final filteredConversations = conversations.where((conv) {
      if (_searchQuery.isEmpty) return true;
      final query = _searchQuery.toLowerCase();
      final peerId = conv['peerId'] as String;
      final lastMsg = conv['lastMessage'] as ChatMessage;

      // Try to find peer name from peers list
      final peerMatch = peers.where((p) => p.id == peerId);
      final peerName = peerMatch.isNotEmpty ? peerMatch.first.deviceName : peerId;

      return peerName.toLowerCase().contains(query) ||
          lastMsg.content.toLowerCase().contains(query) ||
          peerId.toLowerCase().contains(query);
    }).toList();

    return Scaffold(
      backgroundColor: Colors.white,
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
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 20),
              ),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search, color: Colors.white),
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
      // Drawer
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
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                        child: InkWell(
                          onTap: () {
                            Navigator.pop(context);
                            if (userProfile != null) {
                              _showSettingsModal(userProfile);
                            }
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Row(
                              children: [
                                _buildAvatar(userName, userProfile?.profilePicPath, userProfile?.profilePicBase64, size: 50),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
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
                                const Icon(Icons.edit, color: Colors.white54, size: 18),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const Divider(color: Colors.white12, thickness: 1),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          children: [
                            _buildDrawerItem(Icons.home_outlined, 'Home', () {
                              Navigator.pop(context);
                            }),
                            _buildDrawerItem(Icons.bookmark_border_outlined, 'Saved Messages', () {
                              Navigator.pop(context);
                              final roomId = ChatMessage.deriveRoomId(localUserId, localUserId);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ChatScreen(peerId: localUserId, roomId: roomId),
                                ),
                              );
                            }),
                            _buildDrawerItem(Icons.contacts_outlined, 'Contacts', () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const ContactsScreen()),
                              );
                            }),
                            _buildDrawerItem(Icons.person_add_alt_1_outlined, 'Invite Friends', () {
                              Navigator.pop(context);
                              Clipboard.setData(ClipboardData(text: myShortCode));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Copied $myShortCode — share with friends!')),
                              );
                            }),
                            const Divider(color: Colors.white12, thickness: 1),
                            _buildDrawerItem(Icons.settings_outlined, 'Settings', () {
                              Navigator.pop(context);
                              if (userProfile != null) {
                                _showSettingsModal(userProfile);
                              }
                            }),
                            _buildDarkModeToggle(),
                            const Divider(color: Colors.white12, thickness: 1),
                            _buildDrawerItem(Icons.logout, 'Sign Out', () {
                              Navigator.pop(context);
                              authService.signOut();
                            }),
                          ],
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
                          icon: const Icon(Icons.close, color: Colors.white, size: 28),
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
          // Connection state bar
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
                  color: chatConnected ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                  size: 13,
                ),
                const SizedBox(width: 6),
                Text(
                  chatConnected
                      ? 'Chat Server Connected'
                      : 'Connecting to server...',
                  style: TextStyle(
                    color: chatConnected ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: filteredConversations.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline, size: 54, color: const Color(0xFF1B4EBA).withValues(alpha: 0.2)),
                        const SizedBox(height: 16),
                        const Text(
                          'No conversations yet',
                          style: TextStyle(color: Color(0xFF7E8494), fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _showNewChatDialog,
                          child: const Text('Start a New Chat', style: TextStyle(color: Color(0xFF1B4EBA), fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: filteredConversations.length,
                    separatorBuilder: (context, index) => const Divider(height: 1, indent: 84, color: Color(0xFFF1F3F7)),
                    itemBuilder: (context, index) {
                      final conv = filteredConversations[index];
                      final roomId = conv['roomId'] as String;
                      final peerId = conv['peerId'] as String;
                      final lastMsg = conv['lastMessage'] as ChatMessage;
                      final unreadCount = conv['unreadCount'] as int;

                      // Resolve peer display name from presence map first, then local peers DB
                      final presenceData = presenceMap[peerId];
                      final peerMatch = peers.where((p) => p.id == peerId);
                      final peerName = presenceData?['displayName'] as String?
                          ?? (peerMatch.isNotEmpty
                              ? peerMatch.first.deviceName
                              : 'User ${peerId.length >= 8 ? peerId.substring(0, 8) : peerId}');
                      final peerPic = presenceData?['profilePicBase64'] as String?
                          ?? (peerMatch.isNotEmpty ? peerMatch.first.profilePicBase64 : null);

                      // Presence
                      final presence = presenceMap[peerId];
                      final isOnline = presence != null && presence['status'] == 'online';

                      // Format last message
                      final subtext = lastMsg.senderId == localUserId
                          ? 'You: ${lastMsg.content}'
                          : lastMsg.content;
                      final timeText = DateFormat('hh:mm a').format(lastMsg.timestamp);

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
                                  color: isOnline ? const Color(0xFF10B981) : Colors.grey,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                ),
                              ),
                            ),
                          ],
                        ),
                        title: Text(
                          peerName,
                          style: TextStyle(
                            color: const Color(0xFF171B24),
                            fontWeight: unreadCount > 0 ? FontWeight.w800 : FontWeight.bold,
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
                            fontWeight: unreadCount > 0 ? FontWeight.w600 : FontWeight.normal,
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
                                fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            if (unreadCount > 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                              builder: (context) => ChatScreen(
                                peerId: peerId,
                                roomId: roomId,
                              ),
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
        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
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
      leading: Icon(icon, color: Colors.white.withValues(alpha: 0.85), size: 22),
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
}
