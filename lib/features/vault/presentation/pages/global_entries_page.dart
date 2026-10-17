import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/permissions.dart';
import '../../../../core/utils/secure_clipboard.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_fab.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/app_search_field.dart';
import '../../../../core/widgets/fab_registrar.dart';
import '../../../../core/widgets/skeleton_box.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/entry_entity.dart';
import '../../domain/entities/vault_entity.dart';
import '../cubit/global_entries_cubit.dart';
import '../cubit/vault_list_cubit.dart';
import '../widgets/choose_entry_vault_sheet.dart';
import '../widgets/create_vault_sheet.dart';
import '../widgets/entry_list_card.dart';
import '../widgets/vault_library_switch.dart';
import 'add_entry_page.dart';
import 'entry_detail_page.dart';
import 'entry_share_creation_page.dart';

/// Owned by the library route, so switching segments preserves search/scroll.
class GlobalEntriesPreferences {
  final search = TextEditingController();
  final scroll = ScrollController();
  void clear() {
    search.clear();
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  void dispose() {
    search.dispose();
    scroll.dispose();
  }
}

class GlobalEntriesPage extends StatefulWidget {
  const GlobalEntriesPage({super.key, required this.preferences});
  final GlobalEntriesPreferences preferences;
  @override
  State<GlobalEntriesPage> createState() => _GlobalEntriesPageState();
}

class _GlobalEntriesPageState extends State<GlobalEntriesPage>
    with WidgetsBindingObserver {
  late final GlobalEntriesCubit _entries;
  late final VaultListCubit _vaults;
  late final StreamSubscription<VaultListState> _vaultChanges;
  late final StreamSubscription<GlobalEntriesState> _entryChanges;
  final _revealedFields = <(String, String), Set<String>>{};
  AuthState? _lastAuth;
  Animation<double>? _coverAnimation;
  Widget? _fab;
  GlobalEntriesPreferences get ui => widget.preferences;

  @override
  void initState() {
    super.initState();
    _vaults = context.read<VaultListCubit>();
    _entries = getIt<GlobalEntriesCubit>();
    _lastAuth = context.read<AuthBloc>().state;
    WidgetsBinding.instance.addObserver(this);
    _entryChanges = _entries.stream.listen((state) {
      _revealedFields.removeWhere(
        (id, _) => !state.expandedEntries.contains(id),
      );
    });
    _vaultChanges = _vaults.stream.listen((state) {
      if (mounted) setState(() {});
      if (state is VaultListLoaded) {
        _entries.replaceVaults(state.vaults);
        unawaited(_load());
      } else if (state is VaultListLocked || state is VaultListResetRequired) {
        _entries.lock();
      }
    });
    unawaited(_load());
  }

  Future<void> _load() async {
    final auth = context.read<AuthBloc>().state;
    final state = _vaults.state;
    if (auth is AuthAuthenticated &&
        !auth.isVaultLocked &&
        auth.privateKey != null &&
        state is VaultListLoaded) {
      await _entries.load(state.vaults, auth.privateKey!);
    }
  }

  Future<void> _refresh() async {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated || auth.isVaultLocked) return;
    await _vaults.loadVaults(auth.privateKey);
  }

