import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/vault/data/services/sign_in_candidate_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/sign_in_method.dart';
import 'package:mobile_palladin/features/vault/presentation/widgets/sign_in_method_sheet.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

const _reference = SignInEntryReference(
  vaultId: '22222222-2222-4222-8222-222222222222',
  entryId: '33333333-3333-4333-8333-333333333333',
);

void main() {
  late AppLocalizations l10n;
  final requested = <SignInProvider>[];

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  Future<List<SignInProviderCandidate>> loader(SignInProvider provider) async {
    requested.add(provider);
    return provider == SignInProvider.google
        ? const [
            SignInProviderCandidate(
              reference: _reference,
              label: 'Work Google',
              account: 'alice@corp.test',
            ),
          ]
        : const [];
  }

  Future<void> chooseProvider(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(const ValueKey('sign-in-method-provider')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(name).last);
    await tester.pumpAndSettle();
  }

  Future<void> chooseLinked(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('sign-in-method-linked-entry')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Work Google · alice@corp.test').last);
    await tester.pumpAndSettle();
  }

  TextField accountField(WidgetTester tester) => tester.widget<TextField>(
    find.descendant(
      of: find.byKey(const ValueKey('sign-in-method-account')),
      matching: find.byType(TextField),
    ),
  );

  setUp(requested.clear);

  testWidgets('linking a provider Credential sets account and entry', (
    tester,
  ) async {
    SignInMethodChoice? choice;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => choice = await SignInMethodSheet.show(
              context,
              canRemove: false,
              loadCandidates: loader,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('sign-in-method-linked-entry')),
      findsNothing,
    );

    await chooseProvider(tester, 'GitHub');
    expect(requested, [SignInProvider.github]);
    expect(find.text(l10n.entrySignInMethodLinkedEntryEmpty), findsOneWidget);

    await chooseProvider(tester, 'Google');
    await chooseLinked(tester);
    expect(accountField(tester).controller?.text, 'alice@corp.test');
    expect(find.text(l10n.entrySignInMethodAgentHint), findsOneWidget);

    await tester.tap(find.text(l10n.entrySaveAction));
    await tester.pumpAndSettle();
    expect(
      choice?.binding,
      const SignInMethodBinding(
        provider: SignInProvider.google,
        account: 'alice@corp.test',
        entry: _reference,
      ),
    );
  });

  testWidgets('typing an account clears the linked Credential', (tester) async {
    SignInMethodChoice? choice;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => choice = await SignInMethodSheet.show(
              context,
              initial: const SignInMethodBinding(
                provider: SignInProvider.google,
                account: 'alice@corp.test',
                entry: _reference,
              ),
              canRemove: true,
              loadCandidates: loader,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Work Google · alice@corp.test'), findsOneWidget);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('sign-in-method-account')),
        matching: find.byType(TextField),
      ),
      'other@corp.test',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.entrySaveAction));
    await tester.pumpAndSettle();
    expect(
      choice?.binding,
      const SignInMethodBinding(
        provider: SignInProvider.google,
        account: 'other@corp.test',
      ),
    );
  });

  testWidgets('a stale link is dropped when it is no longer offered', (
    tester,
  ) async {
    SignInMethodChoice? choice;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => choice = await SignInMethodSheet.show(
              context,
              initial: const SignInMethodBinding(
                provider: SignInProvider.github,
                account: 'octo',
                entry: _reference,
              ),
              canRemove: true,
              loadCandidates: loader,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.entrySaveAction));
    await tester.pumpAndSettle();
    expect(choice?.binding?.entry, isNull);
    expect(choice?.binding?.account, 'octo');
  });

  testWidgets('a small screen with large text and keyboard keeps the form '
      'scrollable above the footer', (tester) async {
    tester.view
      ..physicalSize = const Size(320, 480)
      ..devicePixelRatio = 1
      ..viewInsets = const FakeViewPadding(bottom: 260);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.reset();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    SignInMethodChoice? choice;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => choice = await SignInMethodSheet.show(
              context,
              initial: const SignInMethodBinding(
                provider: SignInProvider.google,
              ),
              canRemove: true,
              loadCandidates: loader,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final account = find.descendant(
      of: find.byKey(const ValueKey('sign-in-method-account')),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(account);
    await tester.pumpAndSettle();
    await tester.enterText(account, 'qa@corp.test');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(
      find.byKey(const ValueKey('sign-in-method-remove')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('sign-in-method-remove')).hitTestable(),
      findsOneWidget,
    );

    final save = find.text(l10n.entrySaveAction);
    expect(save.hitTestable(), findsOneWidget);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(
      choice?.binding,
      const SignInMethodBinding(
        provider: SignInProvider.google,
        account: 'qa@corp.test',
      ),
    );
  });
}
