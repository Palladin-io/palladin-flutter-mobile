import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/core/crypto/vault_session_store.dart';
import 'package:mobile_palladin/features/grants/data/datasources/grants_remote_datasource.dart';
import 'package:mobile_palladin/features/grants/data/models/grant_model.dart';
import 'package:mobile_palladin/features/grants/data/repositories/grants_repository_impl.dart';
import 'package:mobile_palladin/features/grants/data/services/grant_entry_label_resolver.dart';
import 'package:mobile_palladin/features/grants/data/services/grant_reason_resolver.dart';
import 'package:mobile_palladin/features/grants/domain/entities/grant.dart';
import 'package:mobile_palladin/features/notifications/data/services/notification_presentation_resolver.dart';
import 'package:mobile_palladin/features/notifications/domain/entities/inbox_notification.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_entity.dart';
import 'package:mobile_palladin/features/vault/data/services/member_entry_list_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/member_index_entry.dart';

class _Remote extends Mock implements GrantsRemoteDatasource {}

class _Reasons extends Mock implements GrantReasonResolver {
  @override
  Future<T> withSharedReads<T>(
    Future<T> Function(GrantReasonResolver) operation,
  ) => operation(this);
}

class _Entries extends Mock implements MemberEntryListLoader {}

class _Index extends Mock implements MemberIndexReader {}

