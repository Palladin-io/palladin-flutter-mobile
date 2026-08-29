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
import 'package:mobile_palladin/features/vault/data/services/member_entry_list_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/member_index_entry.dart';

class _Remote extends Mock implements GrantsRemoteDatasource {}

class _Reasons extends Mock implements GrantReasonResolver {}

class _Entries extends Mock implements MemberEntryListLoader {}

void main() {
  setUpAll(() => registerFallbackValue(Uint8List(0)));

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
