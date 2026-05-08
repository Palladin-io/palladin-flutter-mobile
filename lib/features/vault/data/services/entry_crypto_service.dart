import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium_libs/sodium_libs_sumo.dart';

import '../../../../core/crypto/sodium_provider.dart';
import '../../../../core/utils/app_logger.dart';
import '../../domain/exceptions/entry_exceptions.dart';
import '../models/entry_model.dart';

/// Zero-knowledge crypto pipeline for vault entries.
///
/// Two responsibilities:
///   * [unwrapVK] — decrypt the per-vault sealed VK using the user's
///     X25519 private key. The plaintext VK lives in memory only for
///     the duration of the surrounding encrypt/decrypt call.
///   * [encryptEntry] / [decryptEntry] — symmetric `crypto_secretbox_easy`
///     using VK as the symmetric key. Plaintext payload (a JSON map) is
///     UTF-8 encoded; ciphertext + nonce are base64-encoded inside an
///     [EntryContentModel] envelope.
///
/// All methods that hold raw key bytes wrap them in `try/finally` and
/// zero them out before returning so we never leave secret material
/// lingering on the heap.
class EntryCryptoService {
  EntryCryptoService({Future<SodiumSumo> Function()? sodiumLoader})
      : _sodiumLoader = sodiumLoader ?? SodiumProvider.instance;

  final Future<SodiumSumo> Function() _sodiumLoader;

  /// Unwraps the base64-encoded sealed VK using the X25519 [privateKey]
  /// from the unlocked auth state. Returns the raw 32-byte VK as a
  /// `Uint8List` — the caller is responsible for zeroing it out after
  /// use.
  ///
  /// Throws [EntryException] with [EntryErrorKind.cryptoFailure] if the
  /// sealed box cannot be opened (member kicked from vault, tampered
  /// blob, …).
  Future<Uint8List> unwrapVK({
    required String wrappedVK,
    required Uint8List privateKey,
  }) async {
    final sodium = await _sodiumLoader();
    final scalar = SecureKey.fromList(sodium, privateKey);
    try {
      final publicKey = sodium.crypto.scalarmult.base(n: scalar);
      final sealed = base64.decode(wrappedVK);
      try {
        return sodium.crypto.box.sealOpen(
          cipherText: sealed,
          publicKey: publicKey,
          secretKey: scalar,
        );
      } on SodiumException catch (e, s) {
        AppLogger.w('Entry', 'unwrapVK failed: ${e.runtimeType}');
        AppLogger.e('Entry', 'sealOpen failed', error: e, stackTrace: s);
        throw const EntryException(EntryErrorKind.cryptoFailure);
      }
    } finally {
      scalar.dispose();
    }
  }

  /// Encrypts a JSON [payload] with [vaultKey] using `crypto_secretbox_easy`
  /// and wraps the result in an [EntryContentModel] envelope tagged with
  /// the [entryType] discriminator the backend expects.
  ///
  /// The plaintext bytes and the [SecureKey] wrapping [vaultKey] are
  /// zeroed out before this method returns regardless of success or
  /// failure.
  Future<EntryContentModel> encryptEntry({
    required Map<String, dynamic> payload,
    required Uint8List vaultKey,
    required int entryType,
  }) async {
    final sodium = await _sodiumLoader();
    final secretKey = SecureKey.fromList(sodium, vaultKey);
    final plaintext = utf8.encode(jsonEncode(payload));
    try {
      final nonce = sodium.randombytes.buf(sodium.crypto.secretBox.nonceBytes);
      final cipher = sodium.crypto.secretBox.easy(
        message: plaintext,
        nonce: nonce,
        key: secretKey,
      );
      return EntryContentModel(
        entryType: entryType,
        encryptedBlob: base64.encode(cipher),
        nonce: base64.encode(nonce),
      );
    } finally {
      // Zeroize the plaintext bytes — `payload` may contain a password
      // or API key. The serialized JSON copy on the heap could otherwise
      // outlive this call.
      plaintext.fillRange(0, plaintext.length, 0);
      secretKey.dispose();
    }
  }

  /// Decrypts the ciphertext + nonce inside [content] with [vaultKey]
  /// and returns the deserialized JSON payload.
  ///
  /// Throws [EntryException] with [EntryErrorKind.cryptoFailure] when
  /// `crypto_secretbox_open_easy` fails (tampered blob / wrong VK) or
  /// when the resulting bytes are not valid UTF-8 JSON.
  Future<Map<String, dynamic>> decryptEntry({
    required EntryContentModel content,
    required Uint8List vaultKey,
  }) async {
    final sodium = await _sodiumLoader();
    final secretKey = SecureKey.fromList(sodium, vaultKey);
    Uint8List? plaintext;
    try {
      final cipher = base64.decode(content.encryptedBlob);
      final nonceBytes = base64.decode(content.nonce);
      try {
        plaintext = sodium.crypto.secretBox.openEasy(
          cipherText: cipher,
          nonce: nonceBytes,
          key: secretKey,
        );
      } on SodiumException catch (e, s) {
        AppLogger.w('Entry', 'decryptEntry MAC verification failed');
        AppLogger.e('Entry', 'openEasy failed', error: e, stackTrace: s);
        throw const EntryException(EntryErrorKind.cryptoFailure);
      }
      try {
        return jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
      } on FormatException catch (e, s) {
        AppLogger.e('Entry', 'decrypted blob is not valid JSON',
            error: e, stackTrace: s);
        throw const EntryException(EntryErrorKind.cryptoFailure);
      }
    } finally {
      if (plaintext != null) {
        plaintext.fillRange(0, plaintext.length, 0);
      }
      secretKey.dispose();
    }
  }
}