  Future<void> _add() async {
    _clearReveals();
    // Do not restore focus to the off-screen search field when the modal or
    // pushed form closes: Flutter would scroll it into view over our position.
    FocusManager.instance.primaryFocus?.unfocus();
    final vault = await showModalBottomSheet<VaultEntity>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: AppColors.modalBackground(Theme.of(context).brightness),
      builder: (_) => BlocProvider.value(
        value: _vaults,
        child: ChooseEntryVaultSheet(
          onCreateFirstVault: () {
            Navigator.of(context, rootNavigator: true).pop();
            unawaited(_createFirstVault());
          },
        ),
      ),
    );
    if (!mounted || vault == null) return;
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated || auth.isVaultLocked) return;
    final state = _vaults.state;
    if (state is! VaultListLoaded ||
        !state.vaults.any((item) => item.id == vault.id)) {
      return;
    }
    await AddEntryPage.push(
      context,
      vaultId: vault.id,
      vaultName: vault.name,
      wrappedVK: vault.wrappedVK,
    );
    if (mounted) await _load();
  }

  Future<void> _open(GlobalEntryRow row) async {
    _clearReveals();
    FocusManager.instance.primaryFocus?.unfocus();
    await EntryDetailPage.push(
      context,
      entry: row.toEntryEntity(),
      wrappedVK: row.vault.wrappedVK,
    );
    if (mounted) await _load();
  }

  Future<void> _createFirstVault() async {
    final created = await CreateVaultSheet.show(context);
    if (!mounted || created == null) return;
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated || auth.isVaultLocked) return;
    await _vaults.loadVaults(auth.privateKey);
    if (mounted) await _add();
  }

  bool get _canShare {
    final auth = context.read<AuthBloc>().state;
    return auth is AuthAuthenticated &&
        !auth.isVaultLocked &&
        auth.privateKey != null &&
        auth.emailVerified &&
        (auth.permissions & Permissions.vaultManage) != 0;
  }

  void _clearReveals() {
    _revealedFields.clear();
    _entries.clearReveals();
  }

  Future<void> _share(GlobalEntryRow row) async {
    if (!_canShare) return;
    _clearReveals();
    FocusManager.instance.primaryFocus?.unfocus();
    await EntryShareCreationPage.push(context, row.toEntryEntity());
  }

  Future<void> _toggleReveal(GlobalEntryRow row) async {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated ||
        auth.isVaultLocked ||
        auth.privateKey == null) {
      return;
    }
    final success = await _entries.toggleReveal(row, auth.privateKey!);
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.entryErrorCrypto)),
      );
    }
  }

  Future<void> _copy(String value) async {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated || auth.isVaultLocked) return;
    await SecureClipboard.copy(value);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.vaultCopyValue)),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _clearReveals();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.secondaryAnimation;
    if (!identical(animation, _coverAnimation)) {
      _coverAnimation?.removeStatusListener(_covered);
      _coverAnimation = animation;
      animation?.addStatusListener(_covered);
    }
  }

  void _covered(AnimationStatus status) {
    if (status == AnimationStatus.forward ||
        status == AnimationStatus.completed) {
      _clearReveals();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _coverAnimation?.removeStatusListener(_covered);
    unawaited(_entryChanges.cancel());
    _revealedFields.clear();
    unawaited(_vaultChanges.cancel());
    unawaited(_entries.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BlocListener<AuthBloc, AuthState>(
      listener: (_, state) {
        final previous = _lastAuth;
        _lastAuth = state;
        if (state is AuthAuthenticated &&
            previous is AuthAuthenticated &&
            (state.userId != previous.userId ||
                !identical(state.privateKey, previous.privateKey))) {
          _entries.lock();
          ui.clear();
        }
        _clearReveals();
        if (state is! AuthAuthenticated || state.isVaultLocked) {
          _entries.lock();
          ui.clear();
        }
      },
      child: BlocBuilder<GlobalEntriesCubit, GlobalEntriesState>(
        bloc: _entries,
        builder: (context, state) {
          final rows = state.filter(query: ui.search.text);
          final vaultState = _vaults.state;
          return AppScreen.titled(
            title: l10n.vaultTabEntries,
            subtitle: l10n.vaultEntryCount(state.rows.length),
            actions: const [VaultLibrarySwitch(entries: true)],
            floatingActionButton: FabRegistrar(
              fab: _fab ??= AppFab.shell(
                onPressed: _add,
                tooltip: l10n.entryAddTitle,
              ),
            ),
            body: RefreshIndicator(
              onRefresh: _refresh,
              child: CustomScrollView(
                key: const PageStorageKey('global-entries-scroll'),
                controller: ui.scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.screenH,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        children: [
                          AppSearchField(
                            controller: ui.search,
                            hint: l10n.entrySearchHint,
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: AppSpacing.fieldGap),
                          if (state.failedVaultIds.isNotEmpty ||
                              vaultState is VaultListError ||
                              vaultState is VaultListResetRequired)
                            TextButton(
                              onPressed: _refresh,
                              child: Text(
                                '${l10n.vaultErrorUnknown} · ${l10n.vaultRetry}',
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if ((state.loading ||
                          vaultState is VaultListInitial ||
                          vaultState is VaultListLoading) &&
                      rows.isEmpty)
                    const SliverPadding(
                      padding: EdgeInsets.symmetric(
                        horizontal: AppSpacing.screenH,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: SkeletonBox(height: 80),
                      ),
                    )
                  else if (rows.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: Text(l10n.globalEntriesEmpty)),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.screenH,
                        0,
                        AppSpacing.screenH,
                        AppSpacing.listBottom,
                      ),
                      sliver: SliverList.separated(
                        itemCount: rows.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.cardGap),
                        itemBuilder: (_, index) {
                          final row = rows[index];
                          final entry = row.toEntryEntity();
                          return EntryListCard(
                            enabled:
                                EntryType.values.elementAtOrNull(
                                  row.entry.entryType,
                                ) !=
                                null,
                            key: ValueKey(row.identity),
                            entry: entry,
                            vaultName: row.vault.name,
                            isExpanded: state.expandedEntries.contains(
                              row.identity,
                            ),
                            payload:
                                state.revealedEntries[row.identity]?.payload,
                            revealedFields:
                                _revealedFields[row.identity] ?? const {},
                            onToggleReveal: () => _toggleReveal(row),
                            onToggleFieldReveal: (entryId, field) =>
                                setState(() {
                                  final fields = _revealedFields.putIfAbsent(
                                    row.identity,
                                    () => {},
                                  );
                                  final id = '$entryId:$field';
                                  if (!fields.remove(id)) fields.add(id);
                                }),
                            onCopy: _copy,
                            onEdit: () => _open(row),
                            onShare: _canShare ? () => _share(row) : null,
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
