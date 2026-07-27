import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_creation_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_entity.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/create_vault_cubit.dart';

class _MockCreator extends Mock implements VaultCreator {}

void main() {
  late _MockCreator creator;
  final privateKey = Uint8List(32);
  final vault = VaultEntity(
    id: 'v1',
    name: 'Work',
    grantMode: GrantMode.granular,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    entryCount: 0,
    activeGrantCount: 0,
    memberCount: 1,
  );

  setUpAll(() => registerFallbackValue(Uint8List(0)));

  setUp(() => creator = _MockCreator());

  blocTest<CreateVaultCubit, CreateVaultState>(
    'submits trimmed metadata only to the encrypted creator',
    build: () {
      when(
        () => creator.create(
          name: 'Work',
          description: 'Team',
          icon: 'shield',
          color: '#123456',
          memberPrivateKey: privateKey,
        ),
      ).thenAnswer((_) async => vault);
      return CreateVaultCubit(creationService: creator);
    },
    act: (cubit) => cubit.createVault(
      name: ' Work ',
      description: ' Team ',
      icon: 'shield',
      color: '#123456',
      grantMode: GrantMode.granular,
      privateKey: privateKey,
    ),
    expect: () => [isA<CreateVaultLoading>(), isA<CreateVaultSuccess>()],
  );

  blocTest<CreateVaultCubit, CreateVaultState>(
    'rejects missing unlocked key before crypto or network work',
    build: () => CreateVaultCubit(creationService: creator),
    act: (cubit) => cubit.createVault(
      name: 'Work',
      grantMode: GrantMode.granular,
      privateKey: Uint8List(0),
    ),
    expect: () => [isA<CreateVaultError>()],
    verify: (_) => verifyNever(
      () => creator.create(
        name: any(named: 'name'),
        description: any(named: 'description'),
        icon: any(named: 'icon'),
        color: any(named: 'color'),
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    ),
  );
}
