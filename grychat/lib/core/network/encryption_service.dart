import 'dart:convert';
import 'package:encrypt/encrypt.dart';
import 'dart:typed_data';

class EncryptionService {
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

  static String decryptMessage(String ciphertext, String ivBase64, String userId1, String userId2) {
    final key = deriveKey(userId1, userId2);
    final iv = IV.fromBase64(ivBase64);
    final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
    final encrypted = Encrypted.fromBase64(ciphertext);
    return encrypter.decrypt(encrypted, iv: iv);
  }
}
