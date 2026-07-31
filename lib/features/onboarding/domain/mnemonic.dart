import 'dart:math';

import 'package:bip39/bip39.dart' as bip39;

import 'crypto_params.dart';

/// Generates a fresh 24-word BIP-39 mnemonic (English wordlist).
///
/// Uses 256 bits of entropy so the mnemonic is 24 words long, matching
/// the web panel and the zero-knowledge spec.
List<String> generateRecoveryMnemonic() {
  final phrase = bip39.generateMnemonic(
    strength: CryptoParams.recoveryEntropyBytes * 8,
  );
  return phrase.split(' ');
}

/// Joins a mnemonic word list back into a single space-separated string
/// for use as the Argon2id password input to derive the recovery key.
String joinMnemonic(List<String> words) => words.join(' ');

/// Picks [count] distinct word indices from a mnemonic of [length] words
/// for the confirmation quiz.
///
/// Uses [Random.secure] so the quiz isn't predictable. Indices are
/// returned in ascending order so the user sees them in reading order
/// ("Word #3", then "#11", then "#19" — not jumbled).
List<int> pickVerificationIndices({
  int length = CryptoParams.recoveryMnemonicWordCount,
  int count = CryptoParams.recoveryConfirmationWordCount,
  Random? random,
}) {
  if (count >= length) {
    return List<int>.generate(length, (i) => i);
  }

  final rng = random ?? Random.secure();
  final picked = <int>{};
  while (picked.length < count) {
    picked.add(rng.nextInt(length));
  }

  final result = picked.toList()..sort();
  return result;
}
