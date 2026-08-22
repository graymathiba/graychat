import 'package:flutter_test/flutter_test.dart';
import 'package:grychat/core/providers/chat_provider.dart';

void main() {
  group('MyShortCodeNotifier._deriveShortCode', () {
    test('matches backend generateShortCodeFromHash output', () {
      final expected = <String, String>{
        'user_a': 'GRY-VXRU',
        'user_b': 'GRY-VZAS',
        'test-user-id-123': 'GRY-H412',
        'user123': 'GRY-MANC',
      };
      expected.forEach((userId, code) {
        expect(MyShortCodeNotifier.deriveShortCodeForTest(userId), equals(code),
            reason: 'Code mismatch for userId: $userId');
      });
    });

    test('is deterministic', () {
      expect(
        MyShortCodeNotifier.deriveShortCodeForTest('some-user'),
        equals(MyShortCodeNotifier.deriveShortCodeForTest('some-user')),
      );
    });

    test('produces GRY-XXXX format', () {
      final code = MyShortCodeNotifier.deriveShortCodeForTest('abc');
      expect(RegExp(r'^GRY-[0-9A-Z]{4}$').hasMatch(code), isTrue);
    });
  });
}
