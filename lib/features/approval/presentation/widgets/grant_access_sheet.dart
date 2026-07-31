import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_autocomplete_field.dart';
import '../../../../core/widgets/sheet_action_buttons.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../agents/domain/entities/agent.dart';
import '../../../agents/domain/repositories/agents_repository.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../grants/domain/entities/grant_method.dart';
import '../../../vault/presentation/cubit/vault_list_cubit.dart';
import '../cubit/grant_access_cubit.dart';
import 'approval_format.dart';
import 'grant_limit_selector.dart';
import 'grant_methods_selector.dart';

/// Where the "Add agent / Add grant" sheet was opened from — fixes one side of the grant and
/// decides which subject the user picks (mirrors the web `GrantAccessDialog` modes).
sealed class GrantAccessMode {
  const GrantAccessMode();
}

/// From a vault's Agents tab: pick an agent → FULL grant on the vault.
class GrantForVault extends GrantAccessMode {
  const GrantForVault(this.vaultId);
  final String vaultId;
}

/// From an entry's Agents tab: pick an agent → GRANULAR grant on the entry.
class GrantForEntry extends GrantAccessMode {
  const GrantForEntry({required this.vaultId, required this.entryId});
  final String vaultId;
  final String entryId;
}

/// From an agent's Grants tab: pick a vault → FULL grant for the agent.
/// (GRANULAR-per-entry for an agent needs an org-wide entry picker — deferred.)
class GrantForAgent extends GrantAccessMode {
  const GrantForAgent(this.agentId);
  final String agentId;
}

/// Proactive grant-creation sheet. Resolves to `true` once a grant is created
/// so the caller can refresh its list. Reuses [GrantLimitSelector] and
/// [GrantMethodsSelector]; envelope production runs in [GrantAccessCubit] from
/// the unlocked in-memory private key.
class GrantAccessSheet extends StatelessWidget {
  const GrantAccessSheet({super.key, required this.mode});

  final GrantAccessMode mode;

  static Future<bool?> show(BuildContext context, GrantAccessMode mode) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BlocProvider<GrantAccessCubit>(
        create: (_) => getIt<GrantAccessCubit>(),
        child: GrantAccessSheet(mode: mode),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _GrantAccessBody(mode: mode);
}

/// One pickable option (agent or vault).
typedef _Option = ({String id, String label});

class _GrantAccessBody extends StatefulWidget {
  const _GrantAccessBody({required this.mode});
  final GrantAccessMode mode;

  @override
  State<_GrantAccessBody> createState() => _GrantAccessBodyState();
}

class _GrantAccessBodyState extends State<_GrantAccessBody> {
  bool get _pickAgent =>
      widget.mode is GrantForVault || widget.mode is GrantForEntry;

  List<_Option> _options = const [];
  bool _loadingOptions = true;
  String? _loadError;
  String? _selectedId;

  GrantLimit _limit = GrantExpiry(
    DateTime.now().add(const Duration(hours: 24)),
  );
  late List<GrantMethod> _methods = List.of(kDefaultGrantMethods);

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    try {
      final List<_Option> options;
      if (_pickAgent) {
        final agents = await getIt<AgentsRepository>().listAgents();
        options = agents
            .where((a) => a.status == AgentStatus.active)
            .map((a) => (id: a.agentId, label: _agentLabel(a)))
            .toList(growable: false);
      } else {
        final state = getIt<VaultListCubit>().state;
        final vaults = switch (state) {
          VaultListLoaded(:final vaults) => vaults,
          _ => throw StateError('Unlocked Vault projections are unavailable'),
        };
        options = vaults
            .map((v) => (id: v.id, label: v.name))
            .toList(growable: false);
      }
      if (!mounted) return;
      setState(() {
        _options = options;
        _loadingOptions = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loadingOptions = false;
      });
    }
  }

  String _agentLabel(Agent a) {
    final name = a.name?.trim();
    return name != null && name.isNotEmpty
        ? name
        : '${a.publicKeyPrefix}•••${a.publicKeySuffix}';
  }

  Uint8List? _privateKey() {
    final auth = context.read<AuthBloc>().state;
    if (auth is AuthAuthenticated && !auth.isVaultLocked) {
      return auth.privateKey;
    }
    return null;
  }

