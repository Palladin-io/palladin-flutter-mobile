import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/crypto/envelope/envelope_contract.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_v2_crypto_service.dart';

void main() {
  const entryId = '33333333-3333-4333-8333-333333333333';

  Map<String, dynamic> descriptor(Object purpose) => {
    'protocolVersion': 2,
    'cryptoSuiteId': 'palladin-vault-xchacha-v1',
    'purpose': purpose,
    'scope': {
      'organizationId': '11111111-1111-4111-8111-111111111111',
      'vaultId': '22222222-2222-4222-8222-222222222222',
      'entryId': entryId,
      'grantOrRequestId': null,
      'agentId': null,
      'memberId': null,
    },
    'resourceRevision': '1',
    'keyVersion': 1,
    'memberKeyGeneration': 1,
    'binding': {'wrappingVaultKeyVersion': 1},
  };

  test('accepts the canonical named purpose emitted by the backend', () {
    final parsed = entryEnvelopeDescriptorFromJson(
      descriptor('entryDekByVaultKey'),
      EnvelopePurpose.entryDekByVk,
    );

    expect(parsed.purpose, EnvelopePurpose.entryDekByVk);
    expect(parsed.keyVersion, 1);
  });

  test('continues to accept the numeric protocol purpose', () {
    final parsed = entryEnvelopeDescriptorFromJson(
      descriptor(8),
      EnvelopePurpose.entryDekByVk,
    );

    expect(parsed.purpose, EnvelopePurpose.entryDekByVk);
  });

  test('rejects a different canonical purpose', () {
    expect(
      () => entryEnvelopeDescriptorFromJson(
        descriptor('memberIndex'),
        EnvelopePurpose.entryDekByVk,
      ),
      throwsA(isA<EnvelopeException>()),
    );
  });

  test('parses the canonical member-secret operation emitted by the API', () {
    final json = descriptor('memberSecret')
      ..['binding'] = {'operation': 'created'};

    final parsed = entryEnvelopeDescriptorFromJson(
      json,
      EnvelopePurpose.memberSecret,
    );

    expect(parsed.purposeData, isA<MemberSecretPurposeData>());
    expect((parsed.purposeData as MemberSecretPurposeData).operation, 1);
  });

  test('rejects a non-canonical member-secret operation', () {
    final json = descriptor('memberSecret')
      ..['binding'] = {'operation': 'Created'};

    expect(
      () => entryEnvelopeDescriptorFromJson(json, EnvelopePurpose.memberSecret),
      throwsA(isA<EnvelopeException>()),
    );
  });
}
