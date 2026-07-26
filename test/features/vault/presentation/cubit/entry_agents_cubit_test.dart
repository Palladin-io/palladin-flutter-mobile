import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_palladin/features/vault/data/services/canonical_entry_detail_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/agent_visibility_policy.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/entry_agents_cubit.dart';

class _Service extends Mock implements CanonicalEntryDetailService {}

void main() {
  late _Service service;
  late EntryAgentsCubit cubit;
  final entry = EntryEntity(
    id: '33333333-3333-4333-8333-333333333333',
    vaultId: '22222222-2222-4222-8222-222222222222',
    label: 'Member label',
    type: EntryType.credential,
    createdAt: DateTime.utc(2026, 7, 1),
    updatedAt: DateTime.utc(2026, 7, 2),
  );

  CanonicalEntrySnapshot snapshot() => CanonicalEntrySnapshot(
    entry: {
      'organizationId': '11111111-1111-4111-8111-111111111111',
      'vaultId': entry.vaultId,
      'id': entry.id,
    },
    payload: {'username': 'visible-user', 'password': 'secret'},
    secret: {
      'memberLabel': 'Member label',
      'agentLabel': 'Agent account',
      'agentVisibilityPolicy': {
        'discoverable': true,
        'fields': {
          'agentLabel': 'discovery',
          'username': 'discovery',
          'password': 'onGrantValue',
        },
      },
    },
  );

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(entry);
    registerFallbackValue(snapshot());
    registerFallbackValue(
      AgentVisibilityPolicy(
        discoverable: true,
        fields: const {'agentLabel': AgentFieldAccess.discovery},
      ),
    );
  });

  setUp(() {
    service = _Service();
    cubit = EntryAgentsCubit(service);
  });

  tearDown(() => cubit.close());

  test(
    'load exposes Discovery preview only and wipes caller key copy',
    () async {
      final key = Uint8List.fromList(List<int>.filled(32, 7));
      when(
        () => service.reveal(
          expected: entry,
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer((_) async => snapshot());

      await cubit.load(entry: entry, memberPrivateKey: key);

      final state = cubit.state as EntryAgentsLoaded;
      expect(state.discoveryPreview.toString(), contains('visible-user'));
      expect(state.discoveryPreview.toString(), isNot(contains('secret')));
      expect(key, everyElement(0));
    },
  );

  test(
    'save submits one policy mutation and invalidates plaintext snapshot',
    () async {
      when(
        () => service.reveal(
          expected: entry,
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer((_) async => snapshot());
      when(
        () => service.update(
          snapshot: any(named: 'snapshot'),
          expected: entry,
          label: any(named: 'label'),
          description: any(named: 'description'),
          icon: any(named: 'icon'),
          type: EntryType.credential,
          content: any(named: 'content'),
          memberPrivateKey: any(named: 'memberPrivateKey'),
          agentVisibilityPolicy: any(named: 'agentVisibilityPolicy'),
          agentLabel: any(named: 'agentLabel'),
        ),
      ).thenAnswer((_) async => entry);
      await cubit.load(
        entry: entry,
        memberPrivateKey: Uint8List.fromList(List<int>.filled(32, 1)),
      );
      final key = Uint8List.fromList(List<int>.filled(32, 2));

      await cubit.save(key);

      expect(cubit.state, isA<EntryAgentsSaved>());
      expect(key, everyElement(0));
      verify(
        () => service.update(
          snapshot: any(named: 'snapshot'),
          expected: entry,
          label: any(named: 'label'),
          description: any(named: 'description'),
          icon: any(named: 'icon'),
          type: EntryType.credential,
          content: any(named: 'content'),
          memberPrivateKey: any(named: 'memberPrivateKey'),
          agentVisibilityPolicy: any(named: 'agentVisibilityPolicy'),
          agentLabel: any(named: 'agentLabel'),
        ),
      ).called(1);
    },
  );

  test(
    'stale revision is an explicit conflict and key copy is wiped',
    () async {
      when(
        () => service.reveal(
          expected: entry,
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer((_) async => snapshot());
      when(
        () => service.update(
          snapshot: any(named: 'snapshot'),
          expected: entry,
          label: any(named: 'label'),
          description: any(named: 'description'),
          icon: any(named: 'icon'),
          type: EntryType.credential,
          content: any(named: 'content'),
          memberPrivateKey: any(named: 'memberPrivateKey'),
          agentVisibilityPolicy: any(named: 'agentVisibilityPolicy'),
          agentLabel: any(named: 'agentLabel'),
        ),
      ).thenThrow(
        const CanonicalEntryDetailException(CanonicalEntryDetailError.conflict),
      );
      await cubit.load(
        entry: entry,
        memberPrivateKey: Uint8List.fromList(List<int>.filled(32, 1)),
      );
      final key = Uint8List.fromList(List<int>.filled(32, 2));

      await cubit.save(key);

      expect(cubit.state, isA<EntryAgentsConflict>());
      expect(key, everyElement(0));
    },
  );
}
