import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/models/chat_message.dart';
import '../../core/models/group.dart';
import '../../core/providers/chat_provider.dart';
import '../../core/network/chat_service.dart';

class GroupChatScreen extends ConsumerStatefulWidget {
  final Group group;

  const GroupChatScreen({
    super.key,
    required this.group,
  });

  @override
  ConsumerState<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends ConsumerState<GroupChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _typingDebounce;
  ChatService? _chatService;
  ChatMessage? _replyToMessage;

  static const _quickReactions = ['👍', '❤️', '😂', '😮', '😢'];

  String get _roomId => 'group_${widget.group.id}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _chatService = ref.read(chatServiceProvider);
      _chatService!.joinGroup(widget.group.id);
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _typingDebounce?.cancel();
    _chatService?.sendTypingStatus(_roomId, false);
    super.dispose();
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    ref
        .read(chatMessagesProvider(_roomId).notifier)
        .sendMessage(
          text,
          widget.group.id,
          replyTo: _replyToMessage,
          groupId: widget.group.id,
        );
    setState(() => _replyToMessage = null);
    _messageController.clear();
    ref.read(chatServiceProvider).sendTypingStatus(_roomId, false);
    _typingDebounce?.cancel();
    _scrollToBottom();
  }

  void _showMessageActions(ChatMessage message) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final emoji in _quickReactions)
                      IconButton(
                        iconSize: 28,
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          ref
                              .read(chatMessagesProvider(_roomId).notifier)
                              .toggleReaction(message.id, emoji,
                                  groupId: widget.group.id);
                        },
                        icon: Text(emoji),
                      ),
                  ],
                ),
                const Divider(height: 24),
                ListTile(
                  leading: const Icon(Icons.reply),
                  title: const Text('Reply'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    setState(() => _replyToMessage = message);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final localUserId = ref.read(localUserIdProvider);
    final messages = ref.watch(chatMessagesProvider(_roomId));

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFF1B4EBA),
              child: Text(
                widget.group.name.isNotEmpty
                    ? widget.group.name[0].toUpperCase()
                    : '?',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.group.name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    '${widget.group.memberIds.length} members',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.info_outline, color: colorScheme.onSurface),
            onPressed: () {
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.group,
                          size: 64,
                          color: colorScheme.onSurface.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No messages yet',
                          style: TextStyle(
                            fontSize: 16,
                            color: colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Send a message to start the conversation',
                          style: TextStyle(
                            fontSize: 14,
                            color: colorScheme.onSurface.withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      final isMe = message.senderId == localUserId;
                      final showAvatar = index == 0 ||
                          messages[index - 1].senderId != message.senderId;

                      return GestureDetector(
                        onLongPress: () => _showMessageActions(message),
                        child: _MessageBubble(
                          message: message,
                          isMe: isMe,
                          showAvatar: showAvatar,
                          onReactionTap: (emoji) {
                            ref
                                .read(chatMessagesProvider(_roomId).notifier)
                                .toggleReaction(message.id, emoji,
                                    groupId: widget.group.id);
                          },
                        ),
                      );
                    },
                  ),
          ),
          if (_replyToMessage != null)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border(
                  left: BorderSide(color: const Color(0xFF1B4EBA), width: 3),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Replying to ${_replyToMessage!.senderId == localUserId ? 'yourself' : _replyToMessage!.senderId.substring(0, 8)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1B4EBA),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _replyToMessage!.content,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, size: 18, color: colorScheme.onSurface.withValues(alpha: 0.6)),
                    onPressed: () => setState(() => _replyToMessage = null),
                  ),
                ],
              ),
            ),
          _buildMessageInput(colorScheme),
        ],
      ),
    );
  }

  Widget _buildMessageInput(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _messageController,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendMessage(),
                  onChanged: (_) {
                    _typingDebounce?.cancel();
                    _chatService?.sendTypingStatus(_roomId, true);
                    _typingDebounce = Timer(const Duration(seconds: 2), () {
                      _chatService?.sendTypingStatus(_roomId, false);
                    });
                  },
                  style: TextStyle(color: colorScheme.onSurface),
                  decoration: InputDecoration(
                    hintText: 'Type a message...',
                    hintStyle: TextStyle(color: colorScheme.onSurface.withValues(alpha: 0.5)),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: const BoxDecoration(
                color: Color(0xFF1B4EBA),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.send, color: Colors.white, size: 20),
                onPressed: _sendMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;
  final bool showAvatar;
  final ValueChanged<String>? onReactionTap;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.showAvatar,
    this.onReactionTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final time = DateFormat('HH:mm').format(message.timestamp);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe && showAvatar)
                CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFF1B4EBA).withValues(alpha: 0.2),
                  child: Text(
                    message.senderId[0].toUpperCase(),
                    style: const TextStyle(
                      color: Color(0xFF1B4EBA),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                )
              else if (!isMe)
                const SizedBox(width: 32),
              Flexible(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isMe ? const Color(0xFF1B4EBA) : colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isMe ? 16 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 16),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!isMe && showAvatar)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            message.senderId.substring(0, 8),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isMe
                                  ? Colors.white.withValues(alpha: 0.8)
                                  : const Color(0xFF1B4EBA),
                            ),
                          ),
                        ),
                      if (message.replyToMessageId != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.all(8),
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: isMe
                                ? Colors.white.withValues(alpha: 0.15)
                                : colorScheme.surface.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(8),
                            border: Border(
                              left: BorderSide(
                                color: isMe ? Colors.white70 : const Color(0xFF1B4EBA),
                                width: 3,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '↩ ${message.replyToSenderId ?? ''}'.trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isMe ? Colors.white70 : const Color(0xFF1B4EBA),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                message.replyToContent ?? '',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isMe
                                      ? Colors.white.withValues(alpha: 0.85)
                                      : colorScheme.onSurface.withValues(alpha: 0.75),
                                ),
                              ),
                            ],
                          ),
                        ),
                      Text(
                        message.content,
                        style: TextStyle(
                          color: isMe ? Colors.white : colorScheme.onSurface,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            time,
                            style: TextStyle(
                              fontSize: 11,
                              color: isMe
                                  ? Colors.white.withValues(alpha: 0.7)
                                  : colorScheme.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                          if (isMe) ...[
                            const SizedBox(width: 4),
                            Icon(
                              message.status == 'read'
                                  ? Icons.done_all
                                  : message.status == 'delivered'
                                      ? Icons.done_all
                                      : Icons.done,
                              size: 14,
                              color: message.status == 'read'
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.7),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (message.reactions.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(
                left: isMe ? 0 : 40,
                right: isMe ? 40 : 0,
                top: 2,
                bottom: 4,
              ),
              child: Wrap(
                spacing: 6,
                children: [
                  for (final entry in message.reactions.entries)
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: onReactionTap != null ? () => onReactionTap!(entry.key) : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF1B4EBA).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          '${entry.key} ${entry.value.length}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
