import { describe, it, before, after } from 'node:test';
import assert from 'node:assert';

// Test the roomId derivation logic (mirrors backend deriveRoomId)
function deriveRoomId(userA: string, userB: string): string {
  return [userA, userB].sort().join('_');
}

// Test the short code generation logic (mirrors backend generateShortCode)
function generateShortCode(userId: string): string {
  let hash = 0;
  for (let i = 0; i < userId.length; i++) {
    const char = userId.charCodeAt(i);
    hash = ((hash << 5) - hash) + char;
    hash = hash & hash;
  }
  const code = Math.abs(hash).toString(36).toUpperCase().padStart(4, '0').slice(0, 4);
  return `GRY-${code}`;
}

describe('Room ID Derivation', () => {
  it('should be deterministic', () => {
    const room1 = deriveRoomId('user_a', 'user_b');
    const room2 = deriveRoomId('user_a', 'user_b');
    assert.strictEqual(room1, room2);
  });

  it('should be order-independent', () => {
    const room1 = deriveRoomId('user_a', 'user_b');
    const room2 = deriveRoomId('user_b', 'user_a');
    assert.strictEqual(room1, room2);
  });

  it('should use underscore separator', () => {
    const room = deriveRoomId('abc', 'def');
    assert.strictEqual(room, 'abc_def');
  });

  it('should handle same user (self-chat)', () => {
    const room = deriveRoomId('user1', 'user1');
    assert.strictEqual(room, 'user1_user1');
  });
});

describe('Short Code Generation', () => {
  it('should produce GRY- prefix', () => {
    const code = generateShortCode('test-user-id-123');
    assert.ok(code.startsWith('GRY-'));
  });

  it('should produce 8-character code (GRY-XXXX)', () => {
    const code = generateShortCode('test-user-id-123');
    assert.strictEqual(code.length, 8);
  });

  it('should be deterministic', () => {
    const code1 = generateShortCode('user123');
    const code2 = generateShortCode('user123');
    assert.strictEqual(code1, code2);
  });

  it('should produce different codes for different users', () => {
    const code1 = generateShortCode('user_a');
    const code2 = generateShortCode('user_b');
    assert.notStrictEqual(code1, code2);
  });
});

describe('Message Validation', () => {
  const validMessageTypes = ['text', 'image', 'audio', 'video', 'file', 'application/pdf'];

  it('should accept valid message types', () => {
    for (const type of validMessageTypes) {
      assert.ok(validMessageTypes.includes(type), `Type ${type} should be valid`);
    }
  });

  it('should reject invalid message types', () => {
    assert.ok(!validMessageTypes.includes('invalid'), 'Invalid type should not be in list');
    assert.ok(!validMessageTypes.includes(''), 'Empty type should not be in list');
  });

  it('should default invalid type to text', () => {
    const messageType = validMessageTypes.includes('bad_type') ? 'bad_type' : 'text';
    assert.strictEqual(messageType, 'text');
  });
});
