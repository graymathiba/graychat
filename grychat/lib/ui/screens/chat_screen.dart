import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:record/record.dart';
import '../../core/models/chat_message.dart';
import '../../core/providers/database_provider.dart';
import '../../core/providers/chat_provider.dart';
import '../../core/network/chat_service.dart';
import '../widgets/error_boundary.dart';
import 'call_screen.dart';
import 'pdf_viewer_screen.dart';
import '../../core/network/call_service.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String peerId;
  final String roomId;
  final String? peerName;

  const ChatScreen({
    super.key,
    required this.peerId,
    required this.roomId,
    this.peerName,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _typingDebounce;
  ChatService? _chatService;
  ChatMessage? _replyToMessage;
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  DateTime? _recordingStartTime;
  Timer? _recordingTimer;
  String _recordingDuration = '0:00';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _chatService = ref.read(chatServiceProvider);
      _chatService!.joinRoom(widget.roomId);
        await ref
            .read(chatMessagesProvider(widget.roomId).notifier)
            .markIncomingMessagesRead(widget.peerId);
        if (mounted) {
          ref.read(conversationListProvider.notifier).refresh();
        }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _typingDebounce?.cancel();
    _recordingTimer?.cancel();
    _audioRecorder.dispose();
    _chatService?.sendTypingStatus(widget.roomId, false);
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (!await _audioRecorder.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission denied')),
        );
      }
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _audioRecorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000, sampleRate: 44100),
      path: path,
    );
    setState(() {
      _isRecording = true;
      _recordingStartTime = DateTime.now();
    });
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_recordingStartTime == null) return;
      final elapsed = DateTime.now().difference(_recordingStartTime!);
      setState(() {
        _recordingDuration = '${elapsed.inMinutes}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}';
      });
    });
  }

  Future<void> _stopAndSendRecording() async {
    _recordingTimer?.cancel();
    final path = await _audioRecorder.stop();
    setState(() {
      _isRecording = false;
      _recordingStartTime = null;
      _recordingDuration = '0:00';
    });
    if (path == null || !mounted) return;
    try {
      final file = File(path);
      final bytes = await file.readAsBytes();
      final ext = path.split('.').last;
      final name = 'voice_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await ref
          .read(chatMessagesProvider(widget.roomId).notifier)
          .sendAttachment(
            receiverId: widget.peerId,
            fileName: name,
            mimeType: 'audio/$ext',
            base64Data: base64Encode(bytes),
            size: bytes.length,
          );
      if (mounted) _scrollToBottom();
    } finally {
      try { await File(path).delete(); } catch (_) {}
    }
  }

  void _cancelRecording() {
    _recordingTimer?.cancel();
    _audioRecorder.stop();
    setState(() {
      _isRecording = false;
      _recordingStartTime = null;
      _recordingDuration = '0:00';
    });
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    ref
        .read(chatMessagesProvider(widget.roomId).notifier)
        .sendMessage(text, widget.peerId, replyTo: _replyToMessage);

    _messageController.clear();
    _replyToMessage = null;

    ref.read(chatServiceProvider).sendTypingStatus(widget.roomId, false);
    _typingDebounce?.cancel();
    ref.read(conversationListProvider.notifier).refresh();
    _scrollToBottom();
  }

  Future<void> _pickAttachment() async {
    final source = await showModalBottomSheet<ImageSource?>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: const Text('File'),
              onTap: () => Navigator.pop(context, null),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;

    if (source != null) {
      final picker = ImagePicker();
      XFile? picked;
      try {
        picked = await picker.pickImage(source: source);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera not available on this device. Try Gallery instead.')),
        );
        return;
      }
      if (!mounted || picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      if (bytes.length > 50 * 1024 * 1024) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image must be 50 MB or smaller.')),
        );
        return;
      }
      final ext = picked.name.split('.').last.toLowerCase();
      await ref
          .read(chatMessagesProvider(widget.roomId).notifier)
          .sendAttachment(
            receiverId: widget.peerId,
            fileName: picked.name,
            mimeType: _mimeTypeFor(ext),
            base64Data: base64Encode(bytes),
            size: bytes.length,
          );
      if (mounted) _scrollToBottom();
      return;
    }

    final result = await FilePicker.pickFiles(type: FileType.any);
    if (!mounted || result == null) return;

    final file = result.files.single;
    Uint8List bytes;
    if (file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    } else {
      bytes = await file.readAsBytes();
    }
    if (!mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not read the selected file.')),
      );
      return;
    }
    if (bytes.length > 50 * 1024 * 1024) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Files must be 50 MB or smaller.')),
      );
      return;
    }

    final extension =
        (file.extension ?? file.name.split('.').last).toLowerCase();
    final mimeType = _mimeTypeFor(extension);
    await ref
        .read(chatMessagesProvider(widget.roomId).notifier)
        .sendAttachment(
          receiverId: widget.peerId,
          fileName: file.name,
          mimeType: mimeType,
          base64Data: base64Encode(bytes),
          size: bytes.length,
        );
    if (mounted) _scrollToBottom();
  }

  String _mimeTypeFor(String? extension) {
    const types = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'mp3': 'audio/mpeg',
      'wav': 'audio/wav',
      'm4a': 'audio/mp4',
      'mp4': 'video/mp4',
      'mov': 'video/quicktime',
      'webm': 'video/webm',
      'm4v': 'video/x-m4v',
      'avi': 'video/x-msvideo',
      'mkv': 'video/x-matroska',
      '3gp': 'video/3gpp',
      '3g2': 'video/3gpp2',
      'wmv': 'video/x-ms-wmv',
      'flv': 'video/x-flv',
      'mpeg': 'video/mpeg', // Handled specially below if it's WhatsApp Audio
      'mpg': 'video/mpeg',
      'ogv': 'video/ogg',
      'pdf': 'application/pdf',
      'txt': 'text/plain',
      'zip': 'application/zip',
    };
    return types[extension] ?? 'application/octet-stream';
  }

  void _showEmojiMenu() {
    const emojis = ['😀', '😂', '😍', '👍', '🙏', '🔥', '🎉', '❤️', '😢', '😎'];
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: emojis
              .map(
                (emoji) => IconButton(
                  icon: Text(emoji, style: const TextStyle(fontSize: 28)),
                  onPressed: () {
                    _messageController.text += emoji;
                    _messageController.selection = TextSelection.fromPosition(
                      TextPosition(offset: _messageController.text.length),
                    );
                    Navigator.pop(context);
                  },
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Future<File?> _materializeAttachment(ChatMessage message) async {
    final encoded = message.attachmentBase64;
    if (encoded == null || encoded.isEmpty) return null;

    final directory = await getTemporaryDirectory();
    final safeName = (message.fileName ?? 'attachment').replaceAll(
      RegExp(r'[^a-zA-Z0-9._-]'),
      '_',
    );
    final file = File('${directory.path}/grychat_${message.id}_$safeName');
    await file.writeAsBytes(base64Decode(encoded), flush: true);
    return file;
  }

  Future<void> _openAttachment(ChatMessage message) async {
    try {
      final file = await _materializeAttachment(message);
      if (file == null) throw Exception('Attachment data is unavailable');

      if (Platform.isWindows) {
        await Process.start('explorer.exe', [file.path]);
      } else if (Platform.isMacOS) {
        await Process.start('open', [file.path]);
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [file.path]);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open attachment: $error')),
      );
    }
  }

  void _showImagePreview(ChatMessage message) {
    final encoded = message.attachmentBase64;
    if (encoded == null || encoded.isEmpty) return;

    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: InteractiveViewer(
          child: Image.memory(
            base64Decode(encoded),
            fit: BoxFit.contain,
            errorBuilder: (_, error, _) => Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Unable to display image: $error'),
            ),
          ),
        ),
      ),
    );
  }

  void _openPdfViewer(ChatMessage message) {
    final encoded = message.attachmentBase64;
    if (encoded == null || encoded.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfViewerScreen(
          pdfBytes: base64Decode(encoded),
          fileName: message.fileName,
        ),
      ),
    );
  }

  void _onTextChanged(String text) {
    final chatService = ref.read(chatServiceProvider);

    if (text.isNotEmpty) {
      chatService.sendTypingStatus(widget.roomId, true);
    }

    // Debounce: stop typing after 2 seconds of inactivity
    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(seconds: 2), () {
      chatService.sendTypingStatus(widget.roomId, false);
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Returns the appropriate status icon for a sent message
  Widget _buildStatusIcon(String status) {
    switch (status) {
      case 'sending':
        return const Icon(Icons.access_time, color: Colors.white54, size: 12);
      case 'sent':
        return const Icon(Icons.done, color: Colors.white70, size: 12);
      case 'delivered':
        return const Icon(Icons.done_all, color: Colors.white70, size: 12);
      case 'read':
        return const Icon(Icons.done_all, color: Color(0xFF60A5FA), size: 12);
      case 'failed':
        return const Icon(
          Icons.error_outline,
          color: Colors.redAccent,
          size: 12,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  void _showReactionPicker(ChatMessage message) {
    const emojis = ['❤️', '😂', '😍', '👍', '🙏', '🔥', '🎉', '😢', '😎', '😮'];
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: emojis
                    .map(
                      (emoji) => GestureDetector(
                        onTap: () {
                          ref
                              .read(chatMessagesProvider(widget.roomId).notifier)
                              .toggleReaction(message.id, emoji);
                          Navigator.pop(context);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(emoji, style: const TextStyle(fontSize: 28)),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Reply'),
              onTap: () {
                Navigator.pop(context);
                setState(() => _replyToMessage = message);
              },
            ),
            ListTile(
              leading: const Icon(Icons.forward),
              title: const Text('Forward'),
              onTap: () {
                Navigator.pop(context);
                _showForwardDialog(message);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showForwardDialog(ChatMessage message) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Forward to:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _getRecentContacts(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(child: Text('No contacts yet'));
                  }
                  return ListView.builder(
                    itemCount: snapshot.data!.length,
                    itemBuilder: (context, index) {
                      final contact = snapshot.data![index];
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(
                            (contact['displayName'] as String? ?? '?')[0],
                          ),
                        ),
                        title: Text(contact['displayName'] as String? ?? 'Unknown'),
                        onTap: () {
                          ref.read(chatServiceProvider).forwardMessage(
                            message,
                            [contact['peerId'] as String],
                          );
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Message forwarded')),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _getRecentContacts() async {
    final peers = ref.read(peersProvider);
    final messages = ref.read(chatMessagesProvider(widget.roomId));
    final localUserId = ref.read(localUserIdProvider);
    final seen = <String>{};
    final result = <Map<String, dynamic>>[];
    for (final msg in messages.reversed) {
      final otherId =
          msg.senderId == localUserId ? msg.receiverId : msg.senderId;
      if (otherId == localUserId || seen.contains(otherId)) continue;
      seen.add(otherId);
      final peerMatch = peers.where((p) => p.id == otherId);
      result.add({
        'peerId': otherId,
        'displayName': peerMatch.isNotEmpty
            ? peerMatch.first.deviceName
            : otherId.substring(0, 8),
      });
    }
    return result;
  }

  Widget _buildReplyQuote(ChatMessage message, bool isMe) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isMe
            ? Colors.white.withValues(alpha: 0.15)
            : const Color(0xFFF0F2F5),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: isMe ? Colors.white54 : const Color(0xFF1B4EBA),
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Reply',
            style: TextStyle(
              color: isMe ? Colors.white70 : const Color(0xFF1B4EBA),
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            message.replyToContent ?? '',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isMe ? Colors.white60 : const Color(0xFF7E8494),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReactionsDisplay(ChatMessage message, bool isMe) {
    final entries = message.reactions.entries.toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 2,
        children: entries.map((entry) {
          final emoji = entry.key;
          final users = entry.value;
          final localUid = ref.read(localUserIdProvider);
          final isMyReaction = users.contains(localUid);
          return GestureDetector(
            onTap: () {
              ref
                  .read(chatMessagesProvider(widget.roomId).notifier)
                  .toggleReaction(message.id, emoji);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isMyReaction
                    ? (isMe
                        ? Colors.white.withValues(alpha: 0.3)
                        : const Color(0xFF1B4EBA).withValues(alpha: 0.1))
                    : (isMe
                        ? Colors.white.withValues(alpha: 0.15)
                        : const Color(0xFFF0F2F5)),
                borderRadius: BorderRadius.circular(12),
                border: isMyReaction
                    ? Border.all(
                        color: isMe ? Colors.white38 : const Color(0xFF1B4EBA),
                        width: 1,
                      )
                    : null,
              ),
              child: Text(
                '$emoji ${users.length > 1 ? users.length : ''}',
                style: TextStyle(
                  fontSize: 12,
                  color: isMe ? Colors.white : const Color(0xFF171B24),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatMessagesProvider(widget.roomId));
    final localUserId = ref.watch(localUserIdProvider);
    final typingMap = ref.watch(typingStatusProvider(widget.roomId));
    final presenceMap = ref.watch(userPresenceProvider);

    // Resolve peer display name: passed name > presence map > local peers DB > fallback
    final peers = ref.watch(peersProvider);
    final peerMatch = peers.where((p) => p.id == widget.peerId);
    final presenceData = presenceMap[widget.peerId];
    final peerName =
        widget.peerName ??
        presenceData?['displayName'] as String? ??
        (peerMatch.isNotEmpty ? peerMatch.first.deviceName : null) ??
        'User ${widget.peerId.length >= 8 ? widget.peerId.substring(0, 8) : widget.peerId}';

    // Presence
    final isOnline = presenceData != null && presenceData['status'] == 'online';

    // Typing indicator
    final isTyping = typingMap.entries
        .where((e) => e.key != localUserId && e.value == true)
        .isNotEmpty;

    // Auto-scroll when new messages arrive
    if (messages.isNotEmpty) {
      _scrollToBottom();
    }

    return ErrorBoundary(
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F6FA),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1B4EBA),
          iconTheme: const IconThemeData(color: Colors.white),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              // Refresh conversation list on exit
              ref.read(conversationListProvider.notifier).refresh();
              Navigator.pop(context);
            },
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                peerName,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isOnline ? const Color(0xFF10B981) : Colors.grey,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isTyping ? 'typing...' : (isOnline ? 'Online' : 'Offline'),
                    style: TextStyle(
                      color: isTyping
                          ? const Color(0xFF60A5FA)
                          : Colors.white70,
                      fontSize: 11,
                      fontStyle: isTyping ? FontStyle.italic : FontStyle.normal,
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.phone, color: Colors.white70),
              tooltip: 'Voice Call',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CallScreen(
                      peerId: widget.peerId,
                      peerName: peerName,
                      callType: CallType.audio,
                    ),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.videocam, color: Colors.white70),
              tooltip: 'Video Call',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CallScreen(
                      peerId: widget.peerId,
                      peerName: peerName,
                      callType: CallType.video,
                    ),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_sweep, color: Colors.white70),
              tooltip: 'Clear Messages',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: Colors.white,
                    title: const Text(
                      'Clear Chat History',
                      style: TextStyle(
                        color: Color(0xFF171B24),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    content: const Text(
                      'Are you sure you want to delete all messages in this conversation?',
                      style: TextStyle(color: Color(0xFF7E8494)),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(color: Color(0xFF7E8494)),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          ref
                              .read(
                                chatMessagesProvider(widget.roomId).notifier,
                              )
                              .clearMessages();
                          ref.read(conversationListProvider.notifier).refresh();
                          Navigator.pop(context);
                        },
                        child: const Text(
                          'Delete',
                          style: TextStyle(color: Colors.redAccent),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
        body: Stack(
          children: [
        Column(
          children: [
            // Message Feed
            Expanded(
              child: messages.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline,
                            size: 48,
                            color: const Color(
                              0xFF1B4EBA,
                            ).withValues(alpha: 0.15),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'No messages yet. Send a message to start.',
                            style: TextStyle(
                              color: Color(0xFF7E8494),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final message = messages[index];
                        final isMe = message.senderId == localUserId;
                        return _buildMessageBubble(message, isMe);
                      },
                    ),
            ),

            // Typing indicator bar
            if (isTyping)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                color: Colors.white,
                child: Row(
                  children: [
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(
                          const Color(0xFF1B4EBA).withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$peerName is typing...',
                      style: const TextStyle(
                        color: Color(0xFF7E8494),
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),

            // Reply preview bar
            if (_replyToMessage != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: const BoxDecoration(
                  color: Color(0xFFE8EDF5),
                  border: Border(
                    top: BorderSide(color: Color(0xFFD0D5DD), width: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B4EBA),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Reply',
                            style: TextStyle(
                              color: Color(0xFF1B4EBA),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _replyToMessage!.content,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF7E8494),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() => _replyToMessage = null),
                    ),
                  ],
                ),
              ),

            // Message Input Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: Color(0xFFE2E6EE), width: 0.8),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.emoji_emotions_outlined),
                    tooltip: 'Add emoji',
                    onPressed: _showEmojiMenu,
                  ),
                  IconButton(
                    icon: const Icon(Icons.attach_file),
                    tooltip: 'Attach image, audio, video, or file',
                    onPressed: _pickAttachment,
                  ),
                  // Text Field
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      style: const TextStyle(color: Color(0xFF171B24)),
                      decoration: InputDecoration(
                        hintText: 'Type your message...',
                        hintStyle: const TextStyle(color: Color(0xFFB0B5C1)),
                        filled: true,
                        fillColor: const Color(0xFFF4F6FA),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(
                            color: Color(0xFF1B4EBA),
                            width: 1.0,
                          ),
                        ),
                      ),
                      onChanged: _onTextChanged,
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Mic / Send Button
                  if (_messageController.text.trim().isEmpty && !_isRecording)
                    GestureDetector(
                      onLongPress: _startRecording,
                      child: IconButton(
                        icon: Icon(_isRecording ? Icons.stop_circle : Icons.mic, color: const Color(0xFF1B4EBA)),
                        tooltip: 'Hold to record voice message',
                        onPressed: _startRecording,
                      ),
                    )
                  else
                    GestureDetector(
                      onTap: _sendMessage,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: const BoxDecoration(
                          color: Color(0xFF1B4EBA),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.send,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
            // Recording overlay
            if (_isRecording)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  color: const Color(0xFF1B4EBA),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Row(
                    children: [
                      const Icon(Icons.mic, color: Colors.redAccent, size: 20),
                      const SizedBox(width: 10),
                      Text(
                        _recordingDuration,
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Recording...',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: _cancelRecording,
                      ),
                      GestureDetector(
                        onTap: _stopAndSendRecording,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: const BoxDecoration(
                            color: Colors.redAccent,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.send, color: Colors.white, size: 18),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message, bool isMe) {
    final timeStr = DateFormat('HH:mm').format(message.timestamp);
    final isImage = message.messageType == 'image';
    final isWhatsAppAudio =
        (message.fileName ?? message.content).contains('WhatsApp Audio');
    final isAudio = message.messageType == 'audio' ||
        message.mimeType?.startsWith('audio/') == true ||
        (isWhatsAppAudio && message.mimeType?.startsWith('video/') == true);
    final isVideo = !isAudio &&
        (message.messageType == 'video' ||
            message.mimeType?.startsWith('video/') == true);
    final isPdf = message.mimeType == 'application/pdf' ||
        (message.fileName?.toLowerCase().endsWith('.pdf') ?? false);
    final hasAttachment = message.messageType != 'text';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _showReactionPicker(message),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isMe ? const Color(0xFF1B4EBA) : Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isMe ? 16 : 4),
              bottomRight: Radius.circular(isMe ? 4 : 16),
            ),
            border: isMe
                ? null
                : Border.all(color: const Color(0xFFE2E6EE), width: 0.8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Reply quote
              if (message.replyToMessageId != null)
                _buildReplyQuote(message, isMe),
              if (isImage && message.attachmentBase64 != null)
                GestureDetector(
                  onTap: () => _showImagePreview(message),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(
                      base64Decode(message.attachmentBase64!),
                      width: 240,
                      height: 190,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          _attachmentLabel(message, isMe),
                    ),
                  ),
                )
              else if (isAudio && message.attachmentBase64 != null)
                _AudioAttachmentPlayer(
                  key: ValueKey(message.id),
                  bytes: base64Decode(message.attachmentBase64!),
                  fileName: message.fileName ?? message.content,
                  isMine: isMe,
                )
              else if (isVideo && message.attachmentBase64 != null)
                _VideoAttachmentPlayer(
                  key: ValueKey(message.id),
                  bytes: base64Decode(message.attachmentBase64!),
                  fileName: message.fileName ?? message.content,
                )
              else if (isPdf && message.attachmentBase64 != null)
                GestureDetector(
                  onTap: () => _openPdfViewer(message),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isMe
                          ? Colors.white.withValues(alpha: 0.15)
                          : const Color(0xFFF8F9FB),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 44,
                          height: 56,
                          decoration: BoxDecoration(
                            color: isMe
                                ? Colors.white.withValues(alpha: 0.2)
                                : const Color(0xFFE74C3C).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.picture_as_pdf,
                                color: isMe ? Colors.white : const Color(0xFFE74C3C),
                                size: 24,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'PDF',
                                style: TextStyle(
                                  color: isMe ? Colors.white70 : const Color(0xFFE74C3C),
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                message.fileName ?? 'Document',
                                style: TextStyle(
                                  color: isMe ? Colors.white : const Color(0xFF171B24),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Tap to view',
                                style: TextStyle(
                                  color: isMe ? Colors.white60 : const Color(0xFF7E8494),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                _attachmentLabel(message, isMe),
            if (hasAttachment && !isImage && !isAudio && !isVideo && !isPdf)
              TextButton.icon(
                onPressed: () => _openAttachment(message),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Open'),
                style: TextButton.styleFrom(
                  foregroundColor: isMe
                      ? Colors.white
                      : const Color(0xFF1B4EBA),
                  padding: EdgeInsets.zero,
                ),
              ),
            if (isPdf && message.attachmentBase64 != null)
              TextButton.icon(
                onPressed: () => _openPdfViewer(message),
                icon: const Icon(Icons.picture_as_pdf, size: 16),
                label: const Text('View PDF'),
                style: TextButton.styleFrom(
                  foregroundColor: isMe
                      ? Colors.white
                      : const Color(0xFF1B4EBA),
                  padding: EdgeInsets.zero,
                ),
              ),
            const SizedBox(height: 4),
            // Reactions display
            if (message.reactions.isNotEmpty)
              _buildReactionsDisplay(message, isMe),
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  timeStr,
                  style: TextStyle(
                    color: isMe ? Colors.white70 : const Color(0xFF7E8494),
                    fontSize: 10,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  _buildStatusIcon(message.status),
                ],
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }

  String _attachmentIcon(String type, {String? mimeType, String? fileName}) {
    if (mimeType == 'application/pdf' || (fileName?.toLowerCase().endsWith('.pdf') ?? false)) {
      return '📄';
    }
    switch (type) {
      case 'image':
        return '🖼️';
      case 'audio':
        return '🎵';
      case 'video':
        return '🎬';
      default:
        return '📎';
    }
  }

  Widget _attachmentLabel(ChatMessage message, bool isMe) {
    return Text(
      message.messageType == 'text'
          ? message.content
          : '${_attachmentIcon(message.messageType, mimeType: message.mimeType, fileName: message.fileName)} ${message.fileName ?? message.content}',
      style: TextStyle(
        color: isMe ? Colors.white : const Color(0xFF171B24),
        fontSize: 14.5,
      ),
    );
  }
}

class _AudioAttachmentPlayer extends StatefulWidget {
  final Uint8List bytes;
  final String fileName;
  final bool isMine;

  const _AudioAttachmentPlayer({
    super.key,
    required this.bytes,
    required this.fileName,
    required this.isMine,
  });

  @override
  State<_AudioAttachmentPlayer> createState() => _AudioAttachmentPlayerState();
}

class _AudioAttachmentPlayerState extends State<_AudioAttachmentPlayer> {
  final AudioPlayer _player = AudioPlayer();
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _player.onDurationChanged.listen((duration) {
      if (mounted) setState(() => _duration = duration);
    });
    _player.onPositionChanged.listen((position) {
      if (mounted) setState(() => _position = position);
    });
    _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _playing = state == PlayerState.playing);
    });
  }

  Future<void> _togglePlayback() async {
    if (_playing) {
      await _player.pause();
    } else {
      await _player.play(BytesSource(widget.bytes));
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxSeconds = _duration.inMilliseconds > 0
        ? _duration.inMilliseconds.toDouble()
        : 1.0;
    final currentSeconds = _position.inMilliseconds
        .clamp(0, _duration.inMilliseconds)
        .toDouble();

    return SizedBox(
      width: 260,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: _togglePlayback,
            icon: Icon(_playing ? Icons.pause_circle : Icons.play_circle),
            color: widget.isMine ? Colors.white : const Color(0xFF1B4EBA),
            iconSize: 34,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: widget.isMine
                        ? Colors.white
                        : const Color(0xFF171B24),
                    fontSize: 13,
                  ),
                ),
                Slider(
                  value: currentSeconds,
                  max: maxSeconds,
                  onChanged: _duration == Duration.zero
                      ? null
                      : (value) =>
                            _player.seek(Duration(milliseconds: value.round())),
                  activeColor: widget.isMine
                      ? Colors.white
                      : const Color(0xFF1B4EBA),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoAttachmentPlayer extends StatefulWidget {
  final Uint8List bytes;
  final String fileName;

  const _VideoAttachmentPlayer({
    super.key,
    required this.bytes,
    required this.fileName,
  });

  @override
  State<_VideoAttachmentPlayer> createState() => _VideoAttachmentPlayerState();
}

class _VideoAttachmentPlayerState extends State<_VideoAttachmentPlayer> {
  late final Player _player;
  VideoController? _videoController;
  bool _initialized = false;
  String? _error;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = VideoController(_player);
    _initStreams();
    _initialize();
  }

  void _initStreams() {
    _player.stream.playing.listen((playing) {
      if (mounted) setState(() => _isPlaying = playing);
    });
    _player.stream.duration.listen((duration) {
      if (mounted) setState(() => _duration = duration);
    });
    _player.stream.position.listen((position) {
      if (mounted) setState(() => _position = position);
    });
  }

  Future<void> _initialize() async {
    try {
      final directory = await getTemporaryDirectory();
      final safeName = widget.fileName.replaceAll(
        RegExp(r'[^a-zA-Z0-9._-]'),
        '_',
      );
      final safeKey = widget.key
          .toString()
          .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final file = File(
        '${directory.path}/grychat_video_${safeKey}_$safeName',
      );
      await file.writeAsBytes(widget.bytes, flush: true);
      await _player.open(Media(file.path), play: false);
      if (!mounted) return;
      setState(() => _initialized = true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Container(
        width: 240,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.broken_image, color: Colors.grey, size: 20),
                SizedBox(width: 8),
                Text('Video Playback Error', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 4),
            Text(_error!, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () async {
                final directory = await getTemporaryDirectory();
                final safeName = widget.fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
                final safeKey = widget.key.toString().replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
                final file = File('${directory.path}/grychat_video_${safeKey}_$safeName');
                if (await file.exists()) {
                  if (Platform.isWindows) {
                    await Process.run('explorer.exe', [file.path]);
                  } else if (Platform.isMacOS) {
                    await Process.run('open', [file.path]);
                  } else if (Platform.isLinux) {
                    await Process.run('xdg-open', [file.path]);
                  }
                }
              },
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Play in System Player'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B4EBA),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }
    if (!_initialized || _videoController == null) {
      return const SizedBox(
        width: 240,
        height: 150,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return SizedBox(
      width: 260,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: GestureDetector(
              onTap: () => _player.playOrPause(),
              child: SizedBox(
                height: 150,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Video(
                      controller: _videoController!,
                      controls: NoVideoControls,
                    ),
                    if (!_isPlaying)
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: [
              IconButton(
                onPressed: () {
                  _player.playOrPause();
                },
                icon: Icon(
                  _isPlaying ? Icons.pause : Icons.play_arrow,
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                    activeTrackColor: Theme.of(context).colorScheme.primary,
                    inactiveTrackColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                    thumbColor: Theme.of(context).colorScheme.primary,
                  ),
                  child: Slider(
                    value: _duration.inMilliseconds > 0
                        ? _position.inMilliseconds.toDouble().clamp(0.0, _duration.inMilliseconds.toDouble())
                        : 0.0,
                    max: _duration.inMilliseconds > 0 ? _duration.inMilliseconds.toDouble() : 1.0,
                    onChanged: (value) {
                      _player.seek(Duration(milliseconds: value.toInt()));
                    },
                  ),
                ),
              ),
              Text(
                '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
          Text(widget.fileName, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
