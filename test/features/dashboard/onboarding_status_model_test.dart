import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/dashboard/data/models/onboarding_status_model.dart';

void main() {
  group('OnboardingStatusModel.fromJson → toEntity', () {
    test('maps all flags from the API response', () {
      final entity = OnboardingStatusModel.fromJson(<String, dynamic>{
        'isOnboarded': false,
        'vaultCreated': true,
        'apiKeyCreated': false,
        'agentEnrolled': true,
      }).toEntity();

      expect(entity.isOnboarded, isFalse);
      expect(entity.vaultCreated, isTrue);
      expect(entity.apiKeyCreated, isFalse);
      expect(entity.agentEnrolled, isTrue);
    });

    test('defaults every flag to false when keys are absent', () {
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
        'vaultCreated': true,
        'apiKeyCreated': true,
        'agentEnrolled': false,
      }).toEntity();

      expect(entity.serverCompletedCount, 2);
    });
  });
}
