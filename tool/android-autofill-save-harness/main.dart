import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_save_controller.dart';

const fixturePackage = 'io.palladin.autofill.savefixture.form';
const fixturePrincipal = 'synthetic-save-member';

bool matchesSyntheticDraft(AutoFillSaveDraft draft) =>
    draft.valid &&
    !draft.isWeb &&
    draft.packageName == fixturePackage &&
    listEquals(draft.domains, const ['fixture.invalid']) &&
    draft.username == 'synthetic-save-user' &&
    draft.password == 'synthetic-save-password-1';

void main() {
  if (!kDebugMode) throw StateError('Synthetic save fixture is debug-only');
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: SaveHarness()));
}

class SaveHarness extends StatefulWidget {
  const SaveHarness({super.key});
  @override
  State<SaveHarness> createState() => _SaveHarnessState();
}

class _SaveHarnessState extends State<SaveHarness> with WidgetsBindingObserver {
  final controller = AutoFillSaveController();
  static const channel = MethodChannel('io.palladin.mobile/autofill-save');
  String status = 'saveHarnessReady=false';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller.onDraft = verifyHandoff;
    arm();
  }

  Future<void> arm({bool hold = false}) async {
    await controller.synchronize(null, unlocked: false);
    await controller.synchronize(fixturePrincipal, unlocked: true);
    if (hold) await controller.synchronize(fixturePrincipal, unlocked: false);
    update(hold ? 'saveHoldReady=true' : 'saveHarnessReady=true');
  }

  Future<void> verifyHandoff(AutoFillSaveDraft draft) async {
    final matches = matchesSyntheticDraft(draft);
    final valid = await controller.validate(draft, 'fixture.invalid');
    final replay = await channel.invokeMethod<Object?>('take', {
      'id': draft.id,
      'session': draft.session,
    });
    controller.cancelDraft(draft);
    update('saveHandoffVerified=${matches && valid && replay == null}');
  }

  Future<void> checkPending() async {
    final pending = await channel.invokeMethod<String>('pending');
    update('savePendingVerified=${pending != null}');
  }

  Future<void> revoke() async {
    await controller.synchronize(null, unlocked: false);
    final pending = await channel.invokeMethod<String>('pending');
    update(
      'saveRevokedVerified=${pending == null && controller.draft == null}',
    );
  }

  void update(String value) {
    if (mounted) setState(() => status = value);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) controller.resume();
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      controller.background();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(status),
            TextButton(onPressed: arm, child: const Text('Arm save')),
            TextButton(
              onPressed: () => arm(hold: true),
              child: const Text('Hold pending save'),
            ),
            TextButton(
              onPressed: checkPending,
              child: const Text('Check pending'),
            ),
            TextButton(
              onPressed: revoke,
              child: const Text('Revoke synthetic session'),
            ),
          ],
        ),
      ),
    ),
  );
}
