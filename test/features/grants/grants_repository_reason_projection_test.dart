import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/core/crypto/vault_session_store.dart';
import 'package:mobile_palladin/features/grants/data/datasources/grants_remote_datasource.dart';
import 'package:mobile_palladin/features/grants/data/models/grant_model.dart';
import 'package:mobile_palladin/features/grants/data/repositories/grants_repository_impl.dart';
import 'package:mobile_palladin/features/grants/data/services/grant_reason_resolver.dart';
import 'package:mobile_palladin/features/grants/domain/entities/grant.dart';

class _Remote extends Mock implements GrantsRemoteDatasource {}

class _Reasons extends Mock implements GrantReasonResolver {}

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
}
