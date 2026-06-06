import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/permissions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../agents/presentation/bloc/agents_cubit.dart';
import '../../../approval/presentation/cubit/pending_grants_cubit.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/settings_drawer.dart';

/// Top-level scaffold that wraps the five authenticated tabs (Home,
/// Vaults, Agents, Audit, Settings) with a persistent
/// [BottomNavigationBar].
///
/// The Settings tab is special: instead of navigating to a dedicated
/// route it opens the [SettingsDrawer] on the shell's scaffold. This
/// keeps the simple "lock / log out / version" actions one tap away
/// without dedicating an entire screen to them in the MVP.
///
/// Used as the builder for the `ShellRoute` in `app_router.dart`.
/// Child routes decide their own background — the shell only owns
/// the chrome (the bottom nav and the end-drawer). Any descendant
/// widget that wants to programmatically open the same drawer (e.g.
/// the vault list's header cog button) can call
/// `AppShellScope.of(context).openSettingsDrawer()` instead of mounting
/// its own copy.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isBottomNavHidden = false;
  Widget? _fab;

  // Cache tearoffs so AppShellScope.updateShouldNotify returns false on
  // rebuilds — prevents all mounted FabRegistrars from re-firing
  // didChangeDependencies and overwriting each other's setFab calls.
  late final VoidCallback _openSettingsDrawerRef = _openSettingsDrawer;
  late final ValueChanged<bool> _setBottomNavHiddenRef = _setBottomNavHidden;
  late final ValueChanged<Widget?> _setFabRef = _setFab;

  @override
  void initState() {
    super.initState();
    // Populate the nav badges up-front, before the user opens the tabs: the
    // Agents tab badge (pending agents) and the Approvals tab badge (pending
    // grant approvals). Live updates then arrive over SignalR (see app.dart);
    // a tab tap / app resume / tab focus quietly refreshes as a fallback.
    getIt<AgentsCubit>().refresh();
    // Pending-grants feed is GrantManage-only — loading it without the
    // permission 403s on cold start, so gate the badge load.
    if (_canManageGrants()) getIt<PendingGrantsCubit>().load();
  }

  /// True when the current session holds the GrantManage permission.
  bool _canManageGrants() {
    final state = context.read<AuthBloc>().state;
    return state is AuthAuthenticated &&
        (state.permissions & Permissions.grantManage) != 0;
  }

  void _openSettingsDrawer() => _scaffoldKey.currentState?.openEndDrawer();

  /// Toggles the bottom navigation visibility from descendants. Called
  /// from pages that open modal bottom sheets so the nav doesn't peek
  /// out behind / above the sheet (matches the prototype's behaviour).
  void _setBottomNavHidden(bool hidden) {
    if (_isBottomNavHidden == hidden) return;
    setState(() => _isBottomNavHidden = hidden);
  }

  /// Lets descendants register the shell-level [FloatingActionButton]
  /// without each page mounting its own copy on its [Scaffold]. Pages
  /// that own a FAB hoist it here via [FabRegistrar] so the FAB stays
  /// pinned in place during route transitions instead of animating with
  /// the page body.
  ///
  /// Pass `null` to clear the FAB. Identical-by-reference widgets are
  /// no-ops to avoid pointless rebuilds.
  void _setFab(Widget? fab) {
    if (identical(_fab, fab)) return;
    setState(() => _fab = fab);
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final currentIndex = _tabIndex(location);
    final brightness = Theme.of(context).brightness;

    return AppShellScope(
      openSettingsDrawer: _openSettingsDrawerRef,
      setBottomNavHidden: _setBottomNavHiddenRef,
      setFab: _setFabRef,
      child: Container(
        decoration: BoxDecoration(
          gradient: AppColors.backgroundGradient(brightness),
        ),
        child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: Colors.transparent,
        endDrawer: const SettingsDrawer(),
        body: widget.child,
        // FAB is owned by the shell so it persists across page
        // transitions instead of animating with the child route. Pages
        // register their FAB via [AppShellScope.setFab] (typically by
        // dropping a `FabRegistrar` into the page body).
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        floatingActionButton: _isBottomNavHidden ? null : _fab,
        // Keep the nav always mounted and slide it off-screen vertically
        // when hidden — `AnimatedSlide` translates the widget without
        // removing it from the tree, so the slide-out matches the
        // bottom sheet's dismissal animation. Scaffold still reserves
        // the nav's space in its layout, which is fine because a sheet
        // covers the body while it's open anyway.
        bottomNavigationBar: AnimatedSlide(
          offset: _isBottomNavHidden ? const Offset(0, 1) : Offset.zero,
          duration: const Duration(milliseconds: 280),
          curve: _isBottomNavHidden ? Curves.easeIn : Curves.easeOut,
          child: BlocBuilder<AgentsCubit, AgentsState>(
            bloc: getIt<AgentsCubit>(),
            builder: (context, agentsState) =>
                BlocBuilder<PendingGrantsCubit, PendingGrantsState>(
              bloc: getIt<PendingGrantsCubit>(),
              builder: (context, pendingState) => AppBottomNav(
                currentIndex: currentIndex,
                onTap: (i) => _onTap(context, i),
                agentsBadgeCount: agentsState.pendingCount,
                approvalsBadgeCount: pendingState.grants.length,
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }

  int _tabIndex(String location) {
    if (location.startsWith('/vaults')) return AppBottomNav.tabVaults;
    if (location.startsWith('/agents')) return AppBottomNav.tabAgents;
    if (location.startsWith('/approvals')) return AppBottomNav.tabApprovals;
    return AppBottomNav.tabHome;
  }

  void _onTap(BuildContext context, int index) {
    if (index == AppBottomNav.tabSettings) {
      _openSettingsDrawer();
      return;
    }
    // Any tab interaction is a good moment to refresh the badges so they update
    // without having to open the owning tab.
    getIt<AgentsCubit>().refresh();
    if (_canManageGrants()) getIt<PendingGrantsCubit>().refresh();
    switch (index) {
      case AppBottomNav.tabHome:
        context.go('/');
        break;
      case AppBottomNav.tabVaults:
        context.go('/vaults');
        break;
      case AppBottomNav.tabAgents:
        context.go('/agents');
        break;
      case AppBottomNav.tabApprovals:
        context.go('/approvals');
        break;
    }
  }
}

/// Inherited handle that lets descendants of [AppShell] reach the
/// shell's chrome without mounting duplicate copies — currently:
///
///   * [openSettingsDrawer] — surface the settings end-drawer.
///   * [setBottomNavHidden] — hide / show the bottom nav while a modal
///     bottom sheet is open so the nav doesn't bleed into the sheet.
///
/// Use [AppShellScope.of] from any widget below the shell to reach
/// these callbacks.
class AppShellScope extends InheritedWidget {
  const AppShellScope({
    super.key,
    required this.openSettingsDrawer,
    required this.setBottomNavHidden,
    required this.setFab,
    required super.child,
  });

  /// Opens the settings end-drawer on the shell's scaffold. Safe to
  /// call from any descendant — falls back to a no-op if the scaffold
  /// is no longer mounted.
  final VoidCallback openSettingsDrawer;

  /// Hides (`true`) or shows (`false`) the shell's bottom navigation.
  /// Pages that open `showModalBottomSheet` should set `true` before
  /// awaiting the sheet and `false` after it dismisses.
  final ValueChanged<bool> setBottomNavHidden;

  /// Registers (or clears, when `null`) the shell-level
  /// [FloatingActionButton]. Drop a [FabRegistrar] into the page body
  /// instead of calling this directly — the registrar wraps the
  /// post-frame timing needed to play nicely with route transitions.
  final ValueChanged<Widget?> setFab;

  /// Looks up the nearest [AppShellScope]. Throws if no shell is
  /// mounted above [context] — call sites should be reachable only
  /// from within the [AppShell] subtree.
  static AppShellScope of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AppShellScope>();
    assert(scope != null, 'AppShellScope.of called without an AppShell ancestor');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppShellScope oldWidget) =>
      openSettingsDrawer != oldWidget.openSettingsDrawer ||
      setBottomNavHidden != oldWidget.setBottomNavHidden ||
      setFab != oldWidget.setFab;
}
