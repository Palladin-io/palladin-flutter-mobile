import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';
import 'package:mobile_palladin/features/vault/presentation/widgets/script_parameters_editor.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('editing a parameter preserves its validation constraints', (
    tester,
  ) async {
    List<ScriptParameterDefinition>? changed;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ScriptParametersEditor(
            initial: const [
              ScriptParameterDefinition(
                name: 'team_id',
                description: 'Team identifier',
                type: ScriptParameterType.string,
                required: true,
                minLength: 3,
                maxLength: 32,
                allowedValues: ['ops', 'platform'],
              ),
            ],
            onChanged: (value) => changed = value,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'group_id');
    await tester.pump();

    expect(changed, isNotNull);
    expect(changed!.single.name, 'group_id');
    expect(changed!.single.minLength, 3);
    expect(changed!.single.maxLength, 32);
    expect(changed!.single.allowedValues, ['ops', 'platform']);
  });
}
