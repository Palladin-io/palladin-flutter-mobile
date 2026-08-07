import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/approval/domain/repositories/approval_repository.dart';
import 'package:mobile_palladin/features/approval/presentation/cubit/pending_grants_cubit.dart';

class _Repository extends Mock implements ApprovalRepository {}

void main() {
  test('load and refresh share one pending-grants request', () async {
    final repository = _Repository();
    final pending = Completer<List<PendingGrant>>();
    when(repository.listPendingGrants).thenAnswer((_) => pending.future);
    final cubit = PendingGrantsCubit(repository: repository);

    final load = cubit.load();
    final refresh = cubit.refresh();

    expect(identical(load, refresh), isTrue);
    pending.complete(const []);
    await Future.wait([load, refresh]);

    verify(repository.listPendingGrants).called(1);
    expect(cubit.state.status, PendingGrantsStatus.loaded);
    await cubit.close();
  });
}
