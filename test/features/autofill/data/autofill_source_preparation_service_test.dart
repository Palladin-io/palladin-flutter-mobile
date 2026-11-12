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
  setUpAll(() => registerFallbackValue(metadata));
  const channel = MethodChannel('test/source-preparation');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late _Metadata reader;
  late AutoFillSourceAccessService access;
  late AutoFillSourcePreparationService service;
  late List<String> calls;
  late int authorityRevision;
  setUp(() async {
    calls = [];
    authorityRevision = 0;
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
        sessionRevision: () => authorityRevision,
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
    when(() => reader.validateAutoFillPublication(any())).thenReturn(null);
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

  test('warm preparation reuses only an activated current index', () async {
    expect(service.preparedVaultIds(), isNull);
    await service.synchronizePrepared(
      privateKey: Uint8List(32),
      vaultIds: const [],
    );
    expect(service.preparedVaultIds(), isEmpty);
    expect(service.preparedVaultIds(), isEmpty);
    verify(
      () => reader.readAutoFillMetadata(
        vaultIds: any(named: 'vaultIds'),
        authority: claims,
      ),
    ).called(1);
    expect(calls, ['beginSourceSession', 'activateSource']);
  });

  test('source invalidation immediately forbids warm reuse', () async {
    await service.synchronizePrepared(
      privateKey: Uint8List(32),
      vaultIds: const [],
    );
    final pending = access.invalidate();
    expect(service.preparedVaultIds(), isNull);
    await pending;
    expect(service.preparedVaultIds(), isNull);
  });

  test('changed metadata or expired lease forbids warm reuse', () async {
    await service.synchronizePrepared(
      privateKey: Uint8List(32),
      vaultIds: const [],
    );
    when(
      () => reader.validateAutoFillPublication(any()),
    ).thenThrow(const LocalMemberEntryReadInvalidatedException());
    expect(service.preparedVaultIds(), isNull);
  });

  test('account or authority replacement prevents reuse', () async {
    await service.synchronizePrepared(
      privateKey: Uint8List(32),
      vaultIds: const [],
    );
    authorityRevision++;
    expect(service.preparedVaultIds(), isNull);
  });

  test('new source session cannot inherit ready indexes', () async {
    await service.synchronizePrepared(
      privateKey: Uint8List(32),
      vaultIds: const [],
    );
    await access.begin(
      authority: claims,
      profileBinding: 'b' * 64,
      accountUnlock: const {},
    );
    expect(service.preparedVaultIds(), isNull);
  });

  test('native rejection removes previous ready state', () async {
    await service.synchronizePrepared(
      privateKey: Uint8List(32),
      vaultIds: const [],
    );
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'activateSource') return 99;
      return 2;
    });
    await expectLater(
      service.synchronizePrepared(
        privateKey: Uint8List(32),
        vaultIds: const [],
      ),
      throwsStateError,
    );
    expect(service.preparedVaultIds(), isNull);
  });

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
