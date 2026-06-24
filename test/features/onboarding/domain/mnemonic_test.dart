import 'dart:math';

import 'package:bip39/bip39.dart' as bip39;
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_palladin/features/onboarding/domain/mnemonic.dart';

void main() {
  group('generateRecoveryMnemonic', () {
    test('produces a 24-word BIP-39 mnemonic', () {
      final words = generateRecoveryMnemonic();
      expect(words.length, 24);
      expect(bip39.validateMnemonic(words.join(' ')), isTrue);
    });

    test('produces distinct mnemonics across calls', () {
      final a = generateRecoveryMnemonic().join(' ');
      final b = generateRecoveryMnemonic().join(' ');
      expect(a, isNot(equals(b)));
    });
  });

  group('joinMnemonic', () {
    test('joins words with a single space', () {
      expect(joinMnemonic(['alpha', 'beta', 'gamma']), 'alpha beta gamma');
    });
  });

  group('pickVerificationIndices', () {
    test('returns count distinct ascending indices', () {
      final indices = pickVerificationIndices(
        length: 24,
        count: 3,
        random: Random(42),
      );
      expect(indices.length, 3);
      expect(indices.toSet().length, 3);
      final sorted = [...indices]..sort();
      expect(indices, sorted);
      for (final i in indices) {
        expect(i, inInclusiveRange(0, 23));
      }
    });

    test('returns all indices when count >= length', () {
      final indices = pickVerificationIndices(length: 3, count: 5);
      expect(indices, [0, 1, 2]);
    });
  });
}
