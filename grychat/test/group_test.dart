import 'package:flutter_test/flutter_test.dart';
import 'package:grychat/core/models/group.dart';

void main() {
  group('Group', () {
    test('toJson/fromJson roundtrip', () {
      final group = Group(
        id: 'group-123',
        name: 'Test Group',
        creatorId: 'creator-1',
        memberIds: ['user1', 'user2', 'user3'],
        createdAt: DateTime(2025, 6, 15),
      );

      final json = group.toJson();
      final restored = Group.fromJson(json);

      expect(restored.id, equals(group.id));
      expect(restored.name, equals(group.name));
      expect(restored.creatorId, equals(group.creatorId));
      expect(restored.memberIds, equals(group.memberIds));
    });

    test('copyWith preserves unchanged fields', () {
      final group = Group(
        id: 'id',
        name: 'Original Name',
        creatorId: 'creator',
        memberIds: ['a', 'b'],
        createdAt: DateTime(2025, 1, 1),
      );

      final updated = group.copyWith(name: 'New Name');
      expect(updated.name, equals('New Name'));
      expect(updated.id, equals('id'));
      expect(updated.memberIds, equals(['a', 'b']));
    });

    test('fromJson handles null memberIds', () {
      final json = {
        'id': 'id',
        'name': 'name',
        'creatorId': 'creator',
        'memberIds': null,
        'createdAt': DateTime.now().toIso8601String(),
      };

      final group = Group.fromJson(json);
      expect(group.memberIds, isEmpty);
    });
  });
}
