import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/core/storage/user_preferences.dart';
import 'package:mobile_palladin/features/shell/presentation/cubit/library_view_cubit.dart';

class _Preferences extends Mock implements UserPreferences {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'defaults to Entries and restores either choice after recreation',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      const storage = FlutterSecureStorage();
      var cubit = LibraryViewCubit(const UserPreferences(storage));
      await cubit.ready;
      expect(cubit.route, '/entries');
      for (final entries in [false, true]) {
        await cubit.select(entries);
        await cubit.close();
        cubit = LibraryViewCubit(const UserPreferences(storage));
        await cubit.ready;
        expect(cubit.route, entries ? '/entries' : '/vaults');
      }
      expect(await storage.readAll(), {'ui_library_view': 'entries'});
      await cubit.close();
    },
  );

  test(
    'late restore cannot overwrite a newer choice; writes are ordered',
    () async {
      final preferences = _Preferences();
      final restore = Completer<bool>();
      final firstWrite = Completer<void>();
      when(() => preferences.libraryEntries).thenAnswer((_) => restore.future);
      when(
        () => preferences.saveLibraryEntries(false),
      ).thenAnswer((_) => firstWrite.future);
      when(() => preferences.saveLibraryEntries(true)).thenAnswer((_) async {});
      final cubit = LibraryViewCubit(preferences);
      final first = cubit.select(false);
      final last = cubit.select(true);
      restore.complete(false);
      await cubit.ready;
      expect(cubit.route, '/entries');
      verifyNever(() => preferences.saveLibraryEntries(true));
      firstWrite.complete();
      await Future.wait([first, last]);
      verifyInOrder([
        () => preferences.saveLibraryEntries(false),
        () => preferences.saveLibraryEntries(true),
      ]);
      await cubit.close();
    },
  );

  test('storage failure leaves navigation usable', () async {
    final preferences = _Preferences();
    when(
      () => preferences.libraryEntries,
    ).thenAnswer((_) async => throw Exception());
    when(
      () => preferences.saveLibraryEntries(false),
    ).thenAnswer((_) async => throw Exception());
    final cubit = LibraryViewCubit(preferences);
    await cubit.ready;
    expect(cubit.route, '/entries');
    await cubit.select(false);
    expect(cubit.route, '/vaults');
    await cubit.close();
  });
}
