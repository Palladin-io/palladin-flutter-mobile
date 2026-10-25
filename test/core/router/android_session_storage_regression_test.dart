import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/config/env_config.dart';
import 'package:mobile_palladin/core/crypto/vault_session_store.dart';
import 'package:mobile_palladin/core/di/injection.dart';
import 'package:mobile_palladin/core/router/app_router.dart';
import 'package:mobile_palladin/core/storage/biometric_storage_key_store.dart';
import 'package:mobile_palladin/core/storage/secure_token_storage.dart';
import 'package:mobile_palladin/features/auth/data/datasources/auth_remote_datasource.dart';
import 'package:mobile_palladin/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mobile_palladin/features/autofill/domain/autofill_cache_invalidator.dart';

import '../../helpers/android_contract_storage.dart';

class _AutoFillInvalidator extends Mock implements AutoFillCacheInvalidator {}

void main() {
  testWidgets(
    'Android biometric marker checks keep an unlocked account authenticated on recheck',
    (tester) async {
      await getIt.reset();
      configureDependencies(EnvConfig.local());
      addTearDown(getIt.reset);
      final storage = AndroidContractStorage(
        getIt<FlutterSecureStorage>().aOptions,
      );
      final tokens = SecureTokenStorage(storage);
      final claims = base64Url.encode(
        utf8.encode(jsonEncode({'email_verified': true, 'permissions': 0})),
      );
      final accessToken = 'fixture.$claims.signature';
      await tokens.saveTokens(
        accessToken: accessToken,
        refreshToken: 'fixture-refresh',
        userId: 'fixture-account',
        isOnboarded: true,
      );
      await tokens.setAuthProvider('password');
      final biometrics = BiometricStorageKeyStore(markerStorage: storage);
      final dio = Dio();
      addTearDown(dio.close);
      final keys = VaultSessionStore();
      addTearDown(keys.clear);
      final auth = AuthBloc(
        authRepository: AuthRepositoryImpl(
          remoteDatasource: AuthRemoteDatasource(dio),
          tokenStorage: tokens,
          biometricKeyStore: biometrics,
          autoFillCacheInvalidator: _AutoFillInvalidator(),
          googleServerClientId: '',
        ),
        vaultSessionStore: keys,
      );
      addTearDown(auth.close);
      final router = createRouter(auth);
      addTearDown(router.dispose);
      late BuildContext routeContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              routeContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      // Resolve the actual app route contract without constructing unrelated
      // Dashboard data sources; AuthBloc and the session repository stay real.
      Future<String> destination() async {
        router.go('/');
        final matches = await router.routeInformationParser
            .parseRouteInformationWithDependencies(
              router.routeInformationProvider.value,
              routeContext,
            );
        return matches.uri.path;
      }

      var nextState = auth.stream.first;
      auth.add(const AuthCheckRequested());
      expect(await nextState, isA<AuthAuthenticated>());
      expect(await destination(), '/unlock');

      final masterKey = Uint8List(32)..fillRange(0, 32, 1);
      final privateKey = Uint8List(32)..fillRange(0, 32, 2);
      addTearDown(() {
        masterKey.fillRange(0, masterKey.length, 0);
        privateKey.fillRange(0, privateKey.length, 0);
      });
      nextState = auth.stream.first;
      auth.add(VaultUnlocked(masterKey: masterKey, privateKey: privateKey));
      await nextState;
      expect(await destination(), '/');

      await biometrics.isEnrolled();
      await biometrics.purgeLegacyRawKey();
      nextState = auth.stream.first;
      auth.add(const AuthCheckRequested());
      await nextState;

      // An auth recheck may lock the Vault again; it must not lose the account
      // merely because a biometric marker migrated the native storage file.
      expect(await destination(), '/unlock');
      final restored = auth.state as AuthAuthenticated;
      expect(restored.userId, 'fixture-account');
      expect(restored.isOnboarded, isTrue);
      expect(restored.authProvider, 'password');
      expect(await tokens.accessToken, accessToken);
      expect(await tokens.refreshToken, 'fixture-refresh');
    },
  );
}
