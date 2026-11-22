import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

/// Cryptographic helpers matching JMComic3 `v2.1.9` (`HttpUtil.ts` & `Function.js`).
class JmCrypto {
  static const String appVersion = '2.1.9';
  static const String primarySecret = '185Hcomic3PAPP7R';
  static const String secondarySecret = '18comicAPPContent';
  static const String hostListSecret = 'diosfjckwpqpdfjkvnqQjsik';

  static String md5Hex(String input) {
    return md5.convert(utf8.encode(input)).toString();
  }

  /// Builds `Tokenparam` and `Token` headers bound to [timestamp] (UTC epoch seconds).
  static Map<String, String> buildHeaders(
    int timestamp, {
    String? jwtToken,
    String? avsCookie,
  }) {
    final headers = <String, String>{
      'Tokenparam': '$timestamp,$appVersion',
      'Token': md5Hex('$timestamp$primarySecret'),
      'Accept': 'application/json, text/plain, */*',
    };
    if (jwtToken != null && jwtToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $jwtToken';
    }
    if (avsCookie != null && avsCookie.isNotEmpty) {
      headers['Cookie'] = 'AVS=$avsCookie';
    }
    return headers;
  }

  /// Decrypts the dynamic server discovery payload (`newsvr-2025.txt` or backup `hostCode`).
  static Map<String, dynamic> decryptHostTxt(String encryptedBase64) {
    final keyHex = md5Hex(hostListSecret);
    final key = enc.Key.fromUtf8(keyHex);
    final encrypter = enc.Encrypter(
      enc.AES(key, mode: enc.AESMode.ecb, padding: 'PKCS7'),
    );
    final clean = encryptedBase64.replaceAll(RegExp(r'\s+'), '');
    final plain = encrypter.decrypt64(clean);
    final decoded = jsonDecode(plain);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    throw const FormatException('Unexpected host payload JSON type');
  }

  /// Decrypts an encrypted JMComic3 API `data` field using the request [timestamp].
  static dynamic decryptApiPayload(dynamic rawData, int timestamp) {
    if (rawData == null) return null;
    if (rawData is Map || rawData is List) {
      return rawData;
    }
    final cipherB64 = rawData.toString().replaceAll(RegExp(r'\s+'), '');
    if (cipherB64.isEmpty) return null;

    // If plain JSON string was returned, parse directly.
    if (cipherB64.startsWith('{') || cipherB64.startsWith('[')) {
      return jsonDecode(cipherB64);
    }

    for (final secret in const [primarySecret, secondarySecret]) {
      try {
        final keyHex = md5Hex('$timestamp$secret');
        final key = enc.Key.fromUtf8(keyHex);
        final encrypter = enc.Encrypter(
          enc.AES(key, mode: enc.AESMode.ecb, padding: 'PKCS7'),
        );
        final decrypted = encrypter.decrypt64(cipherB64);
        return jsonDecode(decrypted);
      } catch (_) {
        // Try next secret.
      }
    }

    throw const FormatException('无法解密 JMComic API 响应数据');
  }
}
