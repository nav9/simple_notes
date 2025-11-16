// lib/encryption_service.dart
import 'package:encrypt/encrypt.dart' as encrypt;

class EncryptionService {
  // NOTE: fixed IV kept for backwards compatibility with your app (as requested).
  static final iv = encrypt.IV.fromBase64('AAAAAAAAAAAAAAAAAAAAAA==');

  static String encryptText(String text, String password) {
    final key = encrypt.Key.fromUtf8(password.padRight(32, '\0'));
    final encrypter = encrypt.Encrypter(encrypt.AES(key));
    final encrypted = encrypter.encrypt(text, iv: iv);
    return "[ENCRYPTED]" + encrypted.base64;
  }

  static String? decryptText(String encryptedText, String password) {
    if (!encryptedText.startsWith("[ENCRYPTED]")) return null;
    try {
      final key = encrypt.Key.fromUtf8(password.padRight(32, '\0'));
      final encrypter = encrypt.Encrypter(encrypt.AES(key));
      final decrypted = encrypter.decrypt64(encryptedText.substring(11), iv: iv);
      return decrypted;
    } catch (e) {
      return null;
    }
  }
}
