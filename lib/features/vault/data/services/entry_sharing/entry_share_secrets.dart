import 'dart:typed_data';

import '../../../domain/entities/entry_share.dart';
import '../vault_protocol/vault_protocol_bytes.dart';

/// Explicit RAM ownership. No serialization or persistence API by design.
final class EntryShareSecrets {
  EntryShareSecrets({required this.key, required this.accessToken});
  final Uint8List key, accessToken;
  bool _disposed = false;

  String toFragment() {
    if (_disposed || key.length != 32 || accessToken.length != 32) {
      throw const EntryShareException(EntryShareErrorKind.invalidLink);
    }
    return '#v=1&key=${VaultProtocolBytes.base64UrlEncode(key)}&access=${VaultProtocolBytes.base64UrlEncode(accessToken)}';
  }

  factory EntryShareSecrets.fromFragment(String fragment) {
    Uint8List? key;
    Uint8List? bearer;
    try {
      final match = RegExp(
        r'^#v=1&key=([A-Za-z0-9_-]{43})&access=([A-Za-z0-9_-]{43})$',
      ).firstMatch(fragment);
      if (match == null) {
        throw const EntryShareException(EntryShareErrorKind.invalidLink);
      }
      key = VaultProtocolBytes.base64UrlDecode(match[1]!, maximumBytes: 32);
      bearer = VaultProtocolBytes.base64UrlDecode(match[2]!, maximumBytes: 32);
      if (key.length != 32 || bearer.length != 32) {
        throw const EntryShareException(EntryShareErrorKind.invalidLink);
      }
      return EntryShareSecrets(key: key, accessToken: bearer);
    } catch (_) {
      key?.fillRange(0, key.length, 0);
      bearer?.fillRange(0, bearer.length, 0);
      throw const EntryShareException(EntryShareErrorKind.invalidLink);
    }
  }

  void dispose() {
    _disposed = true;
    key.fillRange(0, key.length, 0);
    accessToken.fillRange(0, accessToken.length, 0);
  }
}
