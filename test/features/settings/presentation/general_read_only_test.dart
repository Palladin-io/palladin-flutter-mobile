import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_palladin/features/settings/domain/entities/org.dart';
import 'package:mobile_palladin/features/settings/domain/repositories/settings_repository.dart';
import 'package:mobile_palladin/features/settings/presentation/bloc/settings_cubit.dart';
import 'package:mobile_palladin/features/settings/presentation/widgets/org_settings_section.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

class _Repository extends Mock implements SettingsRepository {}

void main() {
  testWidgets('General is read-only without OrganizationManagement', (
    tester,
  ) async {
    final repository = _Repository();
    when(() => repository.getOrg()).thenAnswer(
      (_) async => const Org(
        orgId: 'org-1',
        name: 'Acme',
        planType: 'Free',
        memberCount: 2,
        seatUsage: 2,
        seatLimit: 2,
      ),
    );
    final cubit = SettingsCubit(repository: repository);
    await cubit.load();
    addTearDown(cubit.close);

    await tester.pumpWidget(
      BlocProvider<SettingsCubit>.value(
        value: cubit,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: OrgSettingsSection(canEdit: false)),
        ),
      ),
    );

    expect(
      find.text(
        'You can view these settings, but only an organization manager can change them.',
      ),
      findsOneWidget,
    );
    expect(find.text('Save'), findsNothing);
    expect(
      find.byKey(const ValueKey('organization-save-footer')),
      findsNothing,
    );
    expect(find.text('Organization'), findsNothing);
    expect(find.text('2 members'), findsNothing);
    expect(find.text('About'), findsNothing);
    expect(find.text('Open-source licences'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    verifyNever(() => repository.updateOrgName(any()));
  });

  testWidgets('General pins Save below the organization-name card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _Repository();
    when(() => repository.getOrg()).thenAnswer(
      (_) async => const Org(
        orgId: 'org-1',
        name: 'Acme',
        planType: 'Free',
        memberCount: 2,
        seatUsage: 2,
        seatLimit: 2,
      ),
    );
    final cubit = SettingsCubit(repository: repository);
    await cubit.load();
    addTearDown(cubit.close);

    await tester.pumpWidget(
      BlocProvider<SettingsCubit>.value(
        value: cubit,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: OrgSettingsSection(canEdit: true)),
        ),
      ),
    );

    final card = find.byKey(const ValueKey('organization-name-card'));
    final footer = find.byKey(const ValueKey('organization-save-footer'));
    expect(card, findsOneWidget);
    expect(footer, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.text('Save')),
      findsNothing,
    );
    expect(
      find.descendant(of: footer, matching: find.text('Save')),
      findsOneWidget,
    );
    expect(tester.getSize(footer).width, 430);
    expect(tester.getBottomLeft(footer).dy, 932);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
  });
}
