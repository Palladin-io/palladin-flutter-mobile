import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/vault/data/services/canonical_entry_detail_service.dart';
import 'package:mobile_palladin/features/vault/data/services/local_current_entry_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/data/services/sign_in_candidate_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/member_index_entry.dart';
import 'package:mobile_palladin/features/vault/domain/entities/sign_in_method.dart';

class _Index extends Mock implements MemberIndexReader {}

class _Entries extends Mock implements LocalCurrentEntryService {}

const _vault = '22222222-2222-4222-8222-222222222222';
const _self = '11111111-1111-4111-8111-111111111111';
const _work = '33333333-3333-4333-8333-333333333333';
const _hidden = '44444444-4444-4444-8444-444444444444';
const _github = '55555555-5555-4555-8555-555555555555';
const _key = '66666666-6666-4666-8666-666666666666';
const _lookalike = '77777777-7777-4777-8777-777777777777';

MemberIndexEntry _index(
  String id,
  String domain, {
  int type = 1,
  String label = 'Entry',
}) => MemberIndexEntry(
  entryId: id,
  entryType: type,
  memberLabel: label,
  searchFields: const [],
  revision: '1',
  state: MemberEntryState.active,
  autofillDomains: [domain],
);

CanonicalEntrySnapshot _snapshot({
  required bool discoverable,
  required String username,
}) => CanonicalEntrySnapshot(
  entry: {'currentRevision': '1'},
  payload: {'username': username, 'password': 'secret'},
  secret: {
    'agentVisibilityPolicy': {'discoverable': discoverable, 'fields': {}},
  },
);

void main() {
  setUpAll(() => registerFallbackValue(Uint8List(0)));

  test(
    'offers only discoverable provider Credentials and wipes inputs',
    () async {
      final index = _Index();
      final entries = _Entries();
      when(() => index.entries(_vault)).thenReturn([
        _index(_self, 'accounts.google.com'),
        _index(_work, 'accounts.google.com', label: 'Work Google'),
        _index(_hidden, 'google.com'),
        _index(_github, 'github.com'),
        _index(_key, 'google.com', type: 0),
        _index(_lookalike, 'google.com.evil.test'),
      ]);
      final opened = <String>[];
      final snapshots = <CanonicalEntrySnapshot>[];
      when(
        () => entries.revealCurrent(
          vaultId: _vault,
          entryId: any(named: 'entryId'),
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer((invocation) async {
        final id = invocation.namedArguments[#entryId] as String;
        opened.add(id);
        final snapshot = _snapshot(
          discoverable: id == _work,
          username: id == _work ? ' alice@corp.test ' : 'bob@corp.test',
        );
        snapshots.add(snapshot);
        return snapshot;
      });
      final key = Uint8List.fromList(List.filled(32, 7));

      final result =
          await SignInCandidateService(
            index: index,
            entries: entries,
          ).candidates(
            provider: SignInProvider.google,
            vaultIds: const [_vault],
            exclude: const SignInEntryReference(
              vaultId: _vault,
              entryId: _self,
            ),
            memberPrivateKey: key,
          );

      expect(opened, [_work, _hidden]);
      expect(result, hasLength(1));
      expect(
        result.single.reference,
        const SignInEntryReference(vaultId: _vault, entryId: _work),
      );
      expect(result.single.label, 'Work Google');
      expect(result.single.account, 'alice@corp.test');
      expect(snapshots.every((snapshot) => snapshot.payload.isEmpty), isTrue);
      expect(key, everyElement(7));
    },
  );
}
