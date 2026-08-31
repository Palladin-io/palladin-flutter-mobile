import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_palladin/features/vault/data/services/member_entry_list_service.dart';
import 'package:mobile_palladin/features/vault/domain/repositories/entry_repository.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/entry_list_cubit.dart';
import 'package:mobile_palladin/features/vault/presentation/widgets/vault_entries_tab.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

class _Repository extends Mock implements EntryRepository {}

class _IndexLoader extends Mock implements MemberEntryListLoader {}

class _EmptyEntryListCubit extends EntryListCubit {
  _EmptyEntryListCubit()
    : super(
        repository: _Repository(),
        vaultId: 'vault',
        indexLoader: _IndexLoader(),
      ) {
    emit(const EntryListLoaded([]));
  }
}

void main() {
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
    expect(find.byType(ElevatedButton), findsOneWidget);

    await tester.tap(find.text('Import entries'));
    expect(importCalls, 1);

    await entryList.close();
  });
}
