import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_source_access_service.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_source_preparation_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_session_authority_provider.dart';

class _Metadata extends Mock implements MemberAutoFillMetadataReader {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const claims = MemberSyncSessionAuthority(
    principalId: 'p',
    organizationId: 'o',
    organizationMembershipGeneration: '1',
    offlinePolicy: '24h',
    offlinePolicyVersion: 1,
  );
  const metadata = MemberAutoFillMetadata(
    readGeneration: 1,
    publicationRevision: 1,
    vaults: {},
  );
  const channel = MethodChannel('test/source-preparation');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late _Metadata reader;
  late AutoFillSourceAccessService access;
  late AutoFillSourcePreparationService service;
  late List<String> calls;
  setUp(() async {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return call.method == 'invalidateSource' ? 2 : 1;
    });
    reader = _Metadata();
    access = AutoFillSourceAccessService(channel: channel);
    await access.begin(
      authority: claims,
      profileBinding: 'a' * 64,
      accountUnlock: const {},
    );
    service = AutoFillSourcePreparationService(
      source: access,
      metadata: reader,
      authority: MemberSyncSessionAuthorityProvider.independent(
        readClaims: () async => claims,
        sessionRevision: () => 0,
      ),
    );
    when(
      () => reader.readAutoFillMetadata(
        vaultIds: any(named: 'vaultIds'),
        authority: claims,
      ),
    ).thenAnswer((_) async => metadata);
    when(
      () => reader.revalidateAutoFillMetadata(metadata, authority: claims),
    ).thenAnswer((_) async {});
    when(() => reader.validateAutoFillPublication(metadata)).thenReturn(null);
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'prepared source activates metadata without credential publication',
    () async {
      await service.synchronizePrepared(
        privateKey: Uint8List(32),
        vaultIds: const [],
      );
      expect(calls, ['beginSourceSession', 'activateSource']);
      verify(
        () => reader.revalidateAutoFillMetadata(metadata, authority: claims),
      ).called(1);
    },
  );

  test(
    'failed metadata authority cannot activate and keeps native denied',
    () async {
      when(
        () => reader.revalidateAutoFillMetadata(metadata, authority: claims),
      ).thenThrow(const LocalMemberEntryReadInvalidatedException());
      await expectLater(
        service.synchronizePrepared(
          privateKey: Uint8List(32),
          vaultIds: const [],
        ),
        throwsA(isA<LocalMemberEntryReadInvalidatedException>()),
      );
      expect(calls, ['beginSourceSession', 'invalidateSource']);
    },
  );
}
