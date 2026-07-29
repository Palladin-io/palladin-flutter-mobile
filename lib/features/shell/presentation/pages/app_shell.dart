import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/permissions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../agents/presentation/bloc/agents_cubit.dart';
import '../../../approval/presentation/cubit/pending_grants_cubit.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../notifications/presentation/cubit/notification_center_cubit.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/settings_drawer.dart';
import 'fab_ownership_stack.dart';

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

  /// Ownership stack of FAB registrations. The shell renders the top
  /// entry's `fab`; pushing a page's entry on top wins, popping it
  /// resurfaces the covered page's FAB. See [FabOwnershipStack] for the
  /// full rationale — this is what stops a covered page's FAB from leaking
  /// onto a page that declares a different (or no) FAB.
  final FabOwnershipStack _fabStack = FabOwnershipStack();

  // Cache tearoffs so AppShellScope.updateShouldNotify returns false on
  // rebuilds — prevents all mounted FabRegistrars from re-firing
  // didChangeDependencies and overwriting each other's setFab calls.
  late final VoidCallback _openSettingsDrawerRef = _openSettingsDrawer;
  late final ValueChanged<bool> _setBottomNavHiddenRef = _setBottomNavHidden;
  late final SetFabCallback _setFabRef = _setFab;
  late final ClearFabCallback _clearFabRef = _clearFab;

  @override
  void initState() {
    super.initState();
    // Populate nav badges before the user opens the tabs. Live updates arrive
    // over SignalR (see app.dart); tab taps and app resume refresh as fallback.
    getIt<AgentsCubit>().refresh();
    getIt<NotificationCenterCubit>().refreshSummary();
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

  /// The FAB currently shown — the top of the ownership stack, or `null`
  /// when nothing is registered.
  Widget? get _fab => _fabStack.current;

  /// Registers (or updates) the FAB owned by [owner], pushing it to the
  /// top of the ownership stack so it becomes the visible FAB. Called via
  /// [AppShellScope.setFab], typically by a [FabRegistrar] on mount /
  /// update.
  ///
  /// Pass `null` for [fab] to claim the top of the stack with *no* FAB —
  /// this is how a page suppresses a covered page's FAB (e.g. the Agents
  /// list, or a detail tab with no add affordance).
  void _setFab(Widget? fab, Object owner) {
    if (!mounted) return;
    if (_fabStack.set(fab, owner)) setState(() {});
  }

  /// Removes [owner]'s entry from the ownership stack — called when a
  /// [FabRegistrar] disposes. If the owner was on top, the next entry
  /// down (the previously-covered page) becomes visible again. No-op if
  /// the owner never registered or was already removed.
  void _clearFab(Object owner) {
    // Removing from the stack is always valid; only rebuild if the shell
    // is still mounted (a post-frame clear can fire after teardown).
    final changed = _fabStack.clear(owner);
    if (changed && mounted) setState(() {});
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
      clearFab: _clearFabRef,
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
                  BlocBuilder<NotificationCenterCubit, NotificationCenterState>(
                    bloc: getIt<NotificationCenterCubit>(),
                    builder: (context, notificationState) => AppBottomNav(
                      currentIndex: currentIndex,
                      onTap: (i) => _onTap(context, i),
                      agentsBadgeCount: agentsState.pendingCount,
                      inboxBadgeCount: notificationState.unreadCount,
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
    if (location.startsWith('/inbox') || location.startsWith('/approvals')) {
      return AppBottomNav.tabInbox;
    }
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
    getIt<NotificationCenterCubit>().refreshSummary();
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
      case AppBottomNav.tabInbox:
        context.go('/inbox');
        break;
    }
  }
}

/// Registers (or updates) the FAB owned by `owner`. Pass `null` for
/// `fab` to claim the top of the stack with no FAB.
typedef SetFabCallback = void Function(Widget? fab, Object owner);

/// Removes `owner`'s FAB registration from the shell.
typedef ClearFabCallback = void Function(Object owner);

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
    required this.clearFab,
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

  /// Registers (or updates) the shell-level [FloatingActionButton] owned
  /// by a token. Drop a [FabRegistrar] into the page body instead of
  /// calling this directly — the registrar owns the token and wraps the
  /// post-frame timing needed to play nicely with route transitions.
  /// Pass `null` for the FAB to claim the top of the stack with no FAB.
  final SetFabCallback setFab;

  /// Removes a previously-registered FAB owned by the given token. The
  /// next FAB down the ownership stack (the covered page's) becomes
  /// visible again. [FabRegistrar] calls this on dispose.
  final ClearFabCallback clearFab;

  /// Looks up the nearest [AppShellScope]. Throws if no shell is
  /// mounted above [context] — call sites should be reachable only
  /// from within the [AppShell] subtree.
  static AppShellScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppShellScope>();
    assert(
      scope != null,
      'AppShellScope.of called without an AppShell ancestor',
    );
    return scope!;
  }

  @override
  bool updateShouldNotify(AppShellScope oldWidget) =>
      openSettingsDrawer != oldWidget.openSettingsDrawer ||
      setBottomNavHidden != oldWidget.setBottomNavHidden ||
      setFab != oldWidget.setFab ||
      clearFab != oldWidget.clearFab;
}
