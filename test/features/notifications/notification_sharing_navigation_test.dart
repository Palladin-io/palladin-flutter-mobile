import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/core/crypto/vault_session_store.dart';
import 'package:mobile_palladin/core/di/injection.dart';
import 'package:mobile_palladin/core/storage/secure_token_storage.dart';
import 'package:mobile_palladin/features/agents/presentation/bloc/agents_cubit.dart';
import 'package:mobile_palladin/features/approval/presentation/cubit/pending_grants_cubit.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mobile_palladin/features/notifications/domain/entities/inbox_notification.dart';
import 'package:mobile_palladin/features/notifications/data/services/notification_sharing_entry_resolver.dart';
import 'package:mobile_palladin/features/notifications/domain/repositories/notification_center_repository.dart';
import 'package:mobile_palladin/features/notifications/presentation/cubit/notification_center_cubit.dart';
import 'package:mobile_palladin/features/notifications/presentation/pages/notification_center_page.dart';
import 'package:mobile_palladin/features/shell/presentation/pages/app_shell.dart';
import 'package:mobile_palladin/features/vault/data/datasources/entry_sharing_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_entry_list_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_session_authority_provider.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_share_list.dart';
import 'package:mobile_palladin/features/vault/domain/entities/member_index_entry.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_entity.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/edit_entry_cubit.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/entry_history_cubit.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/vault_list_cubit.dart';
import 'package:mobile_palladin/features/vault/presentation/pages/entry_detail_page.dart';
import 'package:mobile_palladin/features/vault/presentation/pages/entry_sharing_tab.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

class _Auth extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

class _Vaults extends MockCubit<VaultListState> implements VaultListCubit {}

class _Agents extends MockCubit<AgentsState> implements AgentsCubit {}

class _Pending extends MockCubit<PendingGrantsState>
    implements PendingGrantsCubit {}

class _History extends MockCubit<EntryHistoryState>
    implements EntryHistoryCubit {}

class _InboxRepository extends Mock implements NotificationCenterRepository {}

class _Index extends Mock implements MemberEntryListLoader {}

class _Authority extends Mock implements MemberSyncSessionAuthorityProvider {}

class _Tokens extends Mock implements SecureTokenStorage {}

class _Sharing extends Mock implements EntrySharingRemoteDatasource {}

