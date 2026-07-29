import 'dart:convert';
import 'package:encrypt/encrypt.dart';
import 'dart:typed_data';

/// Simple E2E encryption service using AES-256.
/// Each user pair derives a shared key from both user IDs.
class EncryptionService {
  /// Derive a symmetric key from two user IDs (order-independent).
  static Key deriveKey(String userId1, String userId2) {
    final sorted = [userId1, userId2]..sort();
    final combined = sorted.join(':');
    final bytes = utf8.encode(combined);
    final padded = List<int>.filled(32, 0);
    for (var i = 0; i < bytes.length && i < 32; i++) {
      padded[i] = bytes[i];
    }
    return Key(Uint8List.fromList(padded));
  }

  /// Encrypt a plaintext message.
  static Map<String, String> encryptMessage(String plaintext, String userId1, String userId2) {
    final key = deriveKey(userId1, userId2);
    final iv = IV.fromSecureRandom(16);
    final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
    final encrypted = encrypter.encrypt(plaintext, iv: iv);
    return {
      'ciphertext': encrypted.base64,
      'iv': iv.base64,
    };
  }

  /// Decrypt an encrypted message.
  static String decryptMessage(String ciphertext, String ivBase64, String userId1, String userId2) {
    final key = deriveKey(userId1, userId2);
    final iv = IV.fromBase64(ivBase64);
    final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
    final encrypted = Encrypted.fromBase64(ciphertext);
    return encrypter.decrypt(encrypted, iv: iv);
  }
}
