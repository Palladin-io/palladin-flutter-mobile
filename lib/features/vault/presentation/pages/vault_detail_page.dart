import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/entities/vault_entity.dart';
import '../../domain/exceptions/vault_exceptions.dart';
import '../cubit/vault_detail_cubit.dart';
import '../widgets/grant_card.dart';
import '../widgets/vault_agents_tab.dart';
import '../widgets/vault_entries_tab.dart';
import '../widgets/vault_form.dart';
import '../widgets/vault_placeholder_tab.dart';
import '../widgets/vault_settings_tab.dart';

/// Vault detail screen — wraps a [DefaultTabController] with five tabs:
/// Entries, Agents, Logs, Members, Settings. Each tab body lives in
/// its own widget under `widgets/vault_*_tab.dart`.
///
/// Page-level state (form-data dirty flag, current tab index) is held
/// here so the AppBar Save action can react without coupling the
/// settings widget to the cubit.
class VaultDetailPage extends StatelessWidget {
  const VaultDetailPage({super.key, required this.vaultId});

  final String vaultId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<VaultDetailCubit>(
      create: (_) => getIt<VaultDetailCubit>()..load(vaultId),
      child: _VaultDetailView(vaultId: vaultId),
    );
  }
}

enum _VaultTab { entries, agents, logs, members, settings }

class _VaultDetailView extends StatefulWidget {
  const _VaultDetailView({required this.vaultId});

  final String vaultId;

  @override
  State<_VaultDetailView> createState() => _VaultDetailViewState();
}

class _VaultDetailViewState extends State<_VaultDetailView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  VaultFormData? _initialFormData;
  VaultFormData? _currentFormData;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _VaultTab.values.length, vsync: this)
      ..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool get _isSettingsTab =>
      _tabController.index == _VaultTab.settings.index;

  bool get _isFormDirty {
    final current = _currentFormData;
    final initial = _initialFormData;
    if (current == null || initial == null) return false;
    return current != initial;
  }

  void _saveSettings() {
    final data = _currentFormData;
    if (data == null) return;
    context.read<VaultDetailCubit>().update(
          widget.vaultId,
          name: data.name.trim(),
          description: data.description.trim(),
          icon: data.icon,
          color: data.color,
          grantMode: data.grantMode,
        );
  }

  Future<void> _confirmDelete(VaultEntity vault) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.darkSurface,
          title: Text(
            l10n.vaultDeleteTitle,
            style: const TextStyle(color: AppColors.textPrimary),
          ),
          content: Text(
            l10n.vaultDeleteConfirmWithName(vault.name),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                l10n.vaultCancel,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                l10n.vaultDeleteVault,
                style: const TextStyle(color: AppColors.brandRed),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed == true && mounted) {
      // ignore: use_build_context_synchronously
      context.read<VaultDetailCubit>().delete(widget.vaultId);
    }
  }

  void _syncFormFromVault(VaultEntity vault, AppLocalizations l10n) {
    final next = VaultFormData(
      name: vault.name,
      description: vault.description ?? '',
      icon: vault.icon ?? 'shield',
      color: vault.color ?? '#FF4F4F',
      grantMode: vault.grantMode,
    );
    if (_initialFormData == null) {
      setState(() {
        _initialFormData = next;
        _currentFormData = next;
      });
    } else if (next != _initialFormData) {
      setState(() {
        _initialFormData = next;
        _currentFormData = next;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(l10n.vaultSavedSnackbar),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BlocConsumer<VaultDetailCubit, VaultDetailState>(
      listener: (context, state) {
        if (state is VaultDetailLoaded) {
          _syncFormFromVault(state.vault, l10n);
        } else if (state is VaultDetailDeleted) {
          context.go('/');
        }
      },
      builder: (context, state) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: _DetailAppBar(
            state: state,
            isSettingsTab: _isSettingsTab,
            isFormDirty: _isFormDirty,
            onSave: _saveSettings,
            onBack: () => context.pop(),
            tabController: _tabController,
          ),
          body: Container(
            decoration: const BoxDecoration(
              gradient: AppColors.darkBackgroundGradient,
            ),
            child: SafeArea(
              top: false,
              child: switch (state) {
                VaultDetailInitial() ||
                VaultDetailLoading() => const _LoadingView(),
                VaultDetailDeleted() => const SizedBox.shrink(),
                VaultDetailError(:final kind) => _ErrorView(kind: kind),
                VaultDetailLoaded(:final vault) => _LoadedBody(
                    vault: vault,
                    tabController: _tabController,
                    initialFormData: _initialFormData,
                    onFormChanged: (data) =>
                        setState(() => _currentFormData = data),
                    onDelete: () => _confirmDelete(vault),
                  ),
              },
            ),
          ),
          floatingActionButton: _DetailFab(
            currentTab: _tabController.index,
            l10n: l10n,
          ),
        );
      },
    );
  }
}

