import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/agents/domain/entities/agent.dart';
import 'package:mobile_palladin/features/agents/domain/repositories/agents_repository.dart';
import 'package:mobile_palladin/features/vault/domain/entities/member_index_entry.dart';
import 'package:mobile_palladin/features/grants/domain/entities/grant.dart';
import 'package:mobile_palladin/features/grants/domain/repositories/grants_repository.dart';
import 'package:mobile_palladin/features/notifications/data/services/notification_presentation_resolver.dart';
import 'package:mobile_palladin/features/notifications/domain/entities/inbox_notification.dart';
import 'package:mobile_palladin/features/notifications/domain/repositories/notification_center_repository.dart';
import 'package:mobile_palladin/features/notifications/presentation/cubit/notification_center_cubit.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_entity.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_member.dart';
import 'package:mobile_palladin/features/vault/domain/repositories/vault_members_repository.dart';

class _Repository extends Mock implements NotificationCenterRepository {}

class _Grants extends Mock implements GrantsRepository {}

class _Index extends Mock implements MemberIndexReader {}

class _Agents extends Mock implements AgentsRepository {}

class _Members extends Mock implements VaultMembersRepository {}

Grant _grant(String id, {String? entryId, String? reason}) => Grant(
  id: id,
  vaultId: 'vault',
  agentId: 'agent',
  status: GrantStatus.active,
  scope: entryId == null ? GrantScope.full : GrantScope.granular,
  entryId: entryId,
  reason: reason ?? 'Reason $id',
  createdBy: 'actor',
  createdAt: DateTime(2026),
);

InboxNotification _item(String id, {String? grantId}) => InboxNotification(
  id: id,
  type: 'grant_approved',
  category: NotificationCategory.update,
  titleKey: '',
  metadata: {
    'vaultId': 'vault',
    'grantId': grantId ?? id,
    'agentId': 'agent',
    'reason': 'FORGED',
    'actorName': 'FORGED',
  },
  actionState: NotificationActionState.none,
  occurredAt: DateTime(2026),
);

