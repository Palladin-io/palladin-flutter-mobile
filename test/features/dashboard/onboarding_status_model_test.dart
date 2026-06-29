import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/dashboard/data/models/onboarding_status_model.dart';

void main() {
  group('OnboardingStatusModel.fromJson → toEntity', () {
    test('maps isOnboarded + nested onboardingSteps from the account payload',
        () {
      final entity = OnboardingStatusModel.fromJson(<String, dynamic>{
        'isOnboarded': false,
        'onboardingSteps': <String, dynamic>{
          'vaultCreated': true,
          'apiKeyCreated': false,
          'agentEnrolled': true,
        },
      }).toEntity();

      expect(entity.isOnboarded, isFalse);
      expect(entity.vaultCreated, isTrue);
      expect(entity.apiKeyCreated, isFalse);
      expect(entity.agentEnrolled, isTrue);
    });

    test('tolerates a real not-onboarded /api/account payload (null crypto)',
        () {
      // A user who has not finished setup: backend returns isOnboarded=false,
      // null salt / encrypted keys, and all steps false. The projection must
      // ignore the crypto fields and never throw on the nulls.
      final entity = OnboardingStatusModel.fromJson(<String, dynamic>{
        'userId': 'u-1',
        'email': 'new@user.io',
        'displayName': 'New User',
        'avatarUrl': null,
        'isOnboarded': false,
        'salt': null,
        'encryptedPrivateKey': null,
        'recoverySalt': null,
        'encryptedPrivateKeyByRecovery': null,
        'onboardingSteps': <String, dynamic>{
          'vaultCreated': false,
          'apiKeyCreated': false,
          'agentEnrolled': false,
        },
      }).toEntity();

      expect(entity.isOnboarded, isFalse);
      expect(entity.serverCompletedCount, 0);
    });

    test('defaults every flag to false when onboardingSteps is absent', () {
      final entity = OnboardingStatusModel.fromJson(
        const <String, dynamic>{},
      ).toEntity();

      expect(entity.isOnboarded, isFalse);
      expect(entity.vaultCreated, isFalse);
      expect(entity.apiKeyCreated, isFalse);
      expect(entity.agentEnrolled, isFalse);
      expect(entity.serverCompletedCount, 0);
    });

    test('serverCompletedCount counts only the three server steps', () {
      final entity = OnboardingStatusModel.fromJson(<String, dynamic>{
        'isOnboarded': false,
        'onboardingSteps': <String, dynamic>{
          'vaultCreated': true,
          'apiKeyCreated': true,
          'agentEnrolled': false,
        },
      }).toEntity();

      expect(entity.serverCompletedCount, 2);
    });
  });
}
