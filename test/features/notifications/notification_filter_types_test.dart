import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/notifications/presentation/widgets/notification_format.dart';

void main() {
  test('filter offers every MVP notification type, no duplicates', () {
    expect(notificationFilterTypes.toSet(), {
      'grant_pending',
      'agent_pending',
      'credential_stale',
      'grant_approved',
      'grant_denied',
      'grant_revoked',
      'agent_approved',
      'entry_share_received',
    });
    // No duplicate entries (order matters for display but each type once).
    expect(
      notificationFilterTypes.length,
      notificationFilterTypes.toSet().length,
    );
  });

  test('action-required types lead the filter order', () {
    expect(notificationFilterTypes.first, 'grant_pending');
    expect(notificationFilterTypes.take(3), [
      'grant_pending',
      'agent_pending',
      'credential_stale',
    ]);
  });
}
