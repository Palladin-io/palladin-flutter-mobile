import 'package:sodium_libs/sodium_libs_sumo.dart';

/// Lazy-loads the libsodium native library and exposes a shared
/// [SodiumSumo] instance for all crypto operations.
///
/// Uses the "sumo" variant of libsodium which includes `crypto_pwhash`
/// (Argon2id) and `crypto_scalarmult` — both required for the
/// zero-knowledge onboarding flow.
///
/// The sodium binaries are bundled via the `sodium_libs` plugin and
/// loaded on first use; subsequent calls return the cached instance.
class SodiumProvider {
  SodiumProvider._();

  static SodiumSumo? _sodium;

  /// Returns the shared [SodiumSumo] instance, initializing it on first call.
  ///
  /// Thread-safe: the underlying `SodiumSumoInit.init()` handles
  /// concurrent initialization internally.
  static Future<SodiumSumo> instance() async {
    _sodium ??= await SodiumSumoInit.init();
    return _sodium!;
  }

  /// Test-only hook for injecting a fake [SodiumSumo] instance.
  static set debugOverride(SodiumSumo? value) => _sodium = value;
}