// ── AppBar ─────────────────────────────────────────────────────────

class _DetailAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _DetailAppBar({
    required this.state,
    required this.isSettingsTab,
    required this.isFormDirty,
    required this.onSave,
    required this.onBack,
    required this.tabController,
  });

  final VaultDetailState state;
  final bool isSettingsTab;
  final bool isFormDirty;
  final VoidCallback onSave;
  final VoidCallback onBack;
  final TabController tabController;

  static const double _tabBarHeight = 36;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + _tabBarHeight);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final s = state;
    final loaded = s is VaultDetailLoaded ? s.vault : null;
    final subtitle = loaded != null ? l10n.vaultEntryCount(loaded.entryCount) : '';

    return AppBar(
      backgroundColor: AppColors.darkSurface,
      titleSpacing: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, size: 18),
        onPressed: onBack,
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            loaded?.name ?? l10n.vaultTitle,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (subtitle.isNotEmpty)
            Text(
              subtitle,
              style: const TextStyle(
                color: AppColors.textTertiaryMobile,
                fontSize: 11,
              ),
            ),
        ],
      ),
      actions: [
        if (isSettingsTab)
          TextButton(
            onPressed: isFormDirty ? onSave : null,
            child: Text(
              l10n.vaultSaveAction,
              style: TextStyle(
                color: isFormDirty
                    ? AppColors.brandRed
                    : AppColors.brandRed.withValues(alpha: 0.4),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        else
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {
              // Context menu lands in a follow-up ticket.
            },
          ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(_tabBarHeight),
        child: TabBar(
          controller: tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          labelColor: AppColors.brandRed,
          unselectedLabelColor: AppColors.textTertiaryMobile,
          indicatorColor: AppColors.brandRed,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
          tabs: [
            Tab(text: l10n.vaultTabEntries),
            Tab(text: l10n.vaultTabAgents),
            Tab(text: l10n.vaultTabLogs),
            Tab(text: l10n.vaultTabMembers),
            Tab(text: l10n.vaultTabSettings),
          ],
        ),
      ),
    );
  }
}

// ── Loaded body ────────────────────────────────────────────────────

class _LoadedBody extends StatelessWidget {
  const _LoadedBody({
    required this.vault,
    required this.tabController,
    required this.initialFormData,
    required this.onFormChanged,
    required this.onDelete,
  });

  final VaultEntity vault;
  final TabController tabController;
  final VaultFormData? initialFormData;
  final ValueChanged<VaultFormData> onFormChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: TabBarView(
        controller: tabController,
        children: [
          VaultEntriesTab(entries: _MockData.entries),
          VaultAgentsTab(grants: _MockData.grants),
          _PlaceholderTabBuilder(
            messageKey: (l10n) => l10n.vaultLogsEmpty,
            icon: Icons.history,
          ),
          _PlaceholderTabBuilder(
            messageKey: (l10n) => l10n.vaultMembersEmpty,
            icon: Icons.group_outlined,
          ),
          if (initialFormData != null)
            VaultSettingsTab(
              initial: initialFormData!,
              onChanged: onFormChanged,
              onDelete: onDelete,
            )
          else
            const SizedBox.shrink(),
        ],
      ),
    );
  }
}

class _PlaceholderTabBuilder extends StatelessWidget {
  const _PlaceholderTabBuilder({
    required this.messageKey,
    required this.icon,
  });

  final String Function(AppLocalizations) messageKey;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return VaultPlaceholderTab(icon: icon, message: messageKey(l10n));
  }
}

// ── FAB ────────────────────────────────────────────────────────────

class _DetailFab extends StatelessWidget {
  const _DetailFab({required this.currentTab, required this.l10n});

  final int currentTab;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final showOnEntries = currentTab == _VaultTab.entries.index;
    final showOnAgents = currentTab == _VaultTab.agents.index;
    if (!showOnEntries && !showOnAgents) return const SizedBox.shrink();

