import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_palladin/features/api_keys/presentation/bloc/api_keys_cubit.dart';
import 'package:mobile_palladin/features/api_keys/presentation/widgets/generate_api_key_sheet.dart';
import 'package:mobile_palladin/features/settings/domain/entities/api_key.dart';
import 'package:mobile_palladin/features/settings/domain/repositories/settings_repository.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

class _MockSettingsRepository extends Mock implements SettingsRepository {}

void main() {
  late _MockSettingsRepository repository;

  setUp(() {
    repository = _MockSettingsRepository();
    when(() => repository.listApiKeys()).thenAnswer((_) async => <ApiKey>[]);
  });

  Future<void> pumpSheet(WidgetTester tester) async {
    final cubit = ApiKeysCubit(repository: repository);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: BlocProvider<ApiKeysCubit>.value(
            value: cubit,
            child: const GenerateApiKeySheet(),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'reveal phase shows the title-cased header and connect command with the '
    'agent name',
    (tester) async {
      when(() => repository.createApiKey('My Agent')).thenAnswer(
        (_) async => NewApiKey(
          apiKeyId: 'k1',
          name: 'My Agent',
          plaintext: 'pl_secret_xyz',
          createdAt: DateTime.utc(2026, 6, 1),
        ),
      );

      await pumpSheet(tester);

      await tester.enterText(find.byType(TextField).first, 'My Agent');
      await tester.pump();
      await tester.tap(find.text('Generate'));
      await tester.pumpAndSettle();

      // Title is Title Case, with the API acronym intact.
      expect(find.text('API Key Created'), findsOneWidget);

      // The connect command embeds the plaintext and the agent name.
      expect(
        find.textContaining('palladin connect pl_secret_xyz --id "My Agent"'),
        findsOneWidget,
      );

      // The connect section is present (default-open collapsible header).
      expect(find.text('Connect your agent'), findsOneWidget);
    },
  );

  testWidgets('connect command updates live when the agent name is edited', (
    tester,
  ) async {
    when(() => repository.createApiKey('Prod')).thenAnswer(
      (_) async => NewApiKey(
        apiKeyId: 'k2',
        name: 'Prod',
        plaintext: 'pl_abc',
        createdAt: DateTime.utc(2026, 6, 1),
      ),
    );

    await pumpSheet(tester);

    await tester.enterText(find.byType(TextField).first, 'Prod');
    await tester.pump();
    await tester.tap(find.text('Generate'));
    await tester.pumpAndSettle();

    // Edit the agent-name field in the connect section.
    await tester.enterText(find.byType(TextField).first, 'Renamed');
    await tester.pump();

    expect(
      find.textContaining('palladin connect pl_abc --id "Renamed"'),
      findsOneWidget,
    );
  });
}