  Future<void> _onConfirm() async {
    final l10n = AppLocalizations.of(context)!;
    if (_selectedId == null) {
      _snack(
        _pickAgent ? l10n.grantAccessSelectAgent : l10n.grantAccessSelectVault,
      );
      return;
    }
    if (_methods.isEmpty) {
      _snack(l10n.approvalMethodNoneSelected);
      return;
    }
    final key = _privateKey();
    if (key == null) {
      context.read<GrantAccessCubit>().reportVaultLocked();
      return;
    }

    // Resolve the parameters for each mode. The agent's full public key (needed to seal the DEK)
    // comes from the single-agent endpoint.
    final cubit = context.read<GrantAccessCubit>();
    final ({String agentId, String vaultId, bool isFull, String? entryId}) r =
        switch (widget.mode) {
          GrantForVault(:final vaultId) => (
            agentId: _selectedId!,
            vaultId: vaultId,
            isFull: true,
            entryId: null,
          ),
          GrantForEntry(:final vaultId, :final entryId) => (
            agentId: _selectedId!,
            vaultId: vaultId,
            isFull: false,
            entryId: entryId,
          ),
          GrantForAgent(:final agentId) => (
            agentId: agentId,
            vaultId: _selectedId!,
            isFull: true,
            entryId: null,
          ),
        };

    final String agentPublicKey;
    final int recipientKeyVersion;
    try {
      final agent = await getIt<AgentsRepository>().getAgent(r.agentId);
      agentPublicKey = agent.publicKey;
      recipientKeyVersion = agent.recipientKeyVersion;
    } catch (_) {
      if (mounted) _snack(l10n.grantAccessError);
      return;
    }
    if (!mounted) return;

    await cubit.submit(
      vaultId: r.vaultId,
      agentId: r.agentId,
      agentPublicKey: agentPublicKey,
      recipientKeyVersion: recipientKeyVersion,
      isFull: r.isFull,
      entryId: r.entryId,
      privateKey: key,
      limit: _limit,
      methods: _methods,
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return BlocConsumer<GrantAccessCubit, GrantAccessState>(
      listenWhen: (p, c) =>
          p.status != c.status &&
          (c.status == GrantAccessStatus.done ||
              c.status == GrantAccessStatus.error),
      listener: (context, state) {
        if (state.status == GrantAccessStatus.done) {
          Navigator.of(context).pop(true);
        } else if (state.status == GrantAccessStatus.error) {
          _snack(approvalErrorMessage(l10n, state.error!));
          context.read<GrantAccessCubit>().acknowledgeError();
        }
      },
      builder: (context, state) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.modalBackground(brightness),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Scrollable so the type-ahead picker's keyboard never overflows
              // the sheet; the footer band stays pinned below.
              Flexible(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenH,
                      AppSpacing.sm,
                      AppSpacing.screenH,
                      AppSpacing.xl,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: AppColors.cardBorder(brightness),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.headerGap),
                        Text(
                          _pickAgent
                              ? l10n.grantAccessTitleAgent
                              : l10n.grantAccessTitleVault,
                          style: TextStyle(
                            color: AppColors.onSurface(brightness),
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _Picker(
                          label: _pickAgent
                              ? l10n.grantAccessPickAgent
                              : l10n.grantAccessPickVault,
                          options: _options,
                          loading: _loadingOptions,
                          loadError: _loadError != null,
                          emptyText: _pickAgent
                              ? l10n.grantAccessNoAgents
                              : l10n.grantAccessNoVaults,
                          selectedId: _selectedId,
                          enabled: !state.isSubmitting,
                          brightness: brightness,
                          onChanged: (id) => setState(() => _selectedId = id),
                        ),
                        // ^ null when the typed text matches no option.
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          l10n.approvalAccessType,
                          style: TextStyle(
                            color: AppColors.onSurfaceSubtle(brightness),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.innerGap),
                        GrantLimitSelector(
                          value: _limit,
                          enabled: !state.isSubmitting,
                          onChanged: (l) => setState(() => _limit = l),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          l10n.approvalMethodsLegend,
                          style: TextStyle(
                            color: AppColors.onSurfaceSubtle(brightness),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.innerGap),
                        GrantMethodsSelector(
                          value: _methods,
                          enabled: !state.isSubmitting,
                          onChanged: (m) => setState(() => _methods = m),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SheetActionButtons(
                onCancel: () => Navigator.of(context).pop(),
                onConfirm: _onConfirm,
                confirmLabel: state.isSubmitting
                    ? l10n.grantAccessGranting
                    : l10n.grantAccessConfirm,
                confirmColor: AppColors.positiveAccent,
                busy: state.isSubmitting,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A labelled dropdown of [_Option]s, themed like the app's read-only fields.
class _Picker extends StatelessWidget {
  const _Picker({
    required this.label,
    required this.options,
    required this.loading,
    required this.loadError,
    required this.emptyText,
    required this.selectedId,
    required this.enabled,
    required this.brightness,
    required this.onChanged,
  });

  final String label;
  final List<_Option> options;
  final bool loading;
  final bool loadError;
  final String emptyText;
  final String? selectedId;
  final bool enabled;
  final Brightness brightness;

  /// Null when the typed text matches no option (forces a real pick).
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.onSurfaceSubtle(brightness),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.innerGap),
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.innerGap),
            child: SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.brandRed,
              ),
            ),
          )
        else if (loadError || options.isEmpty)
          Text(
            emptyText,
            style: TextStyle(
              color: AppColors.onSurfaceMuted(brightness),
              fontSize: 12,
            ),
          )
        else
          // Type-to-search — the agent / vault list can be large, so a plain
          // dropdown won't scale. Strict: clears the selection unless the text
          // exactly matches an option label.
          AppAutocompleteField<_Option>(
            initialText: _labelFor(selectedId),
            options: options,
            enabled: enabled,
            displayString: (o) => o.label,
            onSelected: (o) => onChanged(o.id),
            onTextChanged: (text) {
              final q = text.trim().toLowerCase();
              final match = options.where((o) => o.label.toLowerCase() == q);
              onChanged(match.isEmpty ? null : match.first.id);
            },
          ),
      ],
    );
  }

  String _labelFor(String? id) {
    if (id == null) return '';
    for (final o in options) {
      if (o.id == id) return o.label;
    }
    return '';
  }
}
