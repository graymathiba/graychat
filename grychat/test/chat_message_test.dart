import 'package:flutter_test/flutter_test.dart';
import 'package:grychat/core/models/chat_message.dart';

void main() {
  group('ChatMessage', () {
    test('deriveRoomId is deterministic and order-independent', () {
      final room1 = ChatMessage.deriveRoomId('user_a', 'user_b');
      final room2 = ChatMessage.deriveRoomId('user_b', 'user_a');
      expect(room1, equals(room2));
      expect(room1, contains('user_a'));
      expect(room1, contains('user_b'));
    });

    test('deriveRoomId uses underscore separator', () {
      final room = ChatMessage.deriveRoomId('abc', 'def');
      expect(room, equals('abc_def'));
    });

    test('toJson/fromJson roundtrip preserves all fields', () {
      final now = DateTime.now();
      final msg = ChatMessage(
        id: 'test-id-123',
        roomId: 'room_abc',
        senderId: 'sender_1',
        receiverId: 'receiver_2',
        content: 'Hello world',
        messageType: 'text',
        status: 'sent',
        timestamp: now,
        fileName: null,
        mimeType: null,
        attachmentBase64: null,
        attachmentSize: null,
        serverTimestamp: now,
        replyToMessageId: null,
        replyToContent: null,
        replyToSenderId: null,
        reactions: {},
        groupId: null,
        forwardedFrom: null,
        isFavorite: false,
      );

      final json = msg.toJson();
      final restored = ChatMessage.fromJson(json);

      expect(restored.id, equals(msg.id));
      expect(restored.roomId, equals(msg.roomId));
      expect(restored.senderId, equals(msg.senderId));
      expect(restored.receiverId, equals(msg.receiverId));
      expect(restored.content, equals(msg.content));
      expect(restored.messageType, equals(msg.messageType));
      expect(restored.status, equals(msg.status));
    });

    test('copyWith preserves unchanged fields', () {
      final msg = ChatMessage(
        id: 'id-1',
        roomId: 'room_1',
        senderId: 'sender',
        receiverId: 'receiver',
        content: 'original',
        messageType: 'text',
        status: 'sending',
        timestamp: DateTime(2025, 1, 1),
      );

      final updated = msg.copyWith(status: 'sent');
      expect(updated.status, equals('sent'));
      expect(updated.content, equals('original'));
      expect(updated.id, equals('id-1'));
    });

    test('validateRoomId returns true for correctly derived roomId', () {
      final msg = ChatMessage(
        id: 'id',
        roomId: ChatMessage.deriveRoomId('user_a', 'user_b'),
        senderId: 'user_a',
        receiverId: 'user_b',
        content: 'test',
        messageType: 'text',
        status: 'sent',
        timestamp: DateTime.now(),
      );
      expect(msg.validateRoomId(), isTrue);
    });

    test('validateRoomId returns false for incorrect roomId', () {
      final msg = ChatMessage(
        id: 'id',
        roomId: 'wrong_room',
        senderId: 'user_a',
        receiverId: 'user_b',
        content: 'test',
        messageType: 'text',
        status: 'sent',
        timestamp: DateTime.now(),
      );
      expect(msg.validateRoomId(), isFalse);
    });

    test('toggleReaction adds emoji for user', () {
      final msg = ChatMessage(
        id: 'id',
        roomId: 'room',
        senderId: 'sender',
        receiverId: 'receiver',
        content: 'test',
        messageType: 'text',
        status: 'sent',
        timestamp: DateTime.now(),
        reactions: {},
      );

      final updated = msg.toggleReaction('user1', '👍', 'add');
      expect(updated.reactions['👍'], contains('user1'));
    });

    test('toggleReaction removes emoji for user', () {
      final msg = ChatMessage(
        id: 'id',
        roomId: 'room',
        senderId: 'sender',
        receiverId: 'receiver',
        content: 'test',
        messageType: 'text',
        status: 'sent',
        timestamp: DateTime.now(),
        reactions: {'👍': ['user1']},
      );

      final updated = msg.toggleReaction('user1', '👍', 'remove');
      expect(updated.reactions['👍'], isNot(contains('user1')));
    });
  });
}
