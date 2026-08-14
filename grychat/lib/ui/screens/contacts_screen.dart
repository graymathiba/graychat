import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/chat_message.dart';
import '../../core/providers/database_provider.dart';
import '../../core/providers/chat_provider.dart';
import 'chat_screen.dart';

class ContactsScreen extends ConsumerWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localUserId = ref.watch(localUserIdProvider);
    final presenceMap = ref.watch(userPresenceProvider);
    final peers = ref.watch(peersProvider);

    final contacts = <Map<String, dynamic>>[];

    for (final entry in presenceMap.entries) {
      if (entry.key == localUserId) continue;
      final peerMatch = peers.where((p) => p.id == entry.key);
      contacts.add({
        'userId': entry.key,
        'displayName':
            entry.value['displayName'] ??
            (peerMatch.isNotEmpty
                ? peerMatch.first.deviceName
                : (entry.key.length >= 8
                      ? entry.key.substring(0, 8)
                      : entry.key)),
        'profilePicBase64':
            entry.value['profilePicBase64'] ??
            (peerMatch.isNotEmpty ? peerMatch.first.profilePicBase64 : null),
        'isOnline': entry.value['status'] == 'online',
        'lastSeen': entry.value['lastSeen'],
      });
    }

    for (final peer in peers) {
      if (peer.id == localUserId) continue;
      if (contacts.any((c) => c['userId'] == peer.id)) continue;
      contacts.add({
        'userId': peer.id,
        'displayName': peer.deviceName,
        'profilePicBase64': peer.profilePicBase64,
        'isOnline': false,
        'lastSeen': null,
      });
    }

    contacts.sort((a, b) {
      if (a['isOnline'] == true && b['isOnline'] != true) return -1;
      if (a['isOnline'] != true && b['isOnline'] == true) return 1;
      return (a['displayName'] as String).compareTo(b['displayName'] as String);
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts'),
        backgroundColor: const Color(0xFF1B4EBA),
        foregroundColor: Colors.white,
      ),
      body: contacts.isEmpty
          ? const Center(
              child: Text(
                'No contacts yet. Share your invite code to add friends!',
                style: TextStyle(color: Color(0xFF7E8494)),
              ),
            )
          : ListView.separated(
              itemCount: contacts.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
              itemBuilder: (context, index) {
                final contact = contacts[index];
                final name = contact['displayName'] as String;
                final isOnline = contact['isOnline'] as bool;

                return ListTile(
                  leading: Stack(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: const Color(0xFF1B4EBA),
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
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
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                  title: Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    isOnline ? 'Online' : 'Offline',
                    style: TextStyle(
                      color: isOnline
                          ? const Color(0xFF10B981)
                          : const Color(0xFF7E8494),
                      fontSize: 12,
                    ),
                  ),
                  onTap: () {
                    final userId = contact['userId'] as String;
                    final roomId = ChatMessage.deriveRoomId(
                      localUserId,
                      userId,
                    );
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          peerId: userId,
                          roomId: roomId,
                          peerName: name,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
