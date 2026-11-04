import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart' as sodium_ffi;
import 'package:sodium_libs/sodium_libs_sumo.dart';

String get _libraryPath =>
    Platform.environment['PALLADIN_LIBSODIUM_PATH'] ?? 'libsodium.so';

/// Loads host libsodium for crypto tests (CI: apt `libsodium-dev`).
Future<SodiumSumo> loadTestSodium() {
  final configured = Platform.environment['PALLADIN_LIBSODIUM_PATH'];
  if (configured != null || Platform.isLinux) {
    return sodium_ffi.SodiumSumoInit.init(
      () => DynamicLibrary.open(_libraryPath),
    );
  }
  return SodiumSumoInit.init();
}

Map<String, dynamic> readJsonFixture(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

Uint8List hexBytes(String value) => Uint8List.fromList([
  for (var i = 0; i < value.length; i += 2)
    int.parse(value.substring(i, i + 2), radix: 16),
]);

String toHex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

Uint8List b64urlBytes(String value) =>
    Uint8List.fromList(base64Url.decode(base64Url.normalize(value)));

String b64url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

typedef _SeedKeypair =
    Int32 Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>);
typedef _SeedKeypairDart =
    int Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>);
typedef _Enc =
    Int32 Function(
      Pointer<Uint8>,
      Pointer<Uint8>,
      Pointer<Uint8>,
      Pointer<Uint8>,
    );
typedef _EncDart =
    int Function(
      Pointer<Uint8>,
      Pointer<Uint8>,
      Pointer<Uint8>,
      Pointer<Uint8>,
    );
typedef _Malloc = Pointer<Void> Function(IntPtr);
typedef _MallocDart = Pointer<Void> Function(int);
typedef _Free = Void Function(Pointer<Void>);
typedef _FreeDart = void Function(Pointer<Void>);

/// Independent libsodium (>= 1.0.22) X-Wing used as a differential oracle.
/// Returns null when the host library predates `crypto_kem_xwing`.
final class NativeXWing {
  NativeXWing._(this._seedKeypair, this._encDeterministic, this._dec);

  final _SeedKeypairDart _seedKeypair;
  final _EncDart _encDeterministic;
  final _SeedKeypairDart _dec;

  static final _process = DynamicLibrary.process();
  static final _malloc = _process.lookupFunction<_Malloc, _MallocDart>(
    'malloc',
  );
  static final _free = _process.lookupFunction<_Free, _FreeDart>('free');

  static NativeXWing? tryLoad() {
    try {
      final library = DynamicLibrary.open(
        Platform.environment['PALLADIN_LIBSODIUM_PATH'] ??
            (Platform.isLinux ? 'libsodium.so' : 'libsodium.dylib'),
      );
      if (library.lookupFunction<Int32 Function(), int Function()>(
            'sodium_init',
          )() <
          0) {
        return null;
      }
      return NativeXWing._(
        library.lookupFunction<_SeedKeypair, _SeedKeypairDart>(
          'crypto_kem_xwing_seed_keypair',
        ),
        library.lookupFunction<_Enc, _EncDart>(
          'crypto_kem_xwing_enc_deterministic',
        ),
        library.lookupFunction<_SeedKeypair, _SeedKeypairDart>(
          'crypto_kem_xwing_dec',
        ),
      );
    } on ArgumentError {
      return null;
    }
  }

  Uint8List publicKey(Uint8List seed) => _run(
    [1216, 32, 32],
    [null, null, seed],
    (p) => _seedKeypair(p[0], p[1], p[2]),
  )[0];

  (Uint8List, Uint8List) encapsulate(
    Uint8List publicKey,
    Uint8List randomness,
  ) {
    final out = _run(
      [1120, 32, 1216, 64],
      [null, null, publicKey, randomness],
      (p) => _encDeterministic(p[0], p[1], p[2], p[3]),
    );
    return (out[1], out[0]);
  }

  Uint8List decapsulate(Uint8List ciphertext, Uint8List seed) => _run(
    [32, 1120, 32],
    [null, ciphertext, seed],
    (p) => _dec(p[0], p[1], p[2]),
  )[0];

  List<Uint8List> _run(
    List<int> sizes,
    List<Uint8List?> inputs,
    int Function(List<Pointer<Uint8>>) call,
  ) {
    final pointers = [for (final size in sizes) _malloc(size).cast<Uint8>()];
    try {
      for (var i = 0; i < inputs.length; i++) {
        final input = inputs[i];
        if (input != null) pointers[i].asTypedList(sizes[i]).setAll(0, input);
      }
      if (call(pointers) != 0) throw StateError('native X-Wing failed');
      return [
        for (var i = 0; i < sizes.length; i++)
          Uint8List.fromList(pointers[i].asTypedList(sizes[i])),
      ];
    } finally {
      for (final pointer in pointers) {
        _free(pointer.cast());
      }
    }
  }
}
