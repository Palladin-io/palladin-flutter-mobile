import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_palladin/core/widgets/skeleton_box.dart';
import 'package:mobile_palladin/features/vault/data/services/member_entry_list_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';
import 'package:mobile_palladin/features/vault/domain/repositories/entry_repository.dart';
import 'package:mobile_palladin/core/widgets/primary_button.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/entry_list_cubit.dart';
import 'package:mobile_palladin/features/vault/presentation/widgets/vault_entries_tab.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

class _Repository extends Mock implements EntryRepository {}

class _IndexLoader extends Mock implements MemberEntryListLoader {}

class _EmptyEntryListCubit extends EntryListCubit {
  _EmptyEntryListCubit([List<EntryEntity> entries = const []])
    : super(
        repository: _Repository(),
        vaultId: 'vault',
        indexLoader: _IndexLoader(),
      ) {
    emit(EntryListLoaded(entries));
  }
}

void main() {
  testWidgets('loading state uses the shared skeleton primitive', (
    tester,
  ) async {
    final entryList = EntryListCubit(
      repository: _Repository(),
      vaultId: 'vault',
      indexLoader: _IndexLoader(),
    );

    await tester.pumpWidget(
      BlocProvider<EntryListCubit>.value(
        value: entryList,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: VaultEntriesTab(onImport: () {})),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(SkeletonBox), findsNWidgets(5));

    await entryList.close();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('empty state offers a primary import action', (tester) async {
    final entryList = _EmptyEntryListCubit();
    var importCalls = 0;

    await tester.pumpWidget(
      BlocProvider<EntryListCubit>.value(
        value: entryList,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: VaultEntriesTab(onImport: () => importCalls++)),
        ),
      ),
    );

    expect(find.text('No entries yet'), findsOneWidget);
    expect(
      find.text(
        'Add an entry manually or import from another password manager.',
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
    expect(find.byIcon(Icons.file_upload_outlined), findsOneWidget);
    expect(find.byType(PrimaryButton), findsOneWidget);

    await tester.tap(find.text('Import entries'));
    expect(importCalls, 1);

    await entryList.close();
  });

  testWidgets('empty search results do not offer the import action', (
    tester,
  ) async {
    final entryList = _EmptyEntryListCubit([
      EntryEntity(
        id: 'entry-1',
        vaultId: 'vault',
        label: 'GitHub',
        type: EntryType.credential,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    ]);

    await tester.pumpWidget(
      BlocProvider<EntryListCubit>.value(
        value: entryList,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: VaultEntriesTab(onImport: () {})),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'missing');
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('No results for this search'), findsOneWidget);
    expect(find.text('No entries yet'), findsNothing);
    expect(find.text('Import entries'), findsNothing);
    expect(find.byType(PrimaryButton), findsNothing);

    await entryList.close();
  });
}
