// lib/encryption_service.dart
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:convert';

typedef EncryptFn = String Function(String text, String password);
typedef DecryptFn = String? Function(String text, String password);

class EncryptionService {
  static final iv = encrypt.IV.fromBase64('AAAAAAAAAAAAAAAAAAAAAA==');

  /// Registry of supported algorithms
  static final Map<String, _Algo> _algorithms = {
    'aes256': _Algo(encrypt: _encryptAES256, decrypt: _decryptAES256,),
    'fernet': _Algo(encrypt: _encryptFernet, decrypt: _decryptFernet,),
  };

  /// Algorithms enabled in Settings
  static List<String> _enabledAlgorithms() {
    final settings = Hive.box('settings');
    final algo = settings.get('encryptionAlgo', defaultValue: 'aes256');
    return [algo]; // encryption uses ONE
  }

  /// Encryption → use selected algorithm only
  static String encryptText(String text, String password) {
    final algoKey = _enabledAlgorithms().first;
    final algo = _algorithms[algoKey]!;
    return '[ENCRYPTED]' + algo.encrypt(text, password);
  }

  /// Decryption → try ALL algorithms
  static String? decryptText(String encryptedText, String password) {
    if (!encryptedText.startsWith('[ENCRYPTED]')) return null;
    final payload = encryptedText.substring(11);

    for (final algo in _algorithms.values) {
      try {
        final result = algo.decrypt(payload, password);
        if (result != null) return result;
      } catch (_) {}
    }
    return null;
  }

  // ---------------- AES-256 ----------------

static String _encryptAES256(String text, String password) {
  final key = encrypt.Key.fromUtf8(password.padRight(32, '\0'));
  final iv = encrypt.IV.fromSecureRandom(16);

  final aes = encrypt.AES(
    key,
    mode: encrypt.AESMode.cbc,
    padding: 'PKCS7',
  );

  final encrypter = encrypt.Encrypter(aes);
  final encrypted = encrypter.encrypt(text, iv: iv);

  // Store IV + ciphertext
  final combined = iv.bytes + encrypted.bytes;
  return base64Encode(combined);
}

static String? _decryptAES256(String payload, String password) {
  try {
    final raw = base64Decode(payload);
    final iv = encrypt.IV(raw.sublist(0, 16));
    final cipherText = raw.sublist(16);

    final key = encrypt.Key.fromUtf8(password.padRight(32, '\0'));
    final aes = encrypt.AES(key, mode: encrypt.AESMode.cbc,padding: 'PKCS7',);

    final encrypter = encrypt.Encrypter(aes);
    return encrypter.decrypt(encrypt.Encrypted(cipherText),iv: iv,);
  } catch (_) {
    return null;
  }
}


  // ---------------- FERNET ----------------

  static String _encryptFernet(String text, String password) {
    final key = encrypt.Key.fromUtf8(password.padRight(32, '\0'));
    final fernet = encrypt.Fernet(key);
    return encrypt.Encrypter(fernet).encrypt(text).base64;
  }

  static String? _decryptFernet(String payload, String password) {
    try {
      final key = encrypt.Key.fromUtf8(password.padRight(32, '\0'));
      final fernet = encrypt.Fernet(key);
      return encrypt.Encrypter(fernet).decrypt64(payload);
    } catch (_) {
      return null;
    }
  }
}

class _Algo {
  final EncryptFn encrypt;
  final DecryptFn decrypt;
  _Algo({required this.encrypt, required this.decrypt});
}
