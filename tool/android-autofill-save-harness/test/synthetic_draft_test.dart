import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_save_controller.dart';
import '../main.dart';

void main() {
  AutoFillSaveDraft draft({
    String password = 'synthetic-save-password-1',
    String source = 'io.palladin.autofill.savefixture.form',
    List<String> domains = const ['fixture.invalid'],
    bool isWeb = false,
  }) => AutoFillSaveDraft(
    id: 'opaque-capture',
    session: 'opaque-session',
    packageName: source,
    domains: domains,
    isWeb: isWeb,
    username: 'synthetic-save-user',
    password: password,
  );

  test('accepts only the expected real handoff values and native source', () {
    expect(matchesSyntheticDraft(draft()), isTrue);
    expect(matchesSyntheticDraft(draft(password: 'wrong')), isFalse);
    expect(matchesSyntheticDraft(draft(source: 'other.package')), isFalse);
    expect(matchesSyntheticDraft(draft(domains: ['other.invalid'])), isFalse);
    expect(
      matchesSyntheticDraft(
        draft(domains: ['fixture.invalid', 'other.invalid']),
      ),
      isFalse,
    );
    expect(matchesSyntheticDraft(draft(isWeb: true)), isFalse);
    final cancelled = draft()..clear();
    expect(matchesSyntheticDraft(cancelled), isFalse);
  });
  testWidgets(
    'cold startup observes pending before changing native authority',
    (tester) async {
      const channel = MethodChannel('io.palladin.mobile/autofill-save');
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            if (call.method == 'pending') return 'old-persisted-capture';
            if (call.method == 'activate') return 'synthetic-session';
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await tester.pumpWidget(const MaterialApp(home: SaveHarness()));
      await tester.pumpAndSettle();
      expect(find.text('saveColdStartEmpty=false'), findsOneWidget);
      expect(calls, ['pending']);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
