library;

class ChatMessage {
  final String id;
  final String roomId;
  final String senderId;
  final String receiverId;
  final String content;
  final String messageType;
  final String? fileName;
  final String? mimeType;
  final String? attachmentBase64;
  final int? attachmentSize;
  final String status;
  final DateTime timestamp;
  final DateTime? serverTimestamp;
  final String? replyToMessageId;
  final String? replyToContent;
  final String? replyToSenderId;
  final Map<String, List<String>> reactions;
  final String? groupId;
  final String? forwardedFrom;
  final bool isFavorite;

  ChatMessage({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.receiverId,
    required this.content,
    this.messageType = 'text',
    this.fileName,
    this.mimeType,
    this.attachmentBase64,
    this.attachmentSize,
    this.status = 'sending',
    required this.timestamp,
    this.serverTimestamp,
    this.replyToMessageId,
    this.replyToContent,
    this.replyToSenderId,
    this.reactions = const {},
    this.groupId,
    this.forwardedFrom,
    this.isFavorite = false,
  });
  static String deriveRoomId(String userA, String userB) {
    if (userA.isEmpty || userB.isEmpty) {
      throw ArgumentError('User IDs cannot be empty');
    }
    final sorted = [userA, userB]..sort();
    return sorted.join('_');
  }
  static String deriveGroupRoomId(String groupId) {
    return 'group_$groupId';
  }
  bool validateRoomId() {
    if (groupId != null) return true;
    final expectedRoomId = deriveRoomId(senderId, receiverId);
    return roomId == expectedRoomId;
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final reactionsRaw = json['reactions'] as Map<String, dynamic>?;
    final reactions = <String, List<String>>{};
    if (reactionsRaw != null) {
      for (final entry in reactionsRaw.entries) {
        final users = (entry.value as List?)?.map((e) => e.toString()).toList();
        if (users != null && users.isNotEmpty) {
          reactions[entry.key] = users;
        }
      }
    }

    final message = ChatMessage(
      id: json['id'] as String,
      roomId: json['roomId'] as String,
      senderId: json['senderId'] as String,
      receiverId: json['receiverId'] as String,
      content: json['content'] as String,
      messageType: json['messageType'] as String? ?? 'text',
      fileName: json['fileName'] as String?,
      mimeType: json['mimeType'] as String?,
      attachmentBase64: json['attachmentBase64'] as String?,
      attachmentSize: (json['attachmentSize'] as num?)?.toInt(),
      status: json['status'] as String? ?? 'sent',
      timestamp: DateTime.parse(json['timestamp'] as String),
      serverTimestamp: json['serverTimestamp'] != null
          ? DateTime.parse(json['serverTimestamp'] as String)
          : null,
      replyToMessageId: json['replyToMessageId'] as String?,
      replyToContent: json['replyToContent'] as String?,
      replyToSenderId: json['replyToSenderId'] as String?,
      reactions: reactions,
      groupId: json['groupId'] as String?,
      forwardedFrom: json['forwardedFrom'] as String?,
      isFavorite: json['isFavorite'] as bool? ?? false,
    );
    if (message.groupId == null && !message.validateRoomId()) {
      throw FormatException(
        'Invalid room ID: expected ${ChatMessage.deriveRoomId(message.senderId, message.receiverId)}, '
        'but got ${message.roomId} for message between ${message.senderId} and ${message.receiverId}',
      );
    }

    return message;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'roomId': roomId,
      'senderId': senderId,
      'receiverId': receiverId,
      'content': content,
      'messageType': messageType,
      if (fileName != null) 'fileName': fileName,
      if (mimeType != null) 'mimeType': mimeType,
      if (attachmentBase64 != null) 'attachmentBase64': attachmentBase64,
      if (attachmentSize != null) 'attachmentSize': attachmentSize,
      'status': status,
      'timestamp': timestamp.toIso8601String(),
      if (serverTimestamp != null)
        'serverTimestamp': serverTimestamp!.toIso8601String(),
      if (replyToMessageId != null) 'replyToMessageId': replyToMessageId,
      if (replyToContent != null) 'replyToContent': replyToContent,
      if (replyToSenderId != null) 'replyToSenderId': replyToSenderId,
      if (reactions.isNotEmpty) 'reactions': reactions,
      if (groupId != null) 'groupId': groupId,
      if (forwardedFrom != null) 'forwardedFrom': forwardedFrom,
      'isFavorite': isFavorite,
    };
  }

  ChatMessage copyWith({
    String? id,
    String? roomId,
    String? senderId,
    String? receiverId,
    String? content,
    String? messageType,
    String? fileName,
    String? mimeType,
    String? attachmentBase64,
    int? attachmentSize,
    String? status,
    DateTime? timestamp,
    DateTime? serverTimestamp,
    String? replyToMessageId,
    String? replyToContent,
    String? replyToSenderId,
    Map<String, List<String>>? reactions,
    String? groupId,
    String? forwardedFrom,
    bool? isFavorite,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      roomId: roomId ?? this.roomId,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      content: content ?? this.content,
      messageType: messageType ?? this.messageType,
      fileName: fileName ?? this.fileName,
      mimeType: mimeType ?? this.mimeType,
      attachmentBase64: attachmentBase64 ?? this.attachmentBase64,
      attachmentSize: attachmentSize ?? this.attachmentSize,
      status: status ?? this.status,
      timestamp: timestamp ?? this.timestamp,
      serverTimestamp: serverTimestamp ?? this.serverTimestamp,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      replyToContent: replyToContent ?? this.replyToContent,
      replyToSenderId: replyToSenderId ?? this.replyToSenderId,
      reactions: reactions ?? this.reactions,
      groupId: groupId ?? this.groupId,
      forwardedFrom: forwardedFrom ?? this.forwardedFrom,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }
  ChatMessage toggleReaction(String userId, String emoji, [String? action]) {
    final newReactions = Map<String, List<String>>.from(
      reactions.map((k, v) => MapEntry(k, List<String>.from(v))),
    );
    final users = newReactions[emoji] ?? [];
    final shouldRemove = action == 'remove'
        ? true
        : action == 'add'
        ? false
        : users.contains(userId);

    if (shouldRemove) {
      users.remove(userId);
      if (users.isEmpty) {
        newReactions.remove(emoji);
      } else {
        newReactions[emoji] = users;
      }
    } else {
      if (!users.contains(userId)) {
        newReactions[emoji] = [...users, userId];
      }
    }
    return copyWith(reactions: newReactions);
  }

  @override
  String toString() =>
      'ChatMessage(id: $id, room: $roomId, from: $senderId, status: $status, type: $messageType)';
}
