import 'package:hive/hive.dart';
import '../models/chat_message.dart';

/// Hand-written Hive TypeAdapter for ChatMessage.
/// typeId: 4 — bumped from 3 to support new fields (reply, reactions,
/// group chat, forwarding, favorites).
///
/// Field indices:
///   0:  id (String)
///   1:  roomId (String)
///   2:  senderId (String)
///   3:  receiverId (String)
///   4:  content (String)
///   5:  messageType (String)
///   6:  status (String)
///   7:  timestamp (DateTime)
///   8:  serverTimestamp (DateTime?)
///   9:  fileName (String?)
///   10: mimeType (String?)
///   11: attachmentBase64 (String?)
///   12: attachmentSize (int?)
///   13: replyToMessageId (String?)
///   14: replyToContent (String?)
///   15: replyToSenderId (String?)
///   16: reactions (Map<String, List<String>>)
///   17: groupId (String?)
///   18: forwardedFrom (String?)
///   19: isFavorite (bool)
class ChatMessageAdapter extends TypeAdapter<ChatMessage> {
  @override
  final int typeId = 4;

  @override
  ChatMessage read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ChatMessage(
      id: fields[0] as String,
      roomId: fields[1] as String,
      senderId: fields[2] as String,
      receiverId: fields[3] as String,
      content: fields[4] as String,
      messageType: fields[5] as String? ?? 'text',
      fileName: fields[9] as String?,
      mimeType: fields[10] as String?,
      attachmentBase64: fields[11] as String?,
      attachmentSize: fields[12] as int?,
      status: fields[6] as String? ?? 'sent',
      timestamp: fields[7] as DateTime,
      serverTimestamp: fields[8] as DateTime?,
      replyToMessageId: fields[13] as String?,
      replyToContent: fields[14] as String?,
      replyToSenderId: fields[15] as String?,
      reactions: _parseReactions(fields[16]),
      groupId: fields[17] as String?,
      forwardedFrom: fields[18] as String?,
      isFavorite: fields[19] as bool? ?? false,
    );
  }

  Map<String, List<String>> _parseReactions(dynamic raw) {
    if (raw == null) return {};
    if (raw is Map) {
      final result = <String, List<String>>{};
      for (final entry in raw.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (value is List) {
          result[key] = value.map((e) => e.toString()).toList();
        }
      }
      return result;
    }
    return {};
  }

  @override
  void write(BinaryWriter writer, ChatMessage obj) {
    writer.writeByte(20); // number of fields
    writer.writeByte(0);
    writer.write(obj.id);
    writer.writeByte(1);
    writer.write(obj.roomId);
    writer.writeByte(2);
    writer.write(obj.senderId);
    writer.writeByte(3);
    writer.write(obj.receiverId);
    writer.writeByte(4);
    writer.write(obj.content);
    writer.writeByte(5);
    writer.write(obj.messageType);
    writer.writeByte(6);
    writer.write(obj.status);
    writer.writeByte(7);
    writer.write(obj.timestamp);
    writer.writeByte(8);
    writer.write(obj.serverTimestamp);
    writer.writeByte(9);
    writer.write(obj.fileName);
    writer.writeByte(10);
    writer.write(obj.mimeType);
    writer.writeByte(11);
    writer.write(obj.attachmentBase64);
    writer.writeByte(12);
    writer.write(obj.attachmentSize);
    writer.writeByte(13);
    writer.write(obj.replyToMessageId);
    writer.writeByte(14);
    writer.write(obj.replyToContent);
    writer.writeByte(15);
    writer.write(obj.replyToSenderId);
    writer.writeByte(16);
    // Serialize reactions as Map<String, List<String>>
    writer.write(obj.reactions);
    writer.writeByte(17);
    writer.write(obj.groupId);
    writer.writeByte(18);
    writer.write(obj.forwardedFrom);
    writer.writeByte(19);
    writer.write(obj.isFavorite);
  }
}
