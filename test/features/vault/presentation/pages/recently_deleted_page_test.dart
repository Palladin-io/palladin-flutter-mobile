import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mobile_palladin/features/vault/data/datasources/entry_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/services/canonical_entry_detail_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_entry_list_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/recently_deleted_cubit.dart';
import 'package:mobile_palladin/features/vault/presentation/pages/recently_deleted_page.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

class _Remote extends Mock implements EntryRemoteDatasource {}

class _Index extends Mock implements MemberIndexReader {}

class _Sync extends Mock implements MemberEntryListLoader {}

class _Lifecycle extends Mock implements EntryArchiveRestorer {}

class _Auth extends Mock implements AuthBloc {}

class _PageCubit extends RecentlyDeletedCubit {
  _PageCubit()
    : super(
        vaultId: 'vault',
        remote: _Remote(),
        index: _Index(),
        sync: _Sync(),
        lifecycle: _Lifecycle(),
      ) {
    emit(
      RecentlyDeletedLoaded(
        items: [
          RecentlyDeletedItem(
            entryId: '12345678-1234-1234-1234-123456789012',
            deletedAt: DateTime.utc(2026, 7, 1),
            purgeAt: DateTime.utc(2026, 7, 31),
          ),
        ],
      ),
    );
  }

  int purgeCalls = 0;

  @override
  Future<void> purge(String entryId) async {
    purgeCalls += 1;
  }
}

void main() {
  testWidgets('permanent purge requires explicit confirmation', (tester) async {
    final cubit = _PageCubit();
    final auth = _Auth();
    when(() => auth.state).thenReturn(
      const AuthAuthenticated(
        userId: 'user',
        isOnboarded: true,
        isVaultLocked: false,
      ),
    );
    when(() => auth.stream).thenAnswer((_) => const Stream<AuthState>.empty());

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>.value(value: auth),
          BlocProvider<RecentlyDeletedCubit>.value(value: cubit),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RecentlyDeletedPage(vaultId: 'vault'),
        ),
      ),
    );

    await tester.tap(find.text('Delete permanently').last);
    await tester.pumpAndSettle();
    expect(cubit.purgeCalls, 0);
    expect(find.text('Delete permanently?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(cubit.purgeCalls, 0);

    await tester.tap(find.text('Delete permanently').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete permanently').last);
    await tester.pumpAndSettle();
    expect(cubit.purgeCalls, 1);

    await cubit.close();
  });
}
