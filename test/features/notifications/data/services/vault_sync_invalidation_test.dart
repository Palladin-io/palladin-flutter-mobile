import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/notifications/data/services/notification_signalr_service.dart';

void main() {
  test('parses value-free monotonic Vault invalidation', () {
    final value = VaultSyncInvalidation.fromJson({
      'protocolVersion': 1,
      'vaultId': '22222222-2222-4222-8222-222222222222',
      'memberSequence': '12',
      'mutationVersion': '8',
      'removed': false,
    });

    expect(value.memberSequence, '12');
    expect(value.mutationVersion, '8');
    expect(value.removed, isFalse);
  });

  test('rejects payload or non-canonical sequence fields', () {
    expect(
      () => VaultSyncInvalidation.fromJson({
        'protocolVersion': 1,
        'vaultId': '22222222-2222-4222-8222-222222222222',
        'memberSequence': '012',
        'mutationVersion': '8',
        'removed': false,
        'memberSecret': 'forbidden',
      }),
      throwsFormatException,
    );
    expect(
      () => VaultSyncInvalidation.fromJson({
        'protocolVersion': 1,
        'vaultId': '22222222-2222-4222-8222-222222222222',
        'memberSequence': '18446744073709551616',
        'mutationVersion': '8',
        'removed': false,
      }),
      throwsFormatException,
    );
  });
}
