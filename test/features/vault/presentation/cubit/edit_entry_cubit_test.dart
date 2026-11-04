import 'dart:async';
import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_palladin/features/vault/data/services/canonical_entry_detail_service.dart';
import 'package:mobile_palladin/features/vault/data/services/local_current_entry_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/agent_visibility_policy.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';
import 'package:mobile_palladin/features/vault/domain/entities/sign_in_method.dart';
import 'package:mobile_palladin/features/vault/domain/exceptions/entry_exceptions.dart';
import 'package:mobile_palladin/features/vault/domain/repositories/entry_repository.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/edit_entry_cubit.dart';

class _MockEntryRepository extends Mock implements EntryRepository {}

class _MockCanonicalService extends Mock
    implements CanonicalEntryDetailService {}

class _MockLocalCurrentEntryService extends Mock
    implements LocalCurrentEntryService {}

void main() {
  late _MockEntryRepository repository;
  late _MockCanonicalService canonical;

  final sampleEntry = EntryEntity(
    id: 'e-1',
    vaultId: 'v-1',
    label: 'Stripe API Key',
    type: EntryType.key,
    createdAt: DateTime.utc(2026, 4, 1),
    updatedAt: DateTime.utc(2026, 4, 20),
  );
  final samplePayload = <String, dynamic>{
    'type': 'KEY',
    'value': 'sk_live_xxx',
  };
  final privateKey = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));

  CanonicalEntrySnapshot snapshot() => CanonicalEntrySnapshot(
    entry: <String, dynamic>{'currentRevision': '7'},
    payload: Map<String, dynamic>.from(samplePayload),
    secret: <String, dynamic>{'schemaVersion': 1},
  );

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(sampleEntry);
    registerFallbackValue(snapshot());
    registerFallbackValue(EntryType.key);
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(
      AgentVisibilityPolicy(discoverable: false, fields: const {}),
    );
  });

  setUp(() {
    repository = _MockEntryRepository();
    canonical = _MockCanonicalService();
  });

  EditEntryCubit buildCubit() =>
      EditEntryCubit(repository: repository, canonicalService: canonical);

  group('EditEntryCubit canonical lifecycle', () {
    test(
      'starts empty until the presentation requests canonical data',
      () async {
        final cubit = buildCubit();
        expect(cubit.state, isA<EditEntryInitial>());
        verifyNever(
          () => canonical.reveal(
            expected: any(named: 'expected'),
            memberPrivateKey: any(named: 'memberPrivateKey'),
          ),
        );
        await cubit.close();
      },
    );

    blocTest<EditEntryCubit, EditEntryState>(
      'explicit reveal authenticates canonical secret and emits Ready',
      build: () {
        when(
          () => canonical.reveal(
            expected: any(named: 'expected'),
            memberPrivateKey: any(named: 'memberPrivateKey'),
          ),
        ).thenAnswer((_) async => snapshot());
        return buildCubit();
      },
      act: (cubit) =>
          cubit.revealForEdit(entry: sampleEntry, privateKey: privateKey),
      expect: () => [isA<EditEntryRevealing>(), isA<EditEntryReady>()],
      verify: (_) => verifyNever(
        () => repository.revealEntry(
          vaultId: any(named: 'vaultId'),
          entryId: any(named: 'entryId'),
          privateKey: any(named: 'privateKey'),
          wrappedVK: any(named: 'wrappedVK'),
        ),
      ),
    );

    blocTest<EditEntryCubit, EditEntryState>(
      'corrupt canonical secret fails closed without legacy fallback',
      build: () {
        when(
          () => canonical.reveal(
            expected: any(named: 'expected'),
            memberPrivateKey: any(named: 'memberPrivateKey'),
          ),
        ).thenThrow(
          const CanonicalEntryDetailException(
            CanonicalEntryDetailError.corrupt,
          ),
        );
        return buildCubit();
      },
      act: (cubit) =>
          cubit.revealForEdit(entry: sampleEntry, privateKey: privateKey),
      expect: () => [
        isA<EditEntryRevealing>(),
        isA<EditEntryError>().having(
          (state) => state.kind,
          'kind',
          EntryErrorKind.cryptoFailure,
        ),
      ],
      verify: (_) => verifyNever(
        () => repository.revealEntry(
          vaultId: any(named: 'vaultId'),
          entryId: any(named: 'entryId'),
          privateKey: any(named: 'privateKey'),
          wrappedVK: any(named: 'wrappedVK'),
        ),
      ),
    );

    test('forced refresh bypasses a stale local head', () async {
      final local = _MockLocalCurrentEntryService();
      final current = CanonicalEntrySnapshot(
        entry: {
          'currentRevision': '9',
          'currentKeyVersion': 3,
          'updatedAt': '2026-09-01T16:00:00Z',
        },
        payload: Map<String, dynamic>.from(samplePayload),
        secret: {
          'schemaVersion': 1,
          'entryType': EntryType.key.toWire(),
          'memberLabel': 'Authoritative label',
        },
      );
      when(
        () => canonical.reveal(
          expected: any(named: 'expected'),
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer((_) async => current);
      final cubit = EditEntryCubit(
        repository: repository,
        canonicalService: canonical,
        localCurrentEntry: local,
      );

      await cubit.revealForEdit(
        entry: sampleEntry,
        privateKey: privateKey,
        forceRemote: true,
      );

      final ready = cubit.state as EditEntryReady;
      expect(ready.entry.label, 'Authoritative label');
      expect(ready.entry.currentRevision, '9');
      expect(ready.entry.currentKeyVersion, 3);
      verifyNever(
        () => local.reveal(
          expected: any(named: 'expected'),
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      );
      await cubit.close();
    });

    blocTest<EditEntryCubit, EditEntryState>(
      'save creates a canonical revision and never calls legacy update',
      build: () {
        when(
          () => canonical.reveal(
            expected: any(named: 'expected'),
            memberPrivateKey: any(named: 'memberPrivateKey'),
          ),
        ).thenAnswer((_) async => snapshot());
        when(
          () => canonical.update(
            snapshot: any(named: 'snapshot'),
            expected: any(named: 'expected'),
            label: any(named: 'label'),
            description: any(named: 'description'),
            icon: any(named: 'icon'),
            type: any(named: 'type'),
            content: any(named: 'content'),
            memberPrivateKey: any(named: 'memberPrivateKey'),
          ),
        ).thenAnswer(
          (_) async => EntryEntity(
            id: sampleEntry.id,
            vaultId: sampleEntry.vaultId,
            label: 'Renamed',
            type: sampleEntry.type,
            createdAt: sampleEntry.createdAt,
            updatedAt: sampleEntry.updatedAt,
          ),
        );
        return buildCubit();
      },
      act: (cubit) async {
        await cubit.revealForEdit(entry: sampleEntry, privateKey: privateKey);
        await cubit.updateEntry(
          vaultId: sampleEntry.vaultId,
          entryId: sampleEntry.id,
          label: 'Renamed',
          type: EntryType.key,
          payload: samplePayload,
          privateKey: privateKey,
          createdAt: sampleEntry.createdAt,
        );
      },
      skip: 2,
      expect: () => [isA<EditEntryLoading>(), isA<EditEntrySuccess>()],
      verify: (cubit) {
        expect(cubit.hasCanonicalSnapshot, isFalse);
        verifyNever(
          () => repository.updateEntryEncrypted(
            vaultId: any(named: 'vaultId'),
            entryId: any(named: 'entryId'),
            label: any(named: 'label'),
            description: any(named: 'description'),
            icon: any(named: 'icon'),
            type: any(named: 'type'),
            payload: any(named: 'payload'),
            urlDomain: any(named: 'urlDomain'),
            privateKey: any(named: 'privateKey'),
            wrappedVK: any(named: 'wrappedVK'),
            createdAt: any(named: 'createdAt'),
            agentFields: any(named: 'agentFields'),
          ),
        );
      },
    );

    blocTest<EditEntryCubit, EditEntryState>(
      'optimistic conflict is explicit',
      build: () {
        when(
          () => canonical.reveal(
            expected: any(named: 'expected'),
            memberPrivateKey: any(named: 'memberPrivateKey'),
          ),
        ).thenAnswer((_) async => snapshot());
        when(
          () => canonical.update(
            snapshot: any(named: 'snapshot'),
            expected: any(named: 'expected'),
            label: any(named: 'label'),
            description: any(named: 'description'),
            icon: any(named: 'icon'),
            type: any(named: 'type'),
            content: any(named: 'content'),
            memberPrivateKey: any(named: 'memberPrivateKey'),
          ),
        ).thenThrow(
          const CanonicalEntryDetailException(
            CanonicalEntryDetailError.conflict,
          ),
        );
        return buildCubit();
      },
      act: (cubit) async {
        await cubit.revealForEdit(entry: sampleEntry, privateKey: privateKey);
        await cubit.updateEntry(
          vaultId: sampleEntry.vaultId,
          entryId: sampleEntry.id,
          label: 'Renamed',
          type: EntryType.key,
          payload: samplePayload,
          privateKey: privateKey,
          createdAt: sampleEntry.createdAt,
        );
      },
      skip: 2,
      expect: () => [isA<EditEntryLoading>(), isA<EditEntryConflict>()],
    );

    test('coalesces repeated save taps into one canonical update', () async {
      final completion = Completer<EntryEntity>();
      when(
        () => canonical.reveal(
          expected: any(named: 'expected'),
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer((_) async => snapshot());
      when(
        () => canonical.update(
          snapshot: any(named: 'snapshot'),
          expected: any(named: 'expected'),
          label: any(named: 'label'),
          description: any(named: 'description'),
          icon: any(named: 'icon'),
          type: any(named: 'type'),
          content: any(named: 'content'),
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer((_) => completion.future);
      final cubit = buildCubit();
      await cubit.revealForEdit(entry: sampleEntry, privateKey: privateKey);

      final first = cubit.updateEntry(
        vaultId: sampleEntry.vaultId,
        entryId: sampleEntry.id,
        label: 'Renamed',
        type: EntryType.key,
        payload: samplePayload,
        privateKey: privateKey,
        createdAt: sampleEntry.createdAt,
      );
      final repeated = cubit.updateEntry(
        vaultId: sampleEntry.vaultId,
        entryId: sampleEntry.id,
        label: 'Renamed',
        type: EntryType.key,
        payload: samplePayload,
        privateKey: privateKey,
        createdAt: sampleEntry.createdAt,
      );
      await repeated;
      completion.complete(
        EntryEntity(
          id: sampleEntry.id,
          vaultId: sampleEntry.vaultId,
          label: 'Renamed',
          type: sampleEntry.type,
          createdAt: sampleEntry.createdAt,
          updatedAt: sampleEntry.updatedAt,
          currentRevision: '8',
        ),
      );
      await first;

      verify(
        () => canonical.update(
          snapshot: any(named: 'snapshot'),
          expected: any(named: 'expected'),
          label: any(named: 'label'),
          description: any(named: 'description'),
          icon: any(named: 'icon'),
          type: any(named: 'type'),
          content: any(named: 'content'),
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).called(1);
      expect(cubit.state, isA<EditEntrySuccess>());
      await cubit.close();
    });

    test(
      'lock/background cleanup clears payload and returns initial',
      () async {
        when(
          () => canonical.reveal(
            expected: any(named: 'expected'),
            memberPrivateKey: any(named: 'memberPrivateKey'),
          ),
        ).thenAnswer((_) async => snapshot());
        final cubit = buildCubit();
        await cubit.revealForEdit(entry: sampleEntry, privateKey: privateKey);
        final ready = cubit.state as EditEntryReady;
        cubit.clearSensitiveState();
        expect(ready.payload, isEmpty);
        expect(cubit.state, isA<EditEntryInitial>());
        await cubit.close();
      },
    );

    test(
      'late reveal completion is discarded after lifecycle cleanup',
      () async {
        final completion = Completer<CanonicalEntrySnapshot>();
        when(
          () => canonical.reveal(
            expected: any(named: 'expected'),
            memberPrivateKey: any(named: 'memberPrivateKey'),
          ),
        ).thenAnswer((_) => completion.future);
        final cubit = buildCubit();

        final reveal = cubit.revealForEdit(
          entry: sampleEntry,
          privateKey: privateKey,
        );
        cubit.clearSensitiveState();
        final revealed = snapshot();
        completion.complete(revealed);
        await reveal;

        expect(cubit.state, isA<EditEntryInitial>());
        expect(cubit.hasCanonicalSnapshot, isFalse);
        expect(revealed.payload, isEmpty);
        expect(revealed.entry, isEmpty);
        expect(revealed.secret, isEmpty);
        await cubit.close();
      },
    );

    test('close wipes the snapshot still referenced by Ready state', () async {
      final revealed = snapshot();
      when(
        () => canonical.reveal(
          expected: any(named: 'expected'),
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer((_) async => revealed);
      final cubit = buildCubit();
      await cubit.revealForEdit(entry: sampleEntry, privateKey: privateKey);
      final ready = cubit.state as EditEntryReady;

      await cubit.close();

      expect(ready.payload, isEmpty);
      expect(revealed.entry, isEmpty);
      expect(revealed.secret, isEmpty);
    });

    blocTest<EditEntryCubit, EditEntryState>(
      'delete remains repository-backed and typed',
      build: () {
        when(
          () => repository.deleteEntry(
            vaultId: any(named: 'vaultId'),
            entryId: any(named: 'entryId'),
          ),
        ).thenAnswer((_) async {});
        return buildCubit();
      },
      act: (cubit) => cubit.deleteEntry(vaultId: 'v-1', entryId: 'e-1'),
      expect: () => [isA<EditEntryLoading>(), isA<EditEntryDeleted>()],
    );
  });

  group('EditEntryCubit sign-in method', () {
    const otherId = '44444444-4444-4444-8444-444444444444';
    const oldId = '55555555-5555-4555-8555-555555555555';
    const futureId = '66666666-6666-4666-8666-666666666666';
    const linkedVault = '77777777-7777-4777-8777-777777777777';
    const linkedEntry = '88888888-8888-4888-8888-888888888888';
    final credential = EntryEntity(
      id: 'e-2',
      vaultId: 'v-1',
      label: 'Example',
      type: EntryType.credential,
      createdAt: DateTime.utc(2026, 4, 1),
      updatedAt: DateTime.utc(2026, 4, 20),
    );

    CanonicalEntrySnapshot credentialSnapshot({
      int entryType = 1,
      List<Map<String, dynamic>>? fields,
      bool discoverable = true,
      Map<String, String>? access,
    }) => CanonicalEntrySnapshot(
      entry: <String, dynamic>{'currentRevision': '9'},
      payload: <String, dynamic>{
        'username': 'qa@example.test',
        'password': '',
        'url': 'https://example.test',
        'urlDomain': 'example.test',
        'totp': null,
        'notes': 'keep',
        'fields':
            fields ??
            [
              {
                'id': otherId,
                'label': 'Team',
                'type': 'text',
                'value': 'qa',
                'agentVisible': false,
              },
              {
                'id': oldId,
                'label': 'Old',
                'type': 'palladin.signin.v1',
                'value': {'provider': 'google', 'account': null},
                'agentVisible': false,
              },
              {
                'id': futureId,
                'label': 'Future',
                'type': 'palladin.future.v9',
                'value': {'x': 1},
                'agentVisible': false,
              },
            ],
      },
      secret: <String, dynamic>{
        'entryType': entryType,
        'memberLabel': 'Example',
        'agentLabel': 'Example agent',
        'description': 'Desc',
        'iconReference': 'key',
        'agentVisibilityPolicy': {
          'discoverable': discoverable,
          'fields':
              access ??
              {
                'agentLabel': 'discovery',
                'username': 'discovery',
                'password': 'onGrantValue',
                otherId: 'onGrantValue',
                oldId: 'never',
                futureId: 'never',
              },
        },
      },
    );

    void stubReveal(CanonicalEntrySnapshot value) => when(
      () => canonical.reveal(
        expected: any(named: 'expected'),
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    ).thenAnswer((_) async => value);

    void stubUpdate() => when(
      () => canonical.update(
        snapshot: any(named: 'snapshot'),
        expected: any(named: 'expected'),
        label: any(named: 'label'),
        description: any(named: 'description'),
        icon: any(named: 'icon'),
        type: any(named: 'type'),
        content: any(named: 'content'),
        memberPrivateKey: any(named: 'memberPrivateKey'),
        agentVisibilityPolicy: any(named: 'agentVisibilityPolicy'),
        agentLabel: any(named: 'agentLabel'),
      ),
    ).thenAnswer((_) async => credential);

    List<dynamic> captureUpdate() => verify(
      () => canonical.update(
        snapshot: captureAny(named: 'snapshot'),
        expected: any(named: 'expected'),
        label: captureAny(named: 'label'),
        description: captureAny(named: 'description'),
        icon: captureAny(named: 'icon'),
        type: captureAny(named: 'type'),
        content: captureAny(named: 'content'),
        memberPrivateKey: any(named: 'memberPrivateKey'),
        agentVisibilityPolicy: captureAny(named: 'agentVisibilityPolicy'),
        agentLabel: captureAny(named: 'agentLabel'),
      ),
    ).captured;

    test(
      'replaces every binding on a fresh head and preserves the rest',
      () async {
        final fresh = credentialSnapshot();
        stubReveal(fresh);
        stubUpdate();
        final cubit = buildCubit();
        await cubit.saveSignInMethod(
          entry: credential,
          privateKey: privateKey,
          binding: const SignInMethodBinding(
            provider: SignInProvider.github,
            account: 'octo',
            entry: SignInEntryReference(
              vaultId: linkedVault,
              entryId: linkedEntry,
            ),
          ),
          fieldLabel: 'Sign-in method',
        );
        expect(cubit.state, isA<EditEntrySuccess>());
        final captured = captureUpdate();
        expect(identical(captured[0], fresh), isTrue);
        expect(captured.sublist(1, 5), [
          'Example',
          'Desc',
          'key',
          EntryType.credential,
        ]);
        final content = captured[5] as Map<String, dynamic>;
        expect(content['password'], '');
        expect(content['notes'], 'keep');
        final fields = (content['fields'] as List).cast<Map<String, dynamic>>();
        expect(fields.map((field) => field['id']).take(2), [otherId, futureId]);
        expect(fields[1]['value'], {'x': 1});
        expect(fields, hasLength(3));
        final created = fields.last;
        expect(created['type'], 'palladin.signin.v1');
        expect(created['label'], 'Sign-in method');
        expect(created['value'], {
          'provider': 'github',
          'account': 'octo',
          'entry': {'vaultId': linkedVault, 'entryId': linkedEntry},
        });
        expect(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ).hasMatch(created['id'] as String),
          isTrue,
        );
        final policy = captured[6] as AgentVisibilityPolicy;
        expect(policy.discoverable, isTrue);
        // The retired two-key field is unrecognized, so the Credential's
        // discoverability decides the default.
        expect(policy.fields[created['id']], AgentFieldAccess.discovery);
        expect(policy.fields.containsKey(oldId), isFalse);
        expect(policy.fields[otherId], AgentFieldAccess.onGrantValue);
        expect(policy.fields[futureId], AgentFieldAccess.never);
        expect(policy.fields['username'], AgentFieldAccess.discovery);
        expect(captured[7], 'Example agent');
        await cubit.close();
      },
    );

    test('a null binding removes every sign-in field', () async {
      stubReveal(credentialSnapshot());
      stubUpdate();
      final cubit = buildCubit();
      await cubit.saveSignInMethod(
        entry: credential,
        privateKey: privateKey,
        binding: null,
        fieldLabel: 'Sign-in method',
      );
      final captured = captureUpdate();
      final fields = ((captured[5] as Map)['fields'] as List)
          .cast<Map<String, dynamic>>();
      expect(fields.map((field) => field['id']), [otherId, futureId]);
      final policy = captured[6] as AgentVisibilityPolicy;
      expect(policy.fields.containsKey(oldId), isFalse);
      await cubit.close();
    });

    test('rejects a non-Credential head without writing', () async {
      stubReveal(credentialSnapshot(entryType: 0, fields: const []));
      final cubit = buildCubit();
      await cubit.saveSignInMethod(
        entry: credential,
        privateKey: privateKey,
        binding: const SignInMethodBinding(provider: SignInProvider.google),
        fieldLabel: 'Sign-in method',
      );
      expect(
        cubit.state,
        isA<EditEntryError>().having(
          (state) => state.kind,
          'kind',
          EntryErrorKind.validation,
        ),
      );
      verifyNever(
        () => canonical.update(
          snapshot: any(named: 'snapshot'),
          expected: any(named: 'expected'),
          label: any(named: 'label'),
          description: any(named: 'description'),
          icon: any(named: 'icon'),
          type: any(named: 'type'),
          content: any(named: 'content'),
          memberPrivateKey: any(named: 'memberPrivateKey'),
          agentVisibilityPolicy: any(named: 'agentVisibilityPolicy'),
          agentLabel: any(named: 'agentLabel'),
        ),
      );
      await cubit.close();
    });

    Map<String, dynamic> recognized() => {
      'id': oldId,
      'label': 'Old',
      'type': 'palladin.signin.v1',
      'value': {'provider': 'google', 'account': 'a@b.test', 'entry': null},
      'agentVisible': false,
    };

    Future<AgentVisibilityPolicy> savedPolicy(
      CanonicalEntrySnapshot snapshot,
    ) async {
      stubReveal(snapshot);
      stubUpdate();
      final cubit = buildCubit();
      await cubit.saveSignInMethod(
        entry: credential,
        privateKey: privateKey,
        binding: const SignInMethodBinding(provider: SignInProvider.apple),
        fieldLabel: 'Sign-in method',
      );
      await cubit.close();
      final captured = captureUpdate();
      final fields = ((captured[5] as Map)['fields'] as List)
          .cast<Map<String, dynamic>>();
      final policy = captured[6] as AgentVisibilityPolicy;
      final created = fields.singleWhere(
        (field) => field['type'] == 'palladin.signin.v1',
      );
      return AgentVisibilityPolicy(
        discoverable: policy.discoverable,
        fields: {'created': policy.fields[created['id']]!},
      );
    }

    test('replacing a recognized binding keeps its never access', () async {
      final policy = await savedPolicy(
        credentialSnapshot(
          fields: [recognized()],
          access: {
            'agentLabel': 'discovery',
            'username': 'discovery',
            oldId: 'never',
          },
        ),
      );
      expect(policy.fields['created'], AgentFieldAccess.never);
    });

    test('replacing a recognized binding keeps its discovery access', () async {
      final policy = await savedPolicy(
        credentialSnapshot(
          fields: [recognized()],
          access: {'agentLabel': 'discovery', oldId: 'discovery'},
        ),
      );
      expect(policy.fields['created'], AgentFieldAccess.discovery);
    });

    test('a non-discoverable Credential writes never access', () async {
      final policy = await savedPolicy(
        credentialSnapshot(
          fields: const [],
          discoverable: false,
          access: {'agentLabel': 'never', 'username': 'onGrantValue'},
        ),
      );
      expect(policy.fields['created'], AgentFieldAccess.never);
    });

    test('an optimistic conflict surfaces as a conflict state', () async {
      stubReveal(credentialSnapshot());
      when(
        () => canonical.update(
          snapshot: any(named: 'snapshot'),
          expected: any(named: 'expected'),
          label: any(named: 'label'),
          description: any(named: 'description'),
          icon: any(named: 'icon'),
          type: any(named: 'type'),
          content: any(named: 'content'),
          memberPrivateKey: any(named: 'memberPrivateKey'),
          agentVisibilityPolicy: any(named: 'agentVisibilityPolicy'),
          agentLabel: any(named: 'agentLabel'),
        ),
      ).thenThrow(
        const CanonicalEntryDetailException(CanonicalEntryDetailError.conflict),
      );
      final cubit = buildCubit();
      await cubit.saveSignInMethod(
        entry: credential,
        privateKey: privateKey,
        binding: const SignInMethodBinding(provider: SignInProvider.apple),
        fieldLabel: 'Sign-in method',
      );
      expect(cubit.state, isA<EditEntryConflict>());
      await cubit.close();
    });
  });
}
