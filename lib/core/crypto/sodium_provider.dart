import 'package:sodium/sodium_sumo.dart';

/// Lazy-loads the libsodium native library and exposes a shared
/// [SodiumSumo] instance for all crypto operations.
///
/// Uses the "sumo" variant of libsodium which includes `crypto_pwhash`
/// (Argon2id) and `crypto_scalarmult` — both required for the
/// zero-knowledge onboarding flow.
///
/// libsodium 1.0.22 is compiled from the source archive pinned by the
/// `sodium` package's native-asset build hook and bundled with the app.
class SodiumProvider {
  SodiumProvider._();

  static SodiumSumo? _sodium;

  /// Returns the shared [SodiumSumo] instance, initializing it on first call.
  ///
  static Future<SodiumSumo> instance() async {
    _sodium ??= await SodiumSumoInit.init();
    return _sodium!;
  }

  /// Test-only hook for injecting a fake [SodiumSumo] instance.
  static set debugOverride(SodiumSumo? value) => _sodium = value;
}
