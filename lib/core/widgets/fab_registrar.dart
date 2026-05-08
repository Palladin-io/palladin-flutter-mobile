import 'package:flutter/material.dart';

import '../../features/shell/presentation/pages/app_shell.dart';

/// Invisible widget that registers a [FloatingActionButton] (or any
/// widget) with the shell-level [AppShellScope.setFab] callback.
///
/// FABs declared on a child page's [Scaffold] animate together with the
/// page transition because they're part of the page's content. Hoisting
/// the FAB to the shell's [Scaffold] keeps it pinned in place — like the
/// bottom nav — but the shell can't know which page is currently visible
/// and what FAB it wants. [FabRegistrar] bridges that gap: drop one into
/// the page body and it pushes [fab] to the shell whenever this widget
/// is mounted (or its [fab] changes).
///
/// Pass `null` to clear the FAB on tabs/states that shouldn't show one
/// — otherwise a sibling page's FAB would linger after navigation.
///
/// The widget renders a 0×0 [SizedBox.shrink], so it's safe to drop into
/// any layout (a [Stack], a [SliverList] item, …) without affecting
/// layout.
class FabRegistrar extends StatefulWidget {
  const FabRegistrar({super.key, required this.fab});

  /// FAB to register on the shell. `null` clears any previously
  /// registered FAB.
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
    // descendant's build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppShellScope.of(context).setFab(widget.fab);
    });
  }

  @override
  void didUpdateWidget(FabRegistrar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fab != oldWidget.fab) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) AppShellScope.of(context).setFab(widget.fab);
      });
    }
  }

  @override
  void dispose() {
    // Schedule a post-frame no-op so the incoming page's registrar runs
    // its own post-frame setFab first — avoids a one-frame null flash
    // during route transitions where both pages exist briefly.
    WidgetsBinding.instance.addPostFrameCallback((_) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
