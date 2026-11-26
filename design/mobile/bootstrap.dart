import 'dart:typed_data';
import 'activity_adapters.dart';
import 'vault_adapters.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';
import 'package:mobile_palladin/features/vault/domain/entities/member_index_entry.dart';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_palladin/core/storage/biometric_key_store.dart';
import 'package:mobile_palladin/config/env_config.dart';
import 'package:mobile_palladin/core/analytics/analytics_service.dart';
import 'package:mobile_palladin/core/di/injection.dart';
import 'package:mobile_palladin/core/storage/user_preferences.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mobile_palladin/features/auth/presentation/cubit/login_cubit.dart';
import 'package:mobile_palladin/features/unlock/presentation/cubit/unlock_cubit.dart';
import 'package:mobile_palladin/features/dashboard/presentation/cubit/dashboard_cubit.dart';
import 'package:mobile_palladin/features/dashboard/presentation/cubit/search_cubit.dart';
import 'package:mobile_palladin/features/dashboard/presentation/cubit/search_state.dart';
import 'package:mobile_palladin/features/dashboard/domain/entities/search_result_entity.dart';

// Only the standalone design entry point imports these adapters.
Future<void> registerPreviewBootstrap() async {
  // Standalone fixture storage must never read the owner’s native preferences.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  // ignore: invalid_use_of_visible_for_testing_member
  FlutterSecureStorage.setMockInitialValues({});
  configureDependencies(PreviewEnvironment());
  await getIt.unregister<BiometricKeyStore>();
  getIt.registerSingleton<BiometricKeyStore>(PreviewBiometrics());
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (request, handler) {
        handler.reject(
          DioException(
            requestOptions: request,
            error: StateError(
              'Unimplemented preview request: ${request.method} ${request.path}',
            ),
          ),
        );
      },
    ),
  );
  await getIt.unregister<Dio>();
  getIt.registerSingleton<Dio>(dio);
  await getIt.unregister<AuthBloc>();
  getIt.registerSingleton<AuthBloc>(PreviewAuth());
  await getIt.unregister<LoginCubit>();
  getIt.registerFactory<LoginCubit>(PreviewLogin.new);
  await getIt.unregister<UnlockCubit>();
  getIt.registerFactory<UnlockCubit>(PreviewUnlock.new);
  await getIt.unregister<DashboardCubit>();
  getIt.registerSingleton<DashboardCubit>(PreviewDashboard());
  await getIt.unregister<SearchCubit>();
  getIt.registerFactory<SearchCubit>(PreviewSearch.new);
  AnalyticsService.instance.reset();
}

class PreviewPreferences implements UserPreferences {
  bool entries = true;
  ThemeMode theme = Uri.base.queryParameters['theme'] == 'light'
      ? ThemeMode.light
      : ThemeMode.dark;
  Locale language = const Locale('en');
  @override
  Future<bool> get libraryEntries async => entries;
  @override
  Future<ThemeMode> get themeMode async => theme;
  @override
  Future<Locale> get locale async => language;
  @override
  Future<void> saveLibraryEntries(bool value) async {
    entries = value;
  }

  @override
  Future<void> saveThemeMode(ThemeMode value) async {
    theme = value;
  }

  @override
  Future<void> saveLocale(Locale value) async {
    language = value;
  }
}

AuthAuthenticated demoSession({bool locked = false}) => AuthAuthenticated(
  userId: 'demo-user',
  email: 'alex@example.com',
  isOnboarded: true,
  isVaultLocked: locked,
  permissions: 0x7fffffff,
  authProvider: 'password',
  masterKey: locked ? null : Uint8List(32),
  privateKey: locked ? null : Uint8List(32),
);

