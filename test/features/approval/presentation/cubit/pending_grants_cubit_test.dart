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

  test(
    'event refresh queues exactly one request after an active load',
    () async {
      final repository = _Repository();
      final first = Completer<List<PendingGrant>>();
      final trailing = Completer<List<PendingGrant>>();
      var calls = 0;
      when(repository.listPendingGrants).thenAnswer((_) {
        calls += 1;
        return calls == 1 ? first.future : trailing.future;
      });
      final cubit = PendingGrantsCubit(repository: repository);

      final load = cubit.load();
      final fresh = cubit.refresh(ensureFresh: true);
      final sameFresh = cubit.refresh(ensureFresh: true);

      expect(identical(fresh, sameFresh), isTrue);
      first.complete(const []);
      await load;
      expect(calls, 2);

      trailing.complete(const []);
      await Future.wait([fresh, sameFresh]);

      verify(repository.listPendingGrants).called(2);
      await cubit.close();
    },
  );
}
