import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_palladin/features/api_keys/presentation/bloc/api_keys_cubit.dart';
import 'package:mobile_palladin/features/settings/domain/entities/api_key.dart';
import 'package:mobile_palladin/features/settings/domain/exceptions/settings_exceptions.dart';
import 'package:mobile_palladin/features/settings/domain/repositories/settings_repository.dart';

class _MockSettingsRepository extends Mock implements SettingsRepository {}

void main() {
  late _MockSettingsRepository repository;

  final sampleKeys = <ApiKey>[
    ApiKey(
      apiKeyId: 'k1',
      name: 'Prod',
      keySuffix: 'aB3x',
      status: ApiKeyStatus.active,
      createdAt: DateTime.utc(2026, 5, 1),
    ),
  ];

  setUp(() {
    repository = _MockSettingsRepository();
  });

  ApiKeysCubit buildCubit() => ApiKeysCubit(repository: repository);

  group('ApiKeysCubit.load', () {
    blocTest<ApiKeysCubit, ApiKeysState>(
      'emits loading then loaded with keys',
      build: () {
        when(() => repository.listApiKeys())
            .thenAnswer((_) async => sampleKeys);
        return buildCubit();
      },
      act: (cubit) => cubit.load(),
      expect: () => [
        isA<ApiKeysState>()
            .having((s) => s.status, 'status', ApiKeysStatus.loading),
        isA<ApiKeysState>()
            .having((s) => s.status, 'status', ApiKeysStatus.loaded)
            .having((s) => s.apiKeys.length, 'apiKeys.length', 1),
      ],
    );

    blocTest<ApiKeysCubit, ApiKeysState>(
      'emits error on network failure',
      build: () {
        when(() => repository.listApiKeys()).thenThrow(
          const SettingsException(SettingsErrorKind.networkError),
        );
        return buildCubit();
      },
      act: (cubit) => cubit.load(),
      expect: () => [
        isA<ApiKeysState>()
            .having((s) => s.status, 'status', ApiKeysStatus.loading),
        isA<ApiKeysState>()
            .having((s) => s.status, 'status', ApiKeysStatus.error)
            .having(
              (s) => s.error,
              'error',
              SettingsErrorKind.networkError,
            ),
      ],
    );
  });

  group('ApiKeysState.keyById', () {
    test('resolves a key present in the list', () {
      final state = ApiKeysState(
        status: ApiKeysStatus.loaded,
        apiKeys: sampleKeys,
      );
      expect(state.keyById('k1')?.name, 'Prod');
    });

    test('returns null for an unknown id', () {
      final state = ApiKeysState(
        status: ApiKeysStatus.loaded,
        apiKeys: sampleKeys,
      );
      expect(state.keyById('missing'), isNull);
    });
  });

  group('ApiKeysCubit.createApiKey', () {
    test('returns the one-time plaintext and refreshes the list', () async {
      when(() => repository.createApiKey(any()))
          .thenAnswer((_) async => _newKeyFixture());
      when(() => repository.listApiKeys())
          .thenAnswer((_) async => sampleKeys);

      final cubit = buildCubit();
      final created = await cubit.createApiKey('  New  ');

      expect(created.plaintext, 'cv_secret');
      // Name must be trimmed before hitting the API.
      verify(() => repository.createApiKey('New')).called(1);
      verify(() => repository.listApiKeys()).called(1);
      // SECURITY: the plaintext must never be persisted on cubit state.
      expect(cubit.state.apiKeys.any((k) => k.name == 'cv_secret'), isFalse);
      await cubit.close();
    });

    test('propagates SettingsException to the caller', () async {
      when(() => repository.createApiKey(any())).thenThrow(
        const SettingsException(SettingsErrorKind.validation),
      );
      final cubit = buildCubit();
      await expectLater(
        cubit.createApiKey('x'),
        throwsA(isA<SettingsException>()),
      );
      await cubit.close();
    });
  });

  group('ApiKeysCubit.revokeApiKey', () {
    blocTest<ApiKeysCubit, ApiKeysState>(
      'revokes then refreshes the list',
      build: () {
        when(() => repository.revokeApiKey(any())).thenAnswer((_) async {});
        when(() => repository.listApiKeys())
            .thenAnswer((_) async => const <ApiKey>[]);
        return buildCubit();
      },
      act: (cubit) => cubit.revokeApiKey('k1'),
      expect: () => [
        isA<ApiKeysState>()
            .having((s) => s.revokingKeyId, 'revokingKeyId', 'k1'),
        isA<ApiKeysState>()
            .having((s) => s.status, 'status', ApiKeysStatus.loaded)
            .having((s) => s.revokingKeyId, 'revokingKeyId', isNull)
            .having((s) => s.apiKeys, 'apiKeys', isEmpty),
      ],
      verify: (_) {
        verify(() => repository.revokeApiKey('k1')).called(1);
        verify(() => repository.listApiKeys()).called(1);
      },
    );

    blocTest<ApiKeysCubit, ApiKeysState>(
      'surfaces a transient mutationError without flipping status on failure',
      build: () {
        when(() => repository.revokeApiKey(any())).thenThrow(
          const SettingsException(SettingsErrorKind.notFound),
        );
        return buildCubit();
      },
      act: (cubit) => cubit.revokeApiKey('k1'),
      expect: () => [
        isA<ApiKeysState>()
            .having((s) => s.revokingKeyId, 'revokingKeyId', 'k1'),
        // A failed mutation must keep status untouched (so the card
        // stays visible) and only set the transient mutationError.
        isA<ApiKeysState>()
            .having((s) => s.status, 'status', ApiKeysStatus.initial)
            .having((s) => s.error, 'error', isNull)
            .having(
              (s) => s.mutationError,
              'mutationError',
              SettingsErrorKind.notFound,
            )
            .having((s) => s.revokingKeyId, 'revokingKeyId', isNull),
      ],
      verify: (_) {
        verifyNever(() => repository.listApiKeys());
      },
    );
  });

  group('ApiKeysCubit.activateApiKey', () {
    blocTest<ApiKeysCubit, ApiKeysState>(
      'activates then refreshes the list',
      build: () {
        when(() => repository.activateApiKey(any())).thenAnswer((_) async {});
        when(() => repository.listApiKeys())
            .thenAnswer((_) async => sampleKeys);
        return buildCubit();
      },
      act: (cubit) => cubit.activateApiKey('k1'),
      expect: () => [
        isA<ApiKeysState>()
            .having((s) => s.activatingKeyId, 'activatingKeyId', 'k1'),
        isA<ApiKeysState>()
            .having((s) => s.status, 'status', ApiKeysStatus.loaded)
            .having((s) => s.activatingKeyId, 'activatingKeyId', isNull)
            .having((s) => s.apiKeys.length, 'apiKeys.length', 1),
      ],
      verify: (_) {
        verify(() => repository.activateApiKey('k1')).called(1);
        verify(() => repository.listApiKeys()).called(1);
      },
    );

    blocTest<ApiKeysCubit, ApiKeysState>(
      'surfaces a transient mutationError on failure',
      build: () {
        when(() => repository.activateApiKey(any())).thenThrow(
          const SettingsException(SettingsErrorKind.networkError),
        );
        return buildCubit();
      },
      act: (cubit) => cubit.activateApiKey('k1'),
      expect: () => [
        isA<ApiKeysState>()
            .having((s) => s.activatingKeyId, 'activatingKeyId', 'k1'),
        isA<ApiKeysState>()
            .having((s) => s.status, 'status', ApiKeysStatus.initial)
            .having(
              (s) => s.mutationError,
              'mutationError',
              SettingsErrorKind.networkError,
            )
            .having((s) => s.activatingKeyId, 'activatingKeyId', isNull),
      ],
      verify: (_) {
        verifyNever(() => repository.listApiKeys());
      },
    );
  });

  group('ApiKeysCubit.deleteApiKey', () {
    blocTest<ApiKeysCubit, ApiKeysState>(
      'deletes then refreshes the list',
      build: () {
        when(() => repository.deleteApiKey(any())).thenAnswer((_) async {});
        when(() => repository.listApiKeys())
            .thenAnswer((_) async => const <ApiKey>[]);
        return buildCubit();
      },
      act: (cubit) => cubit.deleteApiKey('k1'),
      expect: () => [
        isA<ApiKeysState>()
            .having((s) => s.deletingKeyId, 'deletingKeyId', 'k1'),
        isA<ApiKeysState>()
            .having((s) => s.status, 'status', ApiKeysStatus.loaded)
            .having((s) => s.deletingKeyId, 'deletingKeyId', isNull)
            .having((s) => s.apiKeys, 'apiKeys', isEmpty),
      ],
      verify: (_) {
        verify(() => repository.deleteApiKey('k1')).called(1);
        verify(() => repository.listApiKeys()).called(1);
      },
    );

    blocTest<ApiKeysCubit, ApiKeysState>(
      'surfaces a transient mutationError on failure',
      build: () {
        when(() => repository.deleteApiKey(any())).thenThrow(
          const SettingsException(SettingsErrorKind.notFound),
        );
        return buildCubit();
      },
      act: (cubit) => cubit.deleteApiKey('k1'),
      expect: () => [
        isA<ApiKeysState>()
            .having((s) => s.deletingKeyId, 'deletingKeyId', 'k1'),
        isA<ApiKeysState>()
            .having((s) => s.status, 'status', ApiKeysStatus.initial)
            .having(
              (s) => s.mutationError,
              'mutationError',
              SettingsErrorKind.notFound,
            )
            .having((s) => s.deletingKeyId, 'deletingKeyId', isNull),
      ],
      verify: (_) {
        verifyNever(() => repository.listApiKeys());
      },
    );

    blocTest<ApiKeysCubit, ApiKeysState>(
      'acknowledgeMutationError clears the transient error',
      build: () {
        when(() => repository.deleteApiKey(any())).thenThrow(
          const SettingsException(SettingsErrorKind.notFound),
        );
        return buildCubit();
      },
      act: (cubit) async {
        await cubit.deleteApiKey('k1');
        cubit.acknowledgeMutationError();
      },
      skip: 2,
      expect: () => [
        isA<ApiKeysState>()
            .having((s) => s.mutationError, 'mutationError', isNull),
      ],
    );
  });
}

NewApiKey _newKeyFixture() => NewApiKey(
      apiKeyId: 'k9',
      name: 'New',
      plaintext: 'cv_secret',
      createdAt: DateTime.utc(2026, 5, 17),
    );