class PreviewAuth extends Bloc<AuthEvent, AuthState> implements AuthBloc {
  PreviewAuth()
    : super(
        Uri.base.queryParameters['screen'] == 'login'
            ? const AuthUnauthenticated()
            : demoSession(
                locked: Uri.base.queryParameters['screen'] == 'unlock',
              ),
      ) {
    on<AuthEvent>((event, emit) {
      if (event is AuthLogoutRequested) {
        emit(const AuthUnauthenticated());
      } else if (event is VaultLockRequested) {
        emit(demoSession(locked: true));
      } else if (event is VaultUnlocked ||
          event is PasswordSessionEstablished ||
          event is AuthLoginWithGoogle) {
        emit(demoSession());
      } else {
        throw UnsupportedError('Preview auth event: ${event.runtimeType}');
      }
    });
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class PreviewLogin extends Cubit<LoginState> implements LoginCubit {
  PreviewLogin() : super(const LoginInitial());
  @override
  Future<void> login({required String email, required String password}) async {
    if (email.trim().isEmpty || password.isEmpty) return;
    emit(LoginSuccess(masterKey: Uint8List(32), privateKey: Uint8List(32)));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class PreviewUnlock extends Cubit<UnlockState> implements UnlockCubit {
  PreviewUnlock() : super(const UnlockInitial());
  @override
  Future<bool> isBiometricAvailable() async => false;
  @override
  Future<void> unlock(String password, {String? defaultVaultName}) async {
    if (password.isEmpty) return;
    emit(UnlockSuccess(masterKey: Uint8List(32), privateKey: Uint8List(32)));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<RecentEntryEntity> get previewRecentEntries => vaultPreview.records.values
    .where((entry) => entry.lifecycleState == MemberEntryState.active)
    .map(
      (entry) => RecentEntryEntity(
        id: entry.id,
        label: entry.label,
        icon: entry.icon,
        vaultId: entry.vaultId,
        vaultName: vaultPreview.vaults[entry.vaultId]?.name ?? '',
        typeWire: entry.type.toWire(),
        currentRevision: entry.currentRevision,
        currentKeyVersion: entry.currentKeyVersion,
        createdAt: entry.createdAt,
        updatedAt: entry.updatedAt,
      ),
    )
    .toList();

class PreviewDashboard extends Cubit<DashboardState> implements DashboardCubit {
  PreviewDashboard()
    : super(
        DashboardLoaded(
          recentEntries: previewRecentEntries,
          recentActivity: activityPreview.logs.take(6).toList(),
        ),
      );
  @override
  Future<void> load({bool canViewAudit = false, String? userId}) async {
    emit(
      DashboardLoaded(
        recentEntries: previewRecentEntries,
        recentActivity: activityPreview.logs.take(6).toList(),
      ),
    );
  }

  @override
  void lock() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class PreviewSearch extends Cubit<SearchState> implements SearchCubit {
  PreviewSearch() : super(const SearchIdle());
  @override
  void prepare(Uint8List key, {required String principalId}) {}
  @override
  void query(String query) {
    if (query.isEmpty) {
      emit(const SearchIdle());
      return;
    }
    final List<SearchResultEntity> results = previewRecentEntries
        .where(
          (entry) => entry.label.toLowerCase().contains(query.toLowerCase()),
        )
        .map<SearchResultEntity>(
          (entry) => EntrySearchResult(
            vaultId: entry.vaultId,
            entryId: entry.id,
            displayName: entry.label,
            iconReference: entry.icon,
            vaultName: entry.vaultName,
            entryType: entry.typeWire,
            currentRevision: entry.currentRevision,
            currentKeyVersion: entry.currentKeyVersion,
          ),
        )
        .toList();
    final normalized = query.toLowerCase();
    results.addAll(
      vaultPreview.vaults.values
          .where((vault) => vault.name.toLowerCase().contains(normalized))
          .map(
            (vault) =>
                VaultSearchResult(vaultId: vault.id, displayName: vault.name),
          ),
    );
    results.addAll(
      activityPreview.agents
          .where(
            (agent) => (agent.name ?? agent.agentId).toLowerCase().contains(
              normalized,
            ),
          )
          .map(
            (agent) => AgentSearchResult(
              agentId: agent.agentId,
              displayName: agent.name ?? agent.agentId,
            ),
          ),
    );
    emit(results.isEmpty ? const SearchEmpty() : SearchResults(results));
  }

  @override
  void selectResult(SearchResultEntity result) {}

  @override
  void reset() => emit(const SearchIdle());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class PreviewEnvironment implements EnvConfig {
  @override
  AppFlavor get flavor => AppFlavor.local;
  @override
  String get appName => 'Palladin · Design';
  @override
  String get apiBaseUrl => Uri.base.origin;
  @override
  String get sharingWebOrigin => Uri.base.origin;
  @override
  String get posthogKey => '';
  @override
  String get posthogHost => '';
  @override
  String get googleServerClientId => '';
  @override
  bool get usesStagingBackend => false;
  @override
  bool get clientAnalyticsReleased => false;
  @override
  List<String> get certificatePins => const [];
  @override
  bool get isLocal => true;
  @override
  bool get isStaging => false;
  @override
  bool get isProduction => false;
}

class PreviewBiometrics implements BiometricKeyStore {
  @override
  int get generation => 0;
  @override
  Future<bool> canStore() async => false;
  @override
  Future<bool> isEnrolled() async => false;
  @override
  Future<void> enroll(
    Uint8List key,
    BiometricPromptCopy copy, {
    required int expectedGeneration,
  }) async => throw const BiometricAuthException(
    BiometricAuthFailureReason.unavailable,
  );
  @override
  Future<Uint8List?> unlockKey(BiometricPromptCopy copy) async => null;
  @override
  Future<void> clear() async {}
  @override
  Future<void> purgeLegacyRawKey() async {}
}