void main() {
  setUpAll(() => registerFallbackValue(Uint8List(0)));

  test(
    'Inbox batches same-Vault grant projections without repeated sync',
    () async {
      final remote = _Remote();
      final reasons = _Reasons();
      final entries = _Entries();
      final index = _Index();
      final session = VaultSessionStore()..setMemberPrivateKey(Uint8List(32));
      addTearDown(session.clear);
      final models = List.generate(
        8,
        (i) => GrantModel(
          id: 'grant-$i',
          vaultId: 'vault',
          agentId: 'agent',
          status: 'active',
          type: GrantScope.granular,
          createdAt: '2026-08-07T10:00:00Z',
          entryId: 'entry-$i',
        ),
      );
      final indexEntries = List.generate(
        8,
        (i) => _memberIndexEntry('entry-$i', 'Entry $i'),
      );
      var projectionCalls = 0;
      var entryLoads = 0;
      var grantReads = 0;
      when(() => remote.getGrant('vault', any())).thenAnswer((call) async {
        grantReads++;
        return models.firstWhere((m) => m.id == call.positionalArguments[1]);
      });
      when(
        () => reasons.resolve(
          grants: any(named: 'grants'),
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer((call) async {
        projectionCalls++;
        return {
          for (final m in call.namedArguments[#grants] as List<GrantModel>)
            m.id: 'Reason ${m.id}',
        };
      });
      when(
        () => entries.load(
          vaultId: 'vault',
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer((_) async {
        entryLoads++;
        return indexEntries;
      });
      when(() => index.waitForCurrent('vault')).thenAnswer((_) async {});
      when(() => index.entries('vault')).thenReturn(indexEntries);
      final resolver = NotificationPresentationResolver(
        index: index,
        grants: GrantsRepositoryImpl(
          remote,
          reasonResolver: reasons,
          entryLabelResolver: GrantEntryLabelResolver(entries: entries),
          vaultSessionStore: session,
        ),
      );
      final result = await resolver.resolve(
        items: [
          for (final m in models)
            InboxNotification(
              id: m.id,
              type: 'grant_approved',
              category: NotificationCategory.update,
              titleKey: '',
              metadata: {
                'vaultId': 'vault',
                'grantId': m.id,
                'agentId': 'agent',
              },
              actionState: NotificationActionState.none,
              occurredAt: DateTime(2026),
            ),
        ],
        unlocked: true,
        activeAccountId: 'account',
        activeOrganizationId: 'org',
        activeVaults: [
          VaultEntity(
            id: 'vault',
            name: 'Vault',
            grantMode: GrantMode.granular,
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
            entryCount: 8,
            activeGrantCount: 8,
            memberCount: 1,
          ),
        ],
      );
      expect(
        result.map((r) => r.metadata['reason']),
        models.map((m) => 'Reason ${m.id}'),
      );
      expect(
        result.map((r) => r.metadata['entryLabel']),
        List.generate(8, (i) => 'Entry $i'),
      );
      expect(grantReads, 8);
      expect(
        projectionCalls,
        8,
        reason: 'Per-row crypto projection remains independent',
      );
      expect(
        entryLoads,
        1,
        reason: 'One page must synchronize each Vault once',
      );
    },
  );

  test(
    'closing a failed scope waits for in-flight projection and wipes its key',
    () async {
      final remote = _Remote();
      final reasons = _Reasons();
      final session = VaultSessionStore()
        ..setMemberPrivateKey(Uint8List.fromList(List.filled(32, 7)));
      addTearDown(session.clear);
      final pending = Completer<Map<String, String>>();
      Uint8List? heldKey;
      when(() => remote.getGrant('vault', 'grant')).thenAnswer(
        (_) async => GrantModel(
          id: 'grant',
          vaultId: 'vault',
          agentId: 'agent',
          status: 'active',
          type: GrantScope.full,
          createdAt: '2026-08-07T10:00:00Z',
        ),
      );
      when(
        () => reasons.resolve(
          grants: any(named: 'grants'),
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer((call) {
        heldKey = call.namedArguments[#memberPrivateKey] as Uint8List;
        return pending.future;
      });
      final repository = GrantsRepositoryImpl(
        remote,
        reasonResolver: reasons,
        vaultSessionStore: session,
      );
      Future<Grant>? inFlight;
      final scope = repository.withPresentationReads<void>((read) async {
        inFlight = read('vault', 'grant');
        await Future<void>.delayed(Duration.zero);
        throw StateError('synthetic caller cancellation');
      });
      var finished = false;
      final checkedScope = expectLater(
        scope,
        throwsStateError,
      ).whenComplete(() => finished = true);
      await Future<void>.delayed(Duration.zero);
      expect(heldKey, isNotNull);
      expect(finished, false);
      pending.complete({'grant': 'Synthetic reason'});
      await checkedScope;
      await expectLater(inFlight!, throwsStateError);
      expect(heldKey, everyElement(0));
    },
  );

  for (final boundary in ['lock', 'replacement']) {
    test(
      'scope drops a delayed grant before decryption after $boundary',
      () async {
        final remote = _Remote();
        final reasons = _Reasons();
        final session = VaultSessionStore()..setMemberPrivateKey(Uint8List(32));
        addTearDown(session.clear);
        final pending = Completer<GrantModel>();
        when(
          () => remote.getGrant('vault', 'grant'),
        ).thenAnswer((_) => pending.future);
        final repository = GrantsRepositoryImpl(
          remote,
          reasonResolver: reasons,
          vaultSessionStore: session,
        );
        final scope = repository.withPresentationReads(
          (read) => read('vault', 'grant'),
        );
        final checked = expectLater(scope, throwsStateError);
        if (boundary == 'lock') {
          session.clear();
        } else {
          session.setMemberPrivateKey(Uint8List.fromList(List.filled(32, 1)));
        }
        pending.complete(
          GrantModel(
            id: 'grant',
            vaultId: 'vault',
            agentId: 'agent',
            status: 'active',
            type: GrantScope.full,
            createdAt: '2026-08-07T10:00:00Z',
          ),
        );
        await checked;
        verifyNever(
          () => reasons.resolve(
            grants: any(named: 'grants'),
            memberPrivateKey: any(named: 'memberPrivateKey'),
          ),
        );
      },
    );
  }

  test('escaped reader cannot fetch after its operation completes', () async {
    final remote = _Remote();
    final repository = GrantsRepositoryImpl(remote);
    late Future<Grant> Function(String, String) escaped;
    await repository.withPresentationReads<void>((read) async {
      escaped = read;
    });
    await expectLater(escaped('vault', 'grant'), throwsStateError);
    verifyNever(() => remote.getGrant(any(), any()));
  });

  test('full refresh projects locally decrypted reason into Grant', () async {
    final remote = _Remote();
    final reasons = _Reasons();
    final session = VaultSessionStore();
    final model = GrantModel(
      id: 'grant',
      vaultId: 'vault',
      agentId: 'agent',
      status: 'active',
      type: GrantScope.granular,
      createdAt: '2026-08-07T10:00:00Z',
      entryId: 'entry',
    );
    final memberPrivateKey = Uint8List.fromList(List<int>.filled(32, 7));
    when(
      () => remote.listOrgGrants(pageSize: 50),
    ).thenAnswer((_) async => GrantPage(grants: [model]));
    session.setMemberPrivateKey(memberPrivateKey);
    when(
      () => reasons.resolve(
        grants: [model],
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    ).thenAnswer((_) async => {'grant': 'Deploy release'});

    final page = await GrantsRepositoryImpl(
      remote,
      reasonResolver: reasons,
      vaultSessionStore: session,
    ).listOrgGrants();

    expect(page.grants.single.reason, 'Deploy release');
    session.clear();
  });

  test('projects the Entry label from the local encrypted index', () async {
    final remote = _Remote();
    final entries = _Entries();
    final session = VaultSessionStore();
    final model = GrantModel(
      id: 'grant',
      vaultId: 'vault',
      agentId: 'agent',
      status: 'active',
      type: GrantScope.granular,
      createdAt: '2026-08-07T10:00:00Z',
      entryId: 'entry',
    );
    final memberPrivateKey = Uint8List.fromList(List<int>.filled(32, 7));
    when(
      () => remote.listOrgGrants(pageSize: 50),
    ).thenAnswer((_) async => GrantPage(grants: [model]));
    when(
      () => entries.load(
        vaultId: 'vault',
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    ).thenAnswer(
      (_) async => const [
        MemberIndexEntry(
          entryId: 'entry',
          entryType: 1,
          memberLabel: 'Allegro',
          searchFields: [],
          revision: '1',
          state: MemberEntryState.active,
        ),
      ],
    );
    session.setMemberPrivateKey(memberPrivateKey);

    final page = await GrantsRepositoryImpl(
      remote,
      entryLabelResolver: GrantEntryLabelResolver(entries: entries),
      vaultSessionStore: session,
    ).listOrgGrants();

    expect(page.grants.single.entryLabel, 'Allegro');
    session.clear();
  });

  test('binds resolved labels to the complete granular Grant target', () async {
    final remote = _Remote();
    final entries = _Entries();
    final session = VaultSessionStore();
    GrantModel grant({
      required String vaultId,
      required GrantScope scope,
      String? entryId,
    }) => GrantModel(
      id: 'colliding-grant-id',
      vaultId: vaultId,
      agentId: 'agent',
      status: 'active',
      type: scope,
      createdAt: '2026-08-07T10:00:00Z',
      entryId: entryId,
    );
    final models = [
      grant(vaultId: 'vault-a', scope: GrantScope.granular, entryId: 'entry-a'),
      grant(vaultId: 'vault-b', scope: GrantScope.granular, entryId: 'entry-b'),
      grant(
        vaultId: 'vault-full',
        scope: GrantScope.full,
        entryId: 'malformed-entry',
      ),
    ];
    final memberPrivateKey = Uint8List.fromList(List<int>.filled(32, 7));
    when(
      () => remote.listOrgGrants(pageSize: 50),
    ).thenAnswer((_) async => GrantPage(grants: models));
    when(
      () => entries.load(
        vaultId: 'vault-a',
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    ).thenAnswer((_) async => [_memberIndexEntry('entry-a', 'Alpha')]);
    when(
      () => entries.load(
        vaultId: 'vault-b',
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    ).thenAnswer((_) async => [_memberIndexEntry('entry-b', 'Beta')]);
    session.setMemberPrivateKey(memberPrivateKey);

    final page = await GrantsRepositoryImpl(
      remote,
      entryLabelResolver: GrantEntryLabelResolver(entries: entries),
      vaultSessionStore: session,
    ).listOrgGrants();

    expect(page.grants.map((grant) => grant.entryLabel), [
      'Alpha',
      'Beta',
      null,
    ]);
    verifyNever(
      () => entries.load(
        vaultId: 'vault-full',
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    );
    session.clear();
  });

  test(
    'stops Entry label projection when the unlocked session is invalidated',
    () async {
      final remote = _Remote();
      final entries = _Entries();
      final session = VaultSessionStore();
      final models = [
        GrantModel(
          id: 'grant-a',
          vaultId: 'vault-a',
          agentId: 'agent',
          status: 'active',
          type: GrantScope.granular,
          createdAt: '2026-08-07T10:00:00Z',
          entryId: 'entry-a',
        ),
        GrantModel(
          id: 'grant-b',
          vaultId: 'vault-b',
          agentId: 'agent',
          status: 'active',
          type: GrantScope.granular,
          createdAt: '2026-08-07T10:00:00Z',
          entryId: 'entry-b',
        ),
      ];
      final memberPrivateKey = Uint8List.fromList(List<int>.filled(32, 7));
      when(
        () => remote.listOrgGrants(pageSize: 50),
      ).thenAnswer((_) async => GrantPage(grants: models));
      when(
        () => entries.load(
          vaultId: 'vault-a',
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer((_) async {
        session.clear();
        throw StateError('Member index load invalidated by lock');
      });
      when(
        () => entries.load(
          vaultId: 'vault-b',
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer((_) async => [_memberIndexEntry('entry-b', 'Beta')]);
      session.setMemberPrivateKey(memberPrivateKey);

      final page = await GrantsRepositoryImpl(
        remote,
        entryLabelResolver: GrantEntryLabelResolver(entries: entries),
        vaultSessionStore: session,
      ).listOrgGrants();

      expect(page.grants.map((grant) => grant.entryLabel), [null, null]);
      verifyNever(
        () => entries.load(
          vaultId: 'vault-b',
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      );
    },
  );

  test('loads independent Vault labels with bounded concurrency', () async {
    final remote = _Remote();
    final entries = _Entries();
    final session = VaultSessionStore();
    final models = List.generate(
      5,
      (index) => GrantModel(
        id: 'grant-$index',
        vaultId: 'vault-$index',
        agentId: 'agent',
        status: 'active',
        type: GrantScope.granular,
        createdAt: '2026-08-07T10:00:00Z',
        entryId: 'entry-$index',
      ),
    );
    final pending = {
      for (var index = 0; index < models.length; index++)
        'vault-$index': Completer<List<MemberIndexEntry>>(),
    };
    final started = <String>[];
    when(
      () => remote.listOrgGrants(pageSize: 50),
    ).thenAnswer((_) async => GrantPage(grants: models));
    when(
      () => entries.load(
        vaultId: any(named: 'vaultId'),
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    ).thenAnswer((invocation) {
      final vaultId = invocation.namedArguments[#vaultId]! as String;
      started.add(vaultId);
      return pending[vaultId]!.future;
    });
    session.setMemberPrivateKey(Uint8List(32));

    final pageFuture = GrantsRepositoryImpl(
      remote,
      entryLabelResolver: GrantEntryLabelResolver(entries: entries),
      vaultSessionStore: session,
    ).listOrgGrants();
    await Future<void>.delayed(Duration.zero);

    expect(started, ['vault-0', 'vault-1', 'vault-2', 'vault-3']);

    pending['vault-0']!.complete([_memberIndexEntry('entry-0', 'Entry 0')]);
    await Future<void>.delayed(Duration.zero);
    expect(started, [
      ...List.generate(4, (index) => 'vault-$index'),
      'vault-4',
    ]);

    for (var index = 1; index < models.length; index++) {
      pending['vault-$index']!.complete([
        _memberIndexEntry('entry-$index', 'Entry $index'),
      ]);
    }
    final page = await pageFuture;

    expect(
      page.grants.map((grant) => grant.entryLabel),
      List.generate(models.length, (index) => 'Entry $index'),
    );
    session.clear();
  });
}

MemberIndexEntry _memberIndexEntry(String id, String label) => MemberIndexEntry(
  entryId: id,
  entryType: 1,
  memberLabel: label,
  searchFields: const [],
  revision: '1',
  state: MemberEntryState.active,
);
