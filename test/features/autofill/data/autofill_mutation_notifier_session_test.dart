import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_mutation_notifier.dart';

void main() {
  test(
    'old lease cannot finish a replacement account mutation batch',
    () async {
      final notifier = AutoFillMutationNotifier();
      final actions = <AutoFillMutationAction>[];
      notifier.attachHandler((action) async => actions.add(action));
      final old = await notifier.beginMutation();
      notifier.resetSession();
      final current = await notifier.beginMutation();
      await old.complete();
      expect(actions, [
        AutoFillMutationAction.invalidate,
        AutoFillMutationAction.invalidate,
      ]);
      await current.complete();
      expect(actions.last, AutoFillMutationAction.rebuild);
      expect(actions.length, 3);
    },
  );

  test(
    'account replacement during denial cannot admit old remote mutation',
    () async {
      final notifier = AutoFillMutationNotifier();
      final gate = Completer<void>();
      notifier.attachHandler((_) => gate.future);
      final old = notifier.beginMutation();
      final rejected = expectLater(old, throwsStateError);
      notifier.resetSession();
      gate.complete();
      await rejected;
    },
  );
  test(
    'late failed admission cannot refresh the already finished new batch',
    () async {
      final notifier = AutoFillMutationNotifier();
      final gate = Completer<void>();
      final actions = <AutoFillMutationAction>[];
      notifier.attachHandler((action) async {
        actions.add(action);
        if (actions.length == 1) await gate.future;
      });
      final old = notifier.beginMutation();
      final rejected = expectLater(old, throwsStateError);
      notifier.resetSession();
      final current = await notifier.beginMutation();
      await current.complete();
      gate.complete();
      await rejected;
      expect(actions, [
        AutoFillMutationAction.invalidate,
        AutoFillMutationAction.invalidate,
        AutoFillMutationAction.rebuild,
      ]);
    },
  );
}
