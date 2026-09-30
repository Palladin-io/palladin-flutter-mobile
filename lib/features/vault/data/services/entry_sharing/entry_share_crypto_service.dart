import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium_libs/sodium_libs_sumo.dart';
import '../../../../../core/crypto/sodium_provider.dart';
import '../../../domain/entities/entry_share.dart';
import '../vault_protocol/vault_protocol_bytes.dart';
import 'entry_share_aad.dart';
import 'entry_share_secrets.dart';

final class PreparedEntryShare {
  const PreparedEntryShare({required this.packet, required this.secrets});
  final EntryShareCiphertext packet;
  final EntryShareSecrets secrets;
  void dispose() => secrets.dispose();
}

/// Only this service seals/opens sharing snapshots. Neither MK/VK nor EntryDEK
/// is an input. The caller owns the returned in-memory capability until disposal.
final class EntryShareCryptoService {
  EntryShareCryptoService({Future<SodiumSumo> Function()? sodiumLoader})
    : _sodiumLoader = sodiumLoader ?? SodiumProvider.instance;
  final Future<SodiumSumo> Function() _sodiumLoader;
  static const maximumCiphertextBytes = 262144;

  Future<PreparedEntryShare> prepare({
    required EntryShareScope scope,
    required EntryShareSnapshot snapshot,
  }) async {
    Uint8List? plaintext;
    Uint8List? key;
    Uint8List? bearer;
    SecureKey? secureKey;
    try {
      final aad = entryShareAad(scope);
      plaintext = utf8.encode(jsonEncode(snapshot.toJson()));
      if (plaintext.length + 16 > maximumCiphertextBytes) {
        throw const EntryShareException(EntryShareErrorKind.invalidSnapshot);
      }
      final sodium = await _sodiumLoader();
      key = sodium.randombytes.buf(32);
      bearer = sodium.randombytes.buf(32);
      secureKey = SecureKey.fromList(sodium, key);
      final nonce = sodium.randombytes.buf(24);
      final ciphertext = sodium.crypto.aeadXChaCha20Poly1305IETF.encrypt(
        message: plaintext,
        nonce: nonce,
        key: secureKey,
        additionalData: aad,
      );
      return PreparedEntryShare(
        packet: EntryShareCiphertext(
          nonce: base64Encode(nonce),
          ciphertext: base64Encode(ciphertext),
        ),
        secrets: EntryShareSecrets(key: key, accessToken: bearer),
      );
    } catch (_) {
      key?.fillRange(0, key.length, 0);
      bearer?.fillRange(0, bearer.length, 0);
      throw const EntryShareException(EntryShareErrorKind.invalidSnapshot);
    } finally {
      secureKey?.dispose();
      plaintext?.fillRange(0, plaintext.length, 0);
    }
  }

  Future<EntryShareSnapshot> open({
    required EntryShareCiphertext packet,
    required EntryShareScope authority,
    required String requestedShareId,
    required Uint8List key,
  }) async {
    // Borrowed caller keys can be wiped while sodium initialization is awaiting.
    // Copy now, then the caller's generation guard decides whether to publish.
    final keyCopy = Uint8List.fromList(key);
    Uint8List? plaintext;
    SecureKey? secureKey;
    try {
      if (authority.shareId != requestedShareId || keyCopy.length != 32) {
        throw const EntryShareException(EntryShareErrorKind.invalidSnapshot);
      }
      final aad = entryShareAad(authority);
      final nonce = VaultProtocolBytes.base64Decode(
        packet.nonce,
        maximumBytes: 24,
      );
      final ciphertext = VaultProtocolBytes.base64Decode(
        packet.ciphertext,
        maximumBytes: maximumCiphertextBytes,
      );
      if (nonce.length != 24 || ciphertext.length < 16) {
        throw const EntryShareException(EntryShareErrorKind.invalidSnapshot);
      }
      final sodium = await _sodiumLoader();
      secureKey = SecureKey.fromList(sodium, keyCopy);
      plaintext = sodium.crypto.aeadXChaCha20Poly1305IETF.decrypt(
        cipherText: ciphertext,
        nonce: nonce,
        key: secureKey,
        additionalData: aad,
      );
      return EntryShareSnapshot.fromJson(jsonDecode(utf8.decode(plaintext)));
    } catch (_) {
      throw const EntryShareException(EntryShareErrorKind.invalidSnapshot);
    } finally {
      secureKey?.dispose();
      keyCopy.fillRange(0, keyCopy.length, 0);
      plaintext?.fillRange(0, plaintext.length, 0);
    }
  }
}
