import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/notifications/data/models/notification_preference_model.dart';

void main() {
  test('parses a full preference item', () {
    final pref = NotificationPreferenceModel.fromJson({
      'type': 'grant_pending',
      'category': 'ActionRequired',
      'inboxEnabled': true,
      'signalREnabled': true,
      'pushEnabled': false,
      'mandatory': true,
    }).toEntity();

    expect(pref.type, 'grant_pending');
    expect(pref.category, 'ActionRequired');
    expect(pref.inboxEnabled, isTrue);
    expect(pref.signalREnabled, isTrue);
    expect(pref.pushEnabled, isFalse);
    expect(pref.mandatory, isTrue);
  });

  test('defaults are safe when fields are missing', () {
    final pref = NotificationPreferenceModel.fromJson({
      'type': 'credential_stale',
      'category': 'Update',
    }).toEntity();

    expect(pref.inboxEnabled, isTrue);
    expect(pref.signalREnabled, isTrue);
    expect(pref.pushEnabled, isFalse);
    expect(pref.mandatory, isFalse);
  });

  test('copyWith preserves mandatory and overrides one channel', () {
    final base = NotificationPreferenceModel.fromJson({
      'type': 'grant_pending',
      'category': 'ActionRequired',
      'inboxEnabled': true,
      'signalREnabled': true,
      'pushEnabled': true,
      'mandatory': true,
    }).toEntity();

    final updated = base.copyWith(pushEnabled: false);
    expect(updated.pushEnabled, isFalse);
    expect(updated.inboxEnabled, isTrue);
    expect(updated.mandatory, isTrue);
  });
}