void main() {
  late _Repository repository;
  late _Grants grants;
  late _Agents agents;
  late _Index index;
  late _Members members;
  late NotificationCenterCubit cubit;
  setUp(() {
    repository = _Repository();
    grants = _Grants();
    agents = _Agents();
    index = _Index();
    members = _Members();
    when(() => members.list(any())).thenAnswer((_) async => []);
    when(() => agents.listAgents()).thenAnswer((_) async => []);
    when(() => repository.summary()).thenAnswer(
      (_) async =>
          const NotificationSummary(unreadCount: 2, pendingActionCount: 0),
    );
    cubit = NotificationCenterCubit(
      repository: repository,
      resolver: NotificationPresentationResolver(
        index: index,
        agents: agents,
        grants: grants,
        vaultMembers: members,
      ),
    );
    cubit.configureUnlockedResolution(
      activeAccountId: 'account',
      activeOrganizationId: 'org',
      activeVaults: [
        VaultEntity(
          id: 'vault',
          name: 'Vault',
          grantMode: GrantMode.granular,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          entryCount: 0,
          activeGrantCount: 0,
          memberCount: 1,
        ),
      ],
    );
  });
  tearDown(() => cubit.close());

  test(
    'quiet refresh retains resolved rows until fresh presentation is ready',
    () async {
      when(
        () => repository.list(),
      ).thenAnswer((_) async => NotificationPage(items: [_item('same')]));
      when(
        () => grants.getGrant('vault', 'same'),
      ).thenAnswer((_) async => _grant('same', entryId: 'entry'));
      when(() => members.list('vault')).thenAnswer(
        (_) async => [
          VaultMember(
            id: 'actor',
            name: 'Local Actor',
            addedAt: DateTime(2026),
            status: VaultMemberStatus.active,
          ),
        ],
      );
      when(() => agents.listAgents()).thenAnswer(
        (_) async => [
          Agent(
            agentId: 'agent',
            name: 'Local Agent',
            status: AgentStatus.active,
            publicKeySuffix: 'suffix',
            createdAt: DateTime(2026),
          ),
        ],
      );
      when(() => index.waitForCurrent('vault')).thenAnswer((_) async {});
      when(() => index.entries('vault')).thenReturn(const [
        MemberIndexEntry(
          entryId: 'entry',
          entryType: 1,
          memberLabel: 'Local Entry',
          searchFields: [],
          revision: '1',
          state: MemberEntryState.active,
        ),
      ]);
      await cubit.load();
      final slow = Completer<Grant>();
      when(
        () => grants.getGrant('vault', 'same'),
      ).thenAnswer((_) => slow.future);
      final reasons = <Object?>[];
      final subscription = cubit.stream.listen((state) {
        reasons.add(state.items.single.metadata['reason']);
      });
      final refresh = cubit.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.items.single.metadata['reason'], 'Reason same');
      expect(cubit.state.items.single.metadata['actorName'], 'Local Actor');
      expect(cubit.state.items.single.metadata['agentName'], 'Local Agent');
      expect(cubit.state.items.single.metadata['entryLabel'], 'Local Entry');
      when(() => repository.markRead('same')).thenAnswer((_) async {});
      await cubit.markRead('same');
      slow.complete(_grant('same', reason: 'Updated reason'));
      await refresh;
      await subscription.cancel();
      expect(cubit.state.items.single.metadata['reason'], 'Updated reason');
      expect(cubit.state.items.single.metadata['entryLabel'], isNull);
      expect(cubit.state.items.single.isRead, true);
      expect(reasons, isNot(contains(null)));
    },
  );

  test(
    'quiet refresh applies remote read state before deferred hydration',
    () async {
      when(() => repository.list()).thenAnswer(
        (_) async => NotificationPage(items: [_item('first'), _item('second')]),
      );
      when(() => grants.getGrant('vault', any())).thenAnswer(
        (call) async => _grant(call.positionalArguments[1] as String),
      );
      await cubit.load();
      final readAt = DateTime.utc(2026, 10, 26);
      when(() => repository.list()).thenAnswer(
        (_) async => NotificationPage(
          items: [
            _item('first').copyWith(readAt: readAt),
            _item('second'),
          ],
        ),
      );
      when(() => repository.summary()).thenAnswer(
        (_) async =>
            const NotificationSummary(unreadCount: 1, pendingActionCount: 0),
      );
      when(() => repository.markRead('first')).thenAnswer((_) async {});
      final slow = Completer<Grant>();
      when(
        () => grants.getGrant('vault', 'first'),
      ).thenAnswer((_) => slow.future);
      final refresh = cubit.refresh();
      await Future<void>.delayed(Duration.zero);
      final beforeHydration = cubit.state.items.first;
      cubit.markReadOnView('first');
      final countAfterView = cubit.state.unreadCount;
      slow.complete(_grant('first', reason: 'Fresh reason'));
      await refresh;

      expect(countAfterView, 1);
      expect(beforeHydration.readAt, readAt);
      expect(beforeHydration.metadata['reason'], 'Reason first');
      expect(cubit.state.unreadCount, 1);
      expect(cubit.state.items.first.readAt, readAt);
      expect(cubit.state.items.first.metadata['reason'], 'Fresh reason');
      expect(cubit.state.items.last.isRead, false);
      verifyNever(() => repository.markRead('first'));
    },
  );

  test(
    'pagination waits for quiet replacement then uses its new cursor',
    () async {
      when(() => repository.list()).thenAnswer(
        (_) async =>
            NotificationPage(items: [_item('first')], nextCursor: 'old-cursor'),
      );
      when(() => grants.getGrant('vault', any())).thenAnswer(
        (call) async => _grant(call.positionalArguments[1] as String),
      );
      await cubit.load();
      when(() => repository.list()).thenAnswer(
        (_) async =>
            NotificationPage(items: [_item('first')], nextCursor: 'new-cursor'),
      );
      when(
        () => repository.list(cursor: 'old-cursor'),
      ).thenAnswer((_) async => NotificationPage(items: [_item('old-page')]));
      when(
        () => repository.list(cursor: 'new-cursor'),
      ).thenAnswer((_) async => NotificationPage(items: [_item('next-page')]));
      final slow = Completer<Grant>();
      when(
        () => grants.getGrant('vault', 'first'),
      ).thenAnswer((_) => slow.future);
      final refresh = cubit.refresh();
      await Future<void>.delayed(Duration.zero);
      await cubit.loadMore();
      expect(cubit.state.items.map((item) => item.id), ['first']);
      expect(cubit.state.isLoadingMore, false);
      expect(cubit.state.nextCursor, 'new-cursor');
      slow.complete(_grant('first'));
      await refresh;
      await cubit.loadMore();
      expect(cubit.state.items.map((item) => item.id), ['first', 'next-page']);
      expect(cubit.state.items.last.metadata['reason'], 'Reason next-page');
      expect(cubit.state.nextCursor, isNull);
      expect(cubit.state.isLoadingMore, false);
    },
  );

  test('failed quiet refresh releases pagination for retry', () async {
    when(() => repository.list()).thenAnswer(
      (_) async =>
          NotificationPage(items: [_item('first')], nextCursor: 'cursor'),
    );
    when(
      () => grants.getGrant('vault', any()),
    ).thenAnswer((call) async => _grant(call.positionalArguments[1] as String));
    await cubit.load();
    when(() => repository.list()).thenThrow(StateError('Unavailable'));
    await cubit.refresh();
    when(
      () => repository.list(cursor: 'cursor'),
    ).thenAnswer((_) async => NotificationPage(items: [_item('next-page')]));
    await cubit.loadMore();
    expect(cubit.state.items.map((item) => item.id), ['first', 'next-page']);
    expect(cubit.state.nextCursor, isNull);
    expect(cubit.state.isLoadingMore, false);
  });

  for (final markAll in [false, true]) {
    for (final succeeds in [false, true]) {
      test('quiet refresh preserves ${markAll ? "all" : "single"} read '
          '${succeeds ? "success" : "failure"} with new arrivals', () async {
        when(() => repository.list()).thenAnswer(
          (_) async =>
              NotificationPage(items: [_item('first'), _item('second')]),
        );
        when(() => grants.getGrant('vault', any())).thenAnswer(
          (call) async => _grant(call.positionalArguments[1] as String),
        );
        await cubit.load();
        when(() => repository.list()).thenAnswer(
          (_) async => NotificationPage(
            items: [_item('first'), _item('second'), _item('new')],
          ),
        );
        when(() => repository.summary()).thenAnswer(
          (_) async =>
              const NotificationSummary(unreadCount: 3, pendingActionCount: 0),
        );
        final slow = Completer<Grant>();
        when(
          () => grants.getGrant('vault', 'first'),
        ).thenAnswer((_) => slow.future);
        final refresh = cubit.refresh();
        await Future<void>.delayed(Duration.zero);
        if (markAll) {
          when(() => repository.markAllRead()).thenAnswer((_) async {
            if (!succeeds) throw StateError('Unavailable');
          });
          await cubit.markAllRead();
        } else {
          when(() => repository.markRead('first')).thenAnswer((_) async {
            if (!succeeds) throw StateError('Unavailable');
          });
          await cubit.markRead('first');
        }
        slow.complete(_grant('first'));
        await refresh;
        expect(cubit.state.unreadCount, succeeds ? (markAll ? 0 : 2) : 3);
        expect(
          cubit.state.items.map((item) => item.isRead),
          succeeds
              ? (markAll ? [true, true, true] : [true, false, false])
              : [false, false, false],
        );
      });
    }
  }

  for (final boundary in ['lock', 'reset', 'removed', 'vault removal']) {
    test('quiet refresh drops stale presentation on $boundary', () async {
      when(() => repository.list()).thenAnswer(
        (_) async => NotificationPage(items: [_item('same'), _item('removed')]),
      );
      when(() => grants.getGrant('vault', any())).thenAnswer(
        (call) async => _grant(call.positionalArguments[1] as String),
      );
      await cubit.load();
      final slow = Completer<Grant>();
      when(
        () => repository.list(),
      ).thenAnswer((_) async => NotificationPage(items: [_item('same')]));
      when(
        () => grants.getGrant('vault', 'same'),
      ).thenAnswer((_) => slow.future);
      final refresh = cubit.refresh();
      await Future<void>.delayed(Duration.zero);
      switch (boundary) {
        case 'lock':
          cubit.lock();
        case 'reset':
          cubit.reset();
        case 'vault removal':
          cubit.configureUnlockedResolution(
            activeAccountId: 'account',
            activeOrganizationId: 'org',
            activeVaults: [],
          );
          expect(
            cubit.state.items.every((item) => item.metadata['reason'] == null),
            true,
          );
        case 'removed':
          expect(cubit.state.items.map((item) => item.id), ['same']);
          expect(cubit.state.items.single.metadata['reason'], 'Reason same');
      }
      final settled = cubit.state;
      slow.complete(_grant('same', reason: 'Updated reason'));
      await refresh;
      if (boundary != 'removed') {
        expect(identical(cubit.state, settled), true);
        expect(
          cubit.state.items.every((item) => item.metadata['reason'] == null),
          true,
        );
      }
    });
  }

  test('publishes safe feed and ready metadata before a slow grant', () async {
    final slow = Completer<Grant>();
    when(() => repository.list()).thenAnswer(
      (_) async => NotificationPage(items: [_item('slow'), _item('fast')]),
    );
    when(() => grants.getGrant('vault', 'slow')).thenAnswer((_) => slow.future);
    when(
      () => grants.getGrant('vault', 'fast'),
    ).thenAnswer((_) async => _grant('fast'));
    final loading = cubit.load();
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.status, NotificationCenterStatus.loaded);
    expect(cubit.state.items.map((item) => item.id), ['slow', 'fast']);
    expect(cubit.state.items.first.metadata.containsKey('reason'), false);
    expect(cubit.state.items.first.metadata.containsKey('actorName'), false);
    expect(cubit.state.items.last.metadata['reason'], 'Reason fast');
    slow.complete(_grant('slow'));
    await loading;
    expect(cubit.state.items.first.metadata['reason'], 'Reason slow');
  });

  test(
    'all Entry labels and reasons publish while actor names are pending',
    () async {
      final response = Completer<List<VaultMember>>();
      when(() => members.list('vault')).thenAnswer((_) => response.future);
      when(() => repository.list()).thenAnswer(
        (_) async =>
            NotificationPage(items: [for (var i = 0; i < 9; i++) _item('$i')]),
      );
      when(() => grants.getGrant('vault', any())).thenAnswer(
        (invocation) async => _grant(
          invocation.positionalArguments[1] as String,
          entryId: 'entry',
        ),
      );
      when(() => index.waitForCurrent('vault')).thenAnswer((_) async {});
      when(() => index.entries('vault')).thenReturn(const [
        MemberIndexEntry(
          entryId: 'entry',
          entryType: 1,
          memberLabel: 'Local Entry',
          searchFields: [],
          revision: '1',
          state: MemberEntryState.active,
        ),
      ]);
      final loading = cubit.load();
      await Future<void>.delayed(Duration.zero);
      final beforeActors = cubit.state.items;
      response.complete([
        VaultMember(
          id: 'actor',
          name: 'Local Actor',
          addedAt: DateTime(2026),
          status: VaultMemberStatus.active,
        ),
      ]);
      await loading;
      verify(() => members.list('vault')).called(1);
      verify(() => grants.getGrant('vault', any())).called(9);
      expect(beforeActors.map((item) => item.metadata['reason']), [
        for (var i = 0; i < 9; i++) 'Reason $i',
      ]);
      expect(
        beforeActors.every(
          (item) => item.metadata['entryLabel'] == 'Local Entry',
        ),
        true,
      );
      expect(
        cubit.state.items.every(
          (item) => item.metadata['actorName'] == 'Local Actor',
        ),
        true,
      );
      expect(
        cubit.state.items.every(
          (item) => item.metadata['entryLabel'] == 'Local Entry',
        ),
        true,
      );
    },
  );
  test(
    'all Entry labels and reasons publish while Agent names are pending',
    () async {
      final response = Completer<List<Agent>>();
      when(() => agents.listAgents()).thenAnswer((_) => response.future);
      when(() => repository.list()).thenAnswer(
        (_) async =>
            NotificationPage(items: [for (var i = 0; i < 9; i++) _item('$i')]),
      );
      when(() => grants.getGrant('vault', any())).thenAnswer(
        (invocation) async => _grant(
          invocation.positionalArguments[1] as String,
          entryId: 'entry',
        ),
      );
      when(() => index.waitForCurrent('vault')).thenAnswer((_) async {});
      when(() => index.entries('vault')).thenReturn(const [
        MemberIndexEntry(
          entryId: 'entry',
          entryType: 1,
          memberLabel: 'Local Entry',
          searchFields: [],
          revision: '1',
          state: MemberEntryState.active,
        ),
      ]);
      final loading = cubit.load();
      await Future<void>.delayed(Duration.zero);
      final beforeAgents = cubit.state.items;
      response.complete([
        Agent(
          agentId: 'agent',
          name: 'Local Agent',
          status: AgentStatus.active,
          publicKeySuffix: 'suffix',
          createdAt: DateTime(2026),
        ),
      ]);
      await loading;
      expect(beforeAgents.map((item) => item.metadata['reason']), [
        for (var i = 0; i < 9; i++) 'Reason $i',
      ]);
      expect(
        beforeAgents.every(
          (item) => item.metadata['entryLabel'] == 'Local Entry',
        ),
        true,
      );
      expect(
        cubit.state.items.every(
          (item) => item.metadata['agentName'] == 'Local Agent',
        ),
        true,
      );
      expect(
        cubit.state.items.every(
          (item) => item.metadata['entryLabel'] == 'Local Entry',
        ),
        true,
      );
    },
  );

  test('shares duplicate grant requests within one page', () async {
    when(() => repository.list()).thenAnswer(
      (_) async => NotificationPage(
        items: [
          _item('first', grantId: 'same'),
          _item('second', grantId: 'same'),
        ],
      ),
    );
    when(
      () => grants.getGrant('vault', 'same'),
    ).thenAnswer((_) async => _grant('same'));
    await cubit.load();
    expect(cubit.state.items.map((item) => item.metadata['reason']), [
      'Reason same',
      'Reason same',
    ]);
    verify(() => grants.getGrant('vault', 'same')).called(1);
  });
  test(
    'bounds active grant hydration while keeping the whole feed visible',
    () async {
      final pending = List.generate(9, (_) => Completer<Grant>());
      var started = 0;
      when(() => repository.list()).thenAnswer(
        (_) async =>
            NotificationPage(items: [for (var i = 0; i < 9; i++) _item('$i')]),
      );
      when(() => grants.getGrant('vault', any())).thenAnswer((invocation) {
        started++;
        return pending[int.parse(invocation.positionalArguments[1] as String)]
            .future;
      });
      final loading = cubit.load();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.items.length, 9);
      expect(started, inInclusiveRange(2, 4));
      for (var i = 0; i < 9; i++) {
        pending[i].complete(_grant('$i'));
      }
      await loading;
      expect(
        cubit.state.items.every((item) => item.metadata['reason'] != null),
        true,
      );
    },
  );

  for (final boundary in ['refresh', 'lock', 'reset']) {
    test('delayed grant metadata cannot overwrite $boundary', () async {
      final slow = Completer<Grant>();
      when(
        () => repository.list(),
      ).thenAnswer((_) async => NotificationPage(items: [_item('slow')]));
      when(
        () => grants.getGrant('vault', 'slow'),
      ).thenAnswer((_) => slow.future);
      final loading = cubit.load();
      await Future<void>.delayed(Duration.zero);
      switch (boundary) {
        case 'refresh':
          when(
            () => repository.list(),
          ).thenAnswer((_) async => const NotificationPage(items: []));
          await cubit.refresh();
        case 'lock':
          cubit.lock();
        case 'reset':
          cubit.reset();
      }
      final settled = cubit.state;
      slow.complete(_grant('slow'));
      await loading;
      expect(identical(cubit.state, settled), true);
      expect(
        cubit.state.items.every((item) => !item.metadata.containsKey('reason')),
        true,
      );
    });
  }

  test('actor directory reads remain bounded across distinct Vaults', () async {
    final pending = List.generate(5, (_) => Completer<List<VaultMember>>());
    var active = 0;
    var maximum = 0;
    final started = <String>[];
    cubit.configureUnlockedResolution(
      activeAccountId: 'account',
      activeOrganizationId: 'org',
      activeVaults: [
        for (var i = 0; i < 5; i++)
          VaultEntity(
            id: 'vault-$i',
            name: 'Vault $i',
            grantMode: GrantMode.granular,
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
            entryCount: 0,
            activeGrantCount: 1,
            memberCount: 1,
          ),
      ],
    );
    when(() => repository.list()).thenAnswer(
      (_) async => NotificationPage(
        items: [
          for (var i = 0; i < 5; i++)
            _item('$i').copyWith(
              metadata: {
                'vaultId': 'vault-$i',
                'grantId': '$i',
                'agentId': 'agent',
              },
            ),
        ],
      ),
    );
    when(() => grants.getGrant(any(), any())).thenAnswer(
      (call) async => Grant(
        id: call.positionalArguments[1] as String,
        vaultId: call.positionalArguments[0] as String,
        agentId: 'agent',
        status: GrantStatus.active,
        scope: GrantScope.full,
        reason: 'Ready',
        createdBy: 'actor',
        createdAt: DateTime(2026),
      ),
    );
    when(() => members.list(any())).thenAnswer((call) async {
      final vault = call.positionalArguments.single as String;
      started.add(vault);
      active++;
      if (active > maximum) maximum = active;
      try {
        return await pending[int.parse(vault.split('-').last)].future;
      } finally {
        active--;
      }
    });
    final loading = cubit.load();
    await Future<void>.delayed(Duration.zero);
    expect(
      cubit.state.items.every((item) => item.metadata['reason'] == 'Ready'),
      true,
    );
    expect(started.length, 4);
    pending[0].complete([]);
    await Future<void>.delayed(Duration.zero);
    expect(started.length, 5);
    for (var i = 1; i < 5; i++) {
      pending[i].complete([]);
    }
    await loading;
    expect(maximum, 4);
    expect(started.toSet().length, 5);
  });

  for (final boundary in ['refresh', 'lock', 'reset', 'vault removal']) {
    test('delayed actor metadata cannot overwrite $boundary', () async {
      final directory = Completer<List<VaultMember>>();
      when(() => members.list('vault')).thenAnswer((_) => directory.future);
      when(
        () => repository.list(),
      ).thenAnswer((_) async => NotificationPage(items: [_item('one')]));
      when(
        () => grants.getGrant('vault', 'one'),
      ).thenAnswer((_) async => _grant('one'));
      final loading = cubit.load();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.items.single.metadata['reason'], 'Reason one');
      switch (boundary) {
        case 'refresh':
          when(
            () => repository.list(),
          ).thenAnswer((_) async => const NotificationPage(items: []));
          await cubit.refresh();
        case 'lock':
          cubit.lock();
        case 'reset':
          cubit.reset();
        case 'vault removal':
          cubit.configureUnlockedResolution(
            activeAccountId: 'account',
            activeOrganizationId: 'org',
            activeVaults: [],
          );
      }
      final settled = cubit.state;
      directory.complete([
        VaultMember(
          id: 'actor',
          name: 'Late Actor',
          addedAt: DateTime(2026),
          status: VaultMemberStatus.active,
        ),
      ]);
      await loading;
      expect(identical(cubit.state, settled), true);
      expect(
        cubit.state.items.every((item) => item.metadata['actorName'] == null),
        true,
      );
    });
  }

  for (final actorFirst in [true, false]) {
    test(
      'actor and Agent completions merge latest metadata (actorFirst=$actorFirst)',
      () async {
        final directory = Completer<List<VaultMember>>();
        final agentNames = Completer<List<Agent>>();
        when(() => members.list('vault')).thenAnswer((_) => directory.future);
        when(() => agents.listAgents()).thenAnswer((_) => agentNames.future);
        when(
          () => repository.list(),
        ).thenAnswer((_) async => NotificationPage(items: [_item('one')]));
        when(
          () => grants.getGrant('vault', 'one'),
        ).thenAnswer((_) async => _grant('one'));
        final loading = cubit.load();
        await Future<void>.delayed(Duration.zero);
        void completeActor() => directory.complete([
          VaultMember(
            id: 'actor',
            name: 'Local Actor',
            addedAt: DateTime(2026),
            status: VaultMemberStatus.active,
          ),
        ]);
        void completeAgent() => agentNames.complete([
          Agent(
            agentId: 'agent',
            name: 'Local Agent',
            status: AgentStatus.active,
            publicKeySuffix: 'suffix',
            createdAt: DateTime(2026),
          ),
        ]);
        if (actorFirst) {
          completeActor();
        } else {
          completeAgent();
        }
        await Future<void>.delayed(Duration.zero);
        if (actorFirst) {
          completeAgent();
        } else {
          completeActor();
        }
        await loading;
        expect(
          cubit.state.items.single.metadata,
          containsPair('actorName', 'Local Actor'),
        );
        expect(
          cubit.state.items.single.metadata,
          containsPair('agentName', 'Local Agent'),
        );
        expect(
          cubit.state.items.single.metadata,
          containsPair('reason', 'Reason one'),
        );
      },
    );
  }

  test('metadata completion preserves a concurrent mark-read', () async {
    final slow = Completer<Grant>();
    when(
      () => repository.list(),
    ).thenAnswer((_) async => NotificationPage(items: [_item('slow')]));
    when(() => grants.getGrant('vault', 'slow')).thenAnswer((_) => slow.future);
    when(() => repository.markRead('slow')).thenAnswer((_) async {});
    final loading = cubit.load();
    await Future<void>.delayed(Duration.zero);
    await cubit.markRead('slow');
    slow.complete(_grant('slow'));
    await loading;
    expect(cubit.state.items.single.isRead, true);
    expect(cubit.state.items.single.metadata['reason'], 'Reason slow');
    expect(cubit.state.unreadCount, 1);
  });
}
