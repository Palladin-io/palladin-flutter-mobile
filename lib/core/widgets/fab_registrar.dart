import 'package:flutter/material.dart';

import '../../features/shell/presentation/pages/app_shell.dart';

/// Invisible widget that registers a [FloatingActionButton] (or any
/// widget) with the shell-level FAB ownership stack
/// ([AppShellScope.setFab] / [AppShellScope.clearFab]).
///
/// FABs declared on a child page's [Scaffold] animate together with the
/// page transition because they're part of the page's content. Hoisting
/// the FAB to the shell's [Scaffold] keeps it pinned in place — like the
/// bottom nav — but the shell can't know which page is currently visible
/// and what FAB it wants. [FabRegistrar] bridges that gap: drop one into
/// the page body and it claims FAB ownership for as long as it's mounted.
///
/// **Ownership.** Each registrar instance owns one entry on the shell's
/// FAB stack (keyed by its [State] identity). While mounted it pushes
/// [fab] to the top, so the *most-recently-shown* page wins — exactly
/// what we want when a detail page is pushed over a list. On dispose it
/// removes its entry, so the previously-covered page's FAB reappears
/// automatically without that page re-asserting anything. This makes FAB
/// ownership deterministic and stops a covered page's FAB from leaking
/// onto a page that declares a different (or no) FAB.
///
/// **Every shell page must mount one** — even pages with no FAB. Pass
/// `null` for [fab] to claim the top of the stack with no FAB; that's how
/// a page suppresses a covered page's FAB.
///
/// The widget renders a 0×0 [SizedBox.shrink], so it's safe to drop into
/// any layout (a [Stack], a [SliverList] item, …) without affecting
/// layout.
class FabRegistrar extends StatefulWidget {
  const FabRegistrar({super.key, required this.fab});

  /// FAB to register on the shell. `null` claims the top of the stack
  /// with no FAB (suppressing any covered page's FAB).
  final Widget? fab;

  @override
  State<FabRegistrar> createState() => _FabRegistrarState();
}

class _FabRegistrarState extends State<FabRegistrar> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Defer until after the current build so the InheritedWidget
    // lookup is safe and we don't mutate the shell's state during a
    // descendant's build. `this` is the stable ownership token.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppShellScope.of(context).setFab(widget.fab, this);
    });
  }

  @override
  void didUpdateWidget(FabRegistrar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fab != oldWidget.fab) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) AppShellScope.of(context).setFab(widget.fab, this);
      });
    }
  }

  @override
  void dispose() {
    // Deterministically drop this registrar's FAB. If a newer page has
    // already pushed its own entry on top, our entry is below it and
    // removing it is invisible — so there's no null flash on transitions
    // where the incoming page already owns the FAB. If we *were* on top
    // (e.g. a detail page popping back), the covered page's entry below
    // ours surfaces automatically.
    AppShellScope.maybeOf(context)?.clearFab(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