    return FloatingActionButton(
      backgroundColor: AppColors.brandRed,
      foregroundColor: Colors.white,
      tooltip: showOnEntries ? l10n.vaultAddEntryFab : l10n.vaultAddGrantFab,
      onPressed: () {
        // Add flows ship in CVT-32 (entries) and the grants ticket.
      },
      child: const Icon(Icons.add),
    );
  }
}

// ── Loading / error ────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: AppColors.tealAccent),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.kind});

  final VaultErrorKind kind;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          switch (kind) {
            VaultErrorKind.notFound => l10n.vaultErrorNotFound,
            VaultErrorKind.forbidden => l10n.vaultErrorForbidden,
            VaultErrorKind.planLimitReached => l10n.vaultErrorPlanLimitReached,
            VaultErrorKind.fullModeNotAllowed =>
              l10n.vaultErrorFullModeNotAllowed,
            VaultErrorKind.networkError => l10n.errorCannotConnectToServer,
            VaultErrorKind.unknown => l10n.vaultErrorUnknown,
          },
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

// ── Mock data (lives here so the page is self-contained) ───────────

abstract final class _MockData {
  static final List<MockEntry> entries = [
    const MockEntry(
      kind: EntryKind.key,
      name: 'AWS Access Key',
      meta: 'accessed 3m ago',
      icon: Icons.vpn_key,
      url: 'console.aws.amazon.com',
      value: 'AKIAIOSFODNN7EXAMPLE',
    ),
    const MockEntry(
      kind: EntryKind.key,
      name: 'Stripe API Key',
      meta: 'accessed 1h ago',
      icon: Icons.payment,
      url: 'dashboard.stripe.com',
      value: 'sk_live_51HxyzABCDEFG',
    ),
    const MockEntry(
      kind: EntryKind.credential,
      name: 'GitHub Enterprise',
      meta: 'github.com',
      icon: Icons.language,
      url: 'github.com',
      username: 'patryk@company.com',
      password: 'GitH0b!2026',
    ),
    const MockEntry(
      kind: EntryKind.credential,
      name: 'Vercel Dashboard',
      meta: 'vercel.com',
      icon: Icons.rocket_launch,
      url: 'vercel.com',
      username: 'patryk@vercel.com',
      password: 'V3rc3l#2026',
    ),
    const MockEntry(
      kind: EntryKind.key,
      name: 'OpenAI API Key',
      meta: 'accessed 2h ago',
      icon: Icons.psychology,
      url: 'platform.openai.com',
      value: 'sk-proj-aBcDeFgHiJkL',
    ),
  ];

  static final List<MockGrant> grants = [
    const MockGrant(
      agent: GrantAgent(
        type: AgentType.claude,
        name: 'Claude',
        initials: 'CL',
      ),
      mode: GrantUiMode.full,
      status: GrantStatus.active,
      expiresAbsolute: 'Apr 26 at 20:22',
      expiresRelative: 'in 6h',
      grantedBy: 'Patryk',
    ),
    const MockGrant(
      agent: GrantAgent(
        type: AgentType.cursor,
        name: 'Cursor',
        initials: 'Cu',
      ),
      mode: GrantUiMode.granular,
      status: GrantStatus.active,
      expiresAbsolute: 'Apr 27 at 13:05',
      expiresRelative: 'in 23h',
      grantedBy: 'Patryk',
      entries: [
        GrantEntry(name: 'AWS Access Key'),
        GrantEntry(name: 'Stripe API Key'),
        GrantEntry(name: 'GitHub Token', isActive: false),
        GrantEntry(name: 'OpenAI API Key'),
      ],
    ),
    const MockGrant(
      agent: GrantAgent(
        type: AgentType.copilot,
        name: 'Copilot',
        initials: 'Co',
      ),
      mode: GrantUiMode.full,
      status: GrantStatus.expired,
      expiresAbsolute: 'Apr 26 at 12:10',
      expiresRelative: '2h ago',
      grantedBy: 'Patryk',
    ),
    const MockGrant(
      agent: GrantAgent(
        type: AgentType.openclaw,
        name: 'OpenClaw',
        initials: 'OC',
      ),
      mode: GrantUiMode.granular,
      status: GrantStatus.revoked,
      expiresAbsolute: '',
      expiresRelative: '',
      grantedBy: 'Patryk',
      revokedBy: 'Patryk',
      revokedAbsolute: 'Apr 25 at 09:15',
      revokedRelative: '1d ago',
      revokedReason: 'Suspected credential compromise',
      entries: [
        GrantEntry(name: 'AWS Access Key'),
        GrantEntry(name: 'Stripe API Key'),
      ],
    ),
  ];
}
