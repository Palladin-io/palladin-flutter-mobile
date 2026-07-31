import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/widgets/fab_registrar.dart';
import 'package:mobile_palladin/features/shell/presentation/pages/app_shell.dart';

/// Minimal host that exposes the shell's FAB callbacks via [AppShellScope]
/// and renders [child], so a [FabRegistrar] can register/clear without
/// standing up the full [AppShell] (DI, blocs, router).
class _ScopeHost extends StatefulWidget {
  const _ScopeHost({super.key, required this.child});

  final Widget child;

  @override
  State<_ScopeHost> createState() => _ScopeHostState();
}

class _ScopeHostState extends State<_ScopeHost> {
  Widget? fab;
  final List<Object> owners = [];

  void _setFab(Widget? f, Object owner) {
    if (!owners.contains(owner)) owners.add(owner);
    setState(() => fab = f);
  }

  void _clearFab(Object owner) {
    owners.remove(owner);
    setState(() => fab = null);
  }

  @override
  Widget build(BuildContext context) {
    return AppShellScope(
      openSettingsDrawer: () {},
      setBottomNavHidden: (_) {},
      setFab: _setFab,
      clearFab: _clearFab,
      child: widget.child,
    );
  }
}

void main() {
  testWidgets('disposing while deactivated does not crash on ancestor lookup', (
    tester,
  ) async {
    final hostKey = GlobalKey<_ScopeHostState>();

    await tester.pumpWidget(
      MaterialApp(
        home: _ScopeHost(
          key: hostKey,
          child: const Scaffold(body: FabRegistrar(fab: Icon(Icons.add))),
        ),
      ),
    );
    await tester.pump(); // run the registrar's post-frame setFab

    // Navigate away: the registrar leaves the tree and disposes. The old
    // implementation looked up AppShellScope in dispose() and threw
    // "Looking up a deactivated widget's ancestor is unsafe."
    await tester.pumpWidget(
      MaterialApp(
        home: _ScopeHost(
          key: hostKey,
          child: const Scaffold(body: SizedBox.shrink()),
        ),
      ),
    );
    await tester.pump(); // run the dispose post-frame clearFab

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'switching tabs and tearing down pending FAB updates is lifecycle-safe',
    (tester) async {
      final hostKey = GlobalKey<_ScopeHostState>();

      Widget app({required int tab, required bool mounted}) => MaterialApp(
        home: _ScopeHost(
          key: hostKey,
          child: Scaffold(
            body: mounted
                ? FabRegistrar(
                    // Mirrors Vault Detail: Entries and Agents own a FAB;
                    // Logs, Members and Settings explicitly suppress it.
                    fab: switch (tab) {
                      0 => const Icon(Icons.add),
                      1 => const Icon(Icons.person_add_alt_1),
                      _ => null,
                    },
                  )
                : const SizedBox.shrink(),
          ),
        ),
      );

      await tester.pumpWidget(app(tab: 0, mounted: true));
      await tester.pump();

      // Traverse all five Vault Detail tabs without settling their deferred
      // registrations, then immediately remove the route subtree.
      for (var tab = 1; tab < 5; tab++) {
        await tester.pumpWidget(app(tab: tab, mounted: true));
      }
      await tester.pumpWidget(app(tab: 4, mounted: false));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(hostKey.currentState!.owners, isEmpty);
    },
  );
}
