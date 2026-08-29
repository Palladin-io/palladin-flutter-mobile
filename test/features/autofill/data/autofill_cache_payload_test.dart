import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/autofill/domain/autofill_record.dart';

void main() {
  final notAfter = DateTime.utc(2026, 8, 30);
  const entryAuthority = AutoFillEntryAuthority(revision: '41', keyVersion: 7);
  final manifest = AutoFillCacheManifest(
    principalId: '11111111-1111-4111-8111-111111111111',
    organizationId: '22222222-2222-4222-8222-222222222222',
    organizationMembershipGeneration: '9',
    offlinePolicy: '24h',
    offlinePolicyVersion: 3,
    vaults: {
      '33333333-3333-4333-8333-333333333333': AutoFillVaultAuthority(
        contextVersion: 1,
        memberId: '11111111-1111-4111-8111-111111111111',
        memberKeyGeneration: 4,
        vaultKeyVersion: 6,
        memberRecipientKeyVersion: 5,
        memberRecipientKeyFingerprint: 'fixture-fingerprint',
        issuedAt: DateTime.utc(2026, 8, 29),
        notAfter: notAfter,
        entries: const {'44444444-4444-4444-8444-444444444444': entryAuthority},
      ),
    },
  );

  AutoFillRecord record({String? vaultId, String? revision}) => AutoFillRecord(
    id: '44444444-4444-4444-8444-444444444444',
    organizationId: '22222222-2222-4222-8222-222222222222',
    vaultId: vaultId ?? '33333333-3333-4333-8333-333333333333',
    revision: revision ?? '41',
    keyVersion: 7,
    label: 'Canonical login',
    username: 'alice@example.com',
    password: 'test-only-password',
    domains: const ['login.example.com'],
  );

  test('serializes a v2 payload with independent manifest authority', () {
    final payload = AutoFillCachePayload(
      manifest: manifest,
      records: [record()],
    );

    expect(payload.toPlatformMap(), {
      'version': 2,
      'manifest': manifest.toPlatformMap(),
      'records': [record().toPlatformMap()],
    });
  });

  test('rejects a substituted record against unchanged authority', () {
    final payload = AutoFillCachePayload(
      manifest: manifest,
      records: [record(vaultId: '55555555-5555-4555-8555-555555555555')],
    );

    expect(payload.toPlatformMap, throwsFormatException);
  });

  test('rejects a stale revision against unchanged Entry high-water', () {
    final payload = AutoFillCachePayload(
      manifest: manifest,
      records: [record(revision: '40')],
    );

    expect(payload.toPlatformMap, throwsFormatException);
  });
}
