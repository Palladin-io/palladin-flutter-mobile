import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/shell/presentation/pages/fab_ownership_stack.dart';

/// Marker widgets standing in for real FABs, so `current` comparisons are
/// by identity and read clearly in failure messages.
const _vaultFab = SizedBox(key: ValueKey('vault'));
const _apiKeysFab = SizedBox(key: ValueKey('api-keys'));
const _entryFab = SizedBox(key: ValueKey('entry'));

void main() {
  group('FabOwnershipStack', () {
    test('starts empty with no current FAB', () {
      final stack = FabOwnershipStack();
      expect(stack.current, isNull);
      expect(stack.depth, 0);
    });

    test('first owner that registers a FAB becomes current', () {
      final stack = FabOwnershipStack();
      final vaultList = Object();

      expect(stack.set(_vaultFab, vaultList), isTrue);
      expect(stack.current, same(_vaultFab));
    });

    test('a later owner takes over the FAB (push over a covered page)', () {
      final stack = FabOwnershipStack();
      final vaultDetail = Object();
      final apiKeys = Object();

      stack.set(_vaultFab, vaultDetail);
      stack.set(_apiKeysFab, apiKeys);

      // BUG REGRESSION: API Keys (pushed over vault detail) must show its
      // own FAB, not the vault detail's "add entry".
      expect(stack.current, same(_apiKeysFab));
      expect(stack.depth, 2);
    });

    test('clearing the top owner resurfaces the covered page FAB', () {
      final stack = FabOwnershipStack();
      final apiKeysList = Object();
      final apiKeyDetail = Object();

      stack.set(_apiKeysFab, apiKeysList);
      stack.set(null, apiKeyDetail); // detail suppresses the FAB

      expect(stack.current, isNull);

      // Detail pops → its registrar clears → list's FAB is back, with no
      // re-assert from the list page.
      expect(stack.clear(apiKeyDetail), isTrue);
      expect(stack.current, same(_apiKeysFab));
    });

    test('a null registration suppresses a covered page FAB', () {
      final stack = FabOwnershipStack();
      final vaultList = Object();
      final settings = Object();

      stack.set(_vaultFab, vaultList);
      // Settings declares no FAB — pushed over the vault list it must hide
      // the list's "add vault".
      stack.set(null, settings);

      expect(stack.current, isNull);
    });

    test('re-registering the top owner with the same fab is a no-op', () {
      final stack = FabOwnershipStack();
      final owner = Object();

      expect(stack.set(_vaultFab, owner), isTrue);
      expect(stack.set(_vaultFab, owner), isFalse);
    });

    test('updating an existing owner changes its fab in place', () {
      final stack = FabOwnershipStack();
      final owner = Object();

      stack.set(_vaultFab, owner);
      expect(stack.set(_entryFab, owner), isTrue);
      expect(stack.current, same(_entryFab));
      expect(stack.depth, 1);
    });

    test(
      'a covered owner re-registering updates in place and cannot steal the top',
      () {
        final stack = FabOwnershipStack();
        final vaultDetail = Object();
        final apiKeys = Object();

        stack.set(_vaultFab, vaultDetail);
        stack.set(_apiKeysFab, apiKeys);
        expect(stack.current, same(_apiKeysFab));

        // BUG REGRESSION: while covered by API Keys, the vault detail rebuilds
        // with a new (inline) FAB and re-registers. It must NOT jump back to
        // the top — API Keys keeps showing its own FAB, and the shell is not
        // told to rebuild (set returns false: the visible FAB is unchanged).
        expect(stack.set(_entryFab, vaultDetail), isFalse);
        expect(stack.current, same(_apiKeysFab));
        expect(stack.depth, 2);

        // When API Keys pops, the vault detail resurfaces — with its updated fab.
        stack.clear(apiKeys);
        expect(stack.current, same(_entryFab));
      },
    );

    test('updating the top owner in place changes the current FAB', () {
      final stack = FabOwnershipStack();
      final covered = Object();
      final top = Object();

      stack.set(_vaultFab, covered);
      stack.set(_apiKeysFab, top);

      // The visible (top) page legitimately swaps its FAB (e.g. a detail tab
      // switch) → current updates and the shell must rebuild.
      expect(stack.set(_entryFab, top), isTrue);
      expect(stack.current, same(_entryFab));
      expect(stack.depth, 2);
    });

    test('clearing an unknown owner is a no-op', () {
      final stack = FabOwnershipStack();
      stack.set(_vaultFab, Object());

      expect(stack.clear(Object()), isFalse);
      expect(stack.current, same(_vaultFab));
    });

    test('clearing a non-top owner does not change the current FAB', () {
      final stack = FabOwnershipStack();
      final covered = Object();
      final top = Object();

      stack.set(_vaultFab, covered);
      stack.set(_apiKeysFab, top);

      // The covered page disposes while still covered (rare, but must be
      // safe) — the top FAB stays put.
      expect(stack.clear(covered), isTrue);
      expect(stack.current, same(_apiKeysFab));
      expect(stack.depth, 1);
    });
  });
}