void main() {
  setUpAll(() => registerFallbackValue(CancelToken()));
  late _Auth auth;
  late AuthAuthenticated owner;
  late AuthState authState;
  late VaultListState vaultState;
  late NotificationCenterCubit inbox;
  late _Index index;
  late _Sharing sharing;
  late VaultSessionStore keys;
  Future<List<MemberIndexEntry>> load() =>
      index.load(vaultId: 'vault', memberPrivateKey: owner.privateKey!);
  final entry = MemberIndexEntry(
    entryId: 'entry',
    entryType: 1,
    memberLabel: 'Local entry',
    searchFields: const [],
    revision: '7',
    currentKeyVersion: 3,
    state: MemberEntryState.active,
  );
  setUp(() {
    owner = AuthAuthenticated(
      userId: 'account',
      isOnboarded: true,
      isVaultLocked: false,
      privateKey: Uint8List(32),
      permissions: 8,
    );
    authState = owner;
    auth = _Auth();
    when(() => auth.state).thenAnswer((_) => authState);
    vaultState = VaultListLoaded([
      VaultEntity(
        id: 'vault',
        name: 'Local vault',
        grantMode: GrantMode.granular,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        entryCount: 1,
        activeGrantCount: 0,
        memberCount: 1,
      ),
    ]);
    final vaults = _Vaults();
    when(() => vaults.state).thenAnswer((_) => vaultState);
    final agents = _Agents();
    when(() => agents.state).thenReturn(const AgentsState());
    final pending = _Pending();
    when(() => pending.state).thenReturn(const PendingGrantsState());
    final repository = _InboxRepository();
    when(() => repository.list()).thenAnswer(
      (_) async => NotificationPage(
        items: [
          InboxNotification(
            id: 'receipt',
            type: 'entry_share_received',
            category: NotificationCategory.update,
            titleKey: '',
            metadata: const {
              'vaultId': 'vault',
              'entryId': 'entry',
              'shareId': 'share',
              'actionDeepLink': '/agents/forged',
            },
            actionState: NotificationActionState.none,
            occurredAt: DateTime(2026),
            readAt: DateTime(2026),
          ),
        ],
      ),
    );
    when(() => repository.summary()).thenAnswer(
      (_) async =>
          const NotificationSummary(unreadCount: 0, pendingActionCount: 0),
    );
    inbox = NotificationCenterCubit(repository: repository);
    index = _Index();
    when(load).thenAnswer((_) async => [entry]);
    final authority = _Authority();
    when(authority.current).thenAnswer(
      (_) async => const MemberSyncSessionAuthority(
        principalId: 'account',
        organizationId: 'org',
        organizationMembershipGeneration: '1',
        offlinePolicy: 'disabled',
        offlinePolicyVersion: 1,
      ),
    );
    final tokens = _Tokens();
    when(() => tokens.accessToken).thenAnswer(
      (_) async =>
          'header.${base64Url.encode(utf8.encode(jsonEncode({'sub': 'account', 'org_id': 'org'})))}.signature',
    );
    sharing = _Sharing();
    when(
      () => sharing.list(
        any(),
        any(),
        cursor: any(named: 'cursor'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer(
      (_) async => EntrySharesPage(items: const [], nextCursor: null),
    );
    keys = VaultSessionStore();
    getIt.registerSingleton<VaultListCubit>(vaults);
    getIt.registerSingleton<AgentsCubit>(agents);
    getIt.registerSingleton<PendingGrantsCubit>(pending);
    getIt.registerSingleton<NotificationCenterCubit>(inbox);
    getIt.registerSingleton<NotificationSharingEntryResolver>(
      NotificationSharingEntryResolver(
        entries: index,
        readAuthority: authority.current,
      ),
    );
    getIt.registerSingleton<MemberSyncSessionAuthorityProvider>(authority);
    getIt.registerSingleton<SecureTokenStorage>(tokens);
    getIt.registerSingleton<VaultSessionStore>(keys);
    getIt.registerSingleton<EntrySharingRemoteDatasource>(sharing);
    getIt.registerFactory<EditEntryCubit>(
      () => throw StateError('Unrequested secret detail'),
    );
    getIt.registerFactory<EntryHistoryCubit>(() {
      final history = _History();
      when(() => history.state).thenReturn(const EntryHistoryState());
      return history;
    });
  });
  tearDown(() async {
    await inbox.close();
    await auth.close();
    await getIt.reset();
  });

  Future<void> pump(WidgetTester tester, String locale) async {
    await tester.pumpWidget(
      BlocProvider<AuthBloc>.value(
        value: auth,
        child: MaterialApp(
          locale: Locale(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => AppShellScope(
            openSettingsDrawer: () {},
            setBottomNavHidden: (_) {},
            setFab: (_, _) {},
            clearFab: (_) {},
            child: child!,
          ),
          home: const NotificationCenterPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  for (final locale in ['en', 'pl']) {
    testWidgets('receipt CTA opens exact Entry Sharing tab in $locale', (
      tester,
    ) async {
      await pump(tester, locale);
      final l10n = lookupAppLocalizations(Locale(locale));
      await tester.tap(find.text(l10n.inboxViewSharing));
      await tester.pumpAndSettle();
      final detail = tester.widget<EntryDetailPage>(
        find.byType(EntryDetailPage),
      );
      expect(detail.entry.id, 'entry');
      expect(detail.entry.vaultId, 'vault');
      expect(detail.entry.label, 'Local entry');
      expect(detail.entry.currentRevision, '7');
      expect(detail.showSharing, true);
      expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 4);
      expect(find.byType(EntrySharingTab), findsOneWidget);
      verify(
        () => sharing.list(
          'vault',
          'entry',
          cursor: null,
          cancelToken: any(named: 'cancelToken'),
        ),
      ).called(1);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });
  }
  for (final condition in ['missing', 'permission', 'vault']) {
    testWidgets('$condition destination shows unavailable without navigation', (
      tester,
    ) async {
      await pump(tester, 'en');
      if (condition == 'missing') {
        when(load).thenAnswer((_) async => []);
      }
      if (condition == 'permission') authState = owner.copyWith(permissions: 0);
      if (condition == 'vault') vaultState = const VaultListLoaded([]);
      await tester.tap(find.text('View sharing'));
      await tester.pumpAndSettle();
      expect(find.byType(EntryDetailPage), findsNothing);
      expect(
        find.text(
          lookupAppLocalizations(const Locale('en')).inboxSharingUnavailable,
        ),
        findsOneWidget,
      );
      verifyNever(
        () => sharing.list(
          any(),
          any(),
          cursor: any(named: 'cursor'),
          cancelToken: any(named: 'cancelToken'),
        ),
      );
      await unmount(tester);
    });
  }
  for (final boundary in [
    'lock',
    'account',
    'inbox',
    'vault',
    'keys',
    'background',
    'route',
    'dispose',
  ]) {
    testWidgets('pending local navigation cannot survive $boundary', (
      tester,
    ) async {
      await pump(tester, 'en');
      final pending = Completer<void>();
      when(load).thenAnswer((_) async {
        await pending.future;
        return [entry];
      });
      await tester.tap(find.text('View sharing'));
      await tester.pump();
      switch (boundary) {
        case 'lock':
          authState = owner.copyWith(isVaultLocked: true, clearKeys: true);
        case 'account':
          authState = owner.copyWith(userId: 'other');
        case 'inbox':
          inbox.lock();
        case 'vault':
          vaultState = const VaultListLoaded([]);
        case 'keys':
          keys.clear();
        case 'background':
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
        case 'route':
          unawaited(
            Navigator.of(
              tester.element(find.byType(NotificationCenterPage)),
            ).push(MaterialPageRoute<void>(builder: (_) => const Scaffold())),
          );
          await tester.pump();
        case 'dispose':
          await unmount(tester);
      }
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.byType(EntryDetailPage), findsNothing);
      verifyNever(
        () => sharing.list(
          any(),
          any(),
          cursor: any(named: 'cursor'),
          cancelToken: any(named: 'cancelToken'),
        ),
      );
      expect(tester.takeException(), isNull);
      await unmount(tester);
      if (boundary == 'background') {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
      }
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
  }
}
