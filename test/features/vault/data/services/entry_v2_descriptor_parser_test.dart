import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/crypto/envelope/envelope_contract.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_v2_crypto_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_plaintext.dart';
import 'package:sodium/sodium_sumo.dart' as sodium_ffi;
import 'package:sodium_libs/sodium_libs_sumo.dart';

Future<SodiumSumo?> _loadSodium() async {
  try {
    final configured = Platform.environment['PALLADIN_LIBSODIUM_PATH'];
    if (configured != null) {
      return await sodium_ffi.SodiumSumoInit.init(
        () => DynamicLibrary.open(configured),
      );
    }
    if (Platform.isLinux) {
      return await sodium_ffi.SodiumSumoInit.init(
        () => DynamicLibrary.open('libsodium.so'),
      );
    }
    return await SodiumSumoInit.init();
  } catch (_) {
    return null;
  }
}

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

  test('parses a backend-shaped MemberIndex beyond the 500th record', () {
    const pageSize = 200;
    const recordCount = 539;
    EnvelopeDescriptor? last;

    for (var pageStart = 0; pageStart < recordCount; pageStart += pageSize) {
      final pageEnd = (pageStart + pageSize).clamp(0, recordCount);
      for (var index = pageStart; index < pageEnd; index++) {
        final json = descriptor('memberIndex')
          ..['resourceRevision'] = '${index + 1}'
          ..['binding'] = <String, dynamic>{};
        last = entryEnvelopeDescriptorFromJson(
          json,
          EnvelopePurpose.memberIndex,
        );
      }
    }

    expect(last, isNotNull);
    expect(last!.purpose, EnvelopePurpose.memberIndex);
    expect(last.resourceRevision, 539);
    expect(last.purposeData, isA<NoPurposeData>());
  });

  test('539th MemberIndex is sealed for the unwrapped EntryDEK', () async {
    final sodium = await _loadSodium();
    if (sodium == null) {
      markTestSkipped('libsodium is unavailable in this Flutter test host');
      return;
    }
    final service = EntryV2CryptoService(sodiumLoader: () async => sodium);
    final vaultKey = Uint8List(32)..fillRange(0, 32, 7);
    final discoveryKey = Uint8List(32)..fillRange(0, 32, 8);
    final bundle = await service.seal(
      organizationId: '11111111-1111-4111-8111-111111111111',
      vaultId: '22222222-2222-4222-8222-222222222222',
      entryId: entryId,
      revision: 539,
      vaultKeyVersion: 1,
      vdkVersion: 1,
      memberKeyGeneration: 1,
      operation: 1,
      secret: MemberSecret(
        entryType: VaultEntryType.key,
        memberLabel: 'Record 539',
        agentLabel: null,
        description: null,
        icon: null,
        color: null,
        discoverable: false,
        content: const KeySecretContent(
          value: 'sensitive-test-value',
          notes: null,
          customFields: [],
        ),
        agentFieldAccess: const {
          'memberLabel': AgentFieldAccess.never,
          'agentLabel': AgentFieldAccess.never,
          'description': AgentFieldAccess.never,
          'icon': AgentFieldAccess.never,
          'color': AgentFieldAccess.never,
          'entryType': AgentFieldAccess.never,
          'key.value': AgentFieldAccess.onGrantValue,
          'notes': AgentFieldAccess.onGrantValue,
        },
      ),
      vaultKey: vaultKey,
      vaultDiscoveryKey: discoveryKey,
    );
    final entryDek = await service.openEntryDek(
      entryKey: Map<String, dynamic>.from(bundle.entryKey),
      vaultKey: vaultKey,
    );
    try {
      final index = await service.openMemberIndex(
        envelope: Map<String, dynamic>.from(bundle.memberIndex),
        vaultKey: entryDek,
      );
      expect(index['memberLabel'], 'Record 539');
    } finally {
      entryDek.fillRange(0, entryDek.length, 0);
      vaultKey.fillRange(0, vaultKey.length, 0);
      discoveryKey.fillRange(0, discoveryKey.length, 0);
    }
  });

  test('parses imported MemberIndex with empty nullable text projections', () {
    final index = MemberIndex.fromJson({
      'schema': MemberIndex.schema,
      'entryType': 'credential',
      'memberLabel': 'Imported login',
      'description': '',
      'icon': null,
      'color': null,
      'username': '',
      'urlDomain': '',
      'customIndex': const [],
    });

    expect(index.description, '');
    expect(index.username, '');
    expect(index.urlDomain, '');
  });
}
