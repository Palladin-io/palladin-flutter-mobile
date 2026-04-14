import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_claw_vault/features/onboarding/domain/password_strength.dart';

void main() {
  group('evaluatePasswordStrength', () {
    test('returns tooShort for empty or short passwords', () {
      expect(evaluatePasswordStrength(''), PasswordStrength.tooShort);
      expect(evaluatePasswordStrength('abc'), PasswordStrength.tooShort);
      expect(evaluatePasswordStrength('abcdefg'), PasswordStrength.tooShort);
    });

    test('returns weak for short, single-class passwords', () {
      expect(evaluatePasswordStrength('abcdefgh'), PasswordStrength.weak);
    });

    test('returns fair for 12+ char single-class passwords', () {
      expect(evaluatePasswordStrength('abcdefghijkl'), PasswordStrength.fair);
    });

    test('returns strong with length + class variety', () {
      expect(evaluatePasswordStrength('Abcdefgh1234'), PasswordStrength.strong);
    });

    test('returns veryStrong for long diverse passwords', () {
      expect(
        evaluatePasswordStrength('CorrectHorseBatteryStaple!9'),
        PasswordStrength.veryStrong,
      );
    });

    test('isAcceptable requires at least fair strength', () {
      expect(PasswordStrength.tooShort.isAcceptable, isFalse);
      expect(PasswordStrength.weak.isAcceptable, isFalse);
      expect(PasswordStrength.fair.isAcceptable, isTrue);
      expect(PasswordStrength.strong.isAcceptable, isTrue);
      expect(PasswordStrength.veryStrong.isAcceptable, isTrue);
    });
  });
}
