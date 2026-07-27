import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../grants/presentation/widgets/context_grants_tab.dart';
import '../../domain/entities/agent_visibility_policy.dart';
import '../../domain/entities/entry_entity.dart';
import '../cubit/entry_agents_cubit.dart';

/// Agent policy editor, safe Discovery preview and scoped grant list.
class EntryAgentsTab extends StatefulWidget {
  const EntryAgentsTab({
    super.key,
    required this.entry,
    required this.grantsRefresh,
    required this.onUpdated,
  });

  final EntryEntity entry;
  final int grantsRefresh;
  final ValueChanged<EntryEntity> onUpdated;

  @override
  State<EntryAgentsTab> createState() => _EntryAgentsTabState();
}

class _EntryAgentsTabState extends State<EntryAgentsTab>
    with WidgetsBindingObserver {
  final _labelController = TextEditingController();
  bool _requested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && mounted) {
      context.read<EntryAgentsCubit>().clearSensitiveState();
      _labelController.clear();
      _requested = false;
    }
  }

  Future<void> _load() async {
    if (!mounted || _requested) return;
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated || auth.privateKey == null) return;
    _requested = true;
    await context.read<EntryAgentsCubit>().load(
      entry: widget.entry,
      memberPrivateKey: Uint8List.fromList(auth.privateKey!),
    );
  }

  Future<void> _save() async {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated || auth.privateKey == null) return;
    await context.read<EntryAgentsCubit>().save(
      Uint8List.fromList(auth.privateKey!),
    );
  }

  void _retry() {
    _requested = false;
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BlocConsumer<EntryAgentsCubit, EntryAgentsState>(
      listener: (context, state) {
        if (state is EntryAgentsLoaded &&
            _labelController.text != state.agentLabel) {
          _labelController.text = state.agentLabel;
        } else if (state is EntryAgentsSaved) {
          widget.onUpdated(state.entry);
          _labelController.clear();
          _requested = false;
          _load();
        }
      },
      builder: (context, state) => switch (state) {
        EntryAgentsInitial() || EntryAgentsLoading() => const Center(
          child: CircularProgressIndicator(color: AppColors.brandRed),
        ),
        EntryAgentsConflict() => _Message(
          text: l10n.entryErrorConflict,
          action: l10n.vaultRetry,
          onAction: _retry,
        ),
        EntryAgentsError() => _Message(
          text: l10n.entryAgentsPolicyError,
          action: l10n.vaultRetry,
          onAction: _retry,
        ),
        EntryAgentsSaved() => const Center(
          child: CircularProgressIndicator(color: AppColors.brandRed),
        ),
        EntryAgentsLoaded() => Column(
          children: [
            Flexible(
              flex: 5,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenH,
                  AppSpacing.fieldGap,
                  AppSpacing.screenH,
                  AppSpacing.md,
                ),
                child: _PolicyEditor(
                  state: state,
                  labelController: _labelController,
                  onSave: _save,
                ),
              ),
            ),
            Divider(
              height: 1,
              color: AppColors.navBorder(Theme.of(context).brightness),
            ),
            Expanded(
              flex: 4,
              child: ContextGrantsTab(
                key: ValueKey(widget.grantsRefresh),
                entryId: widget.entry.id,
                emptyTitle: l10n.entryAgentsEmptyTitle,
                emptyHint: l10n.entryAgentsEmptyHint,
                contentPadding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenH,
                  AppSpacing.md,
                  AppSpacing.screenH,
                  AppSpacing.listBottom,
                ),
              ),
            ),
          ],
        ),
      },
    );
  }
}

class _PolicyEditor extends StatelessWidget {
  const _PolicyEditor({
    required this.state,
    required this.labelController,
    required this.onSave,
  });

  final EntryAgentsLoaded state;
  final TextEditingController labelController;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final preview = state.discoveryPreview['fields'];
    final previewFields = preview is Map ? preview : const <String, dynamic>{};
    final editable = state.policy.fields.entries
        .where((entry) => entry.key != 'agentLabel')
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.entryAgentsPolicyTitle,
          style: TextStyle(
            color: AppColors.onSurface(brightness),
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          l10n.entryAgentsPolicyHint,
          style: TextStyle(
            color: AppColors.onSurfaceMuted(brightness),
            fontSize: 12,
          ),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: state.policy.discoverable,
          title: Text(l10n.entryAgentsDiscoverable),
          onChanged: state.saving
              ? null
              : context.read<EntryAgentsCubit>().setDiscoverable,
        ),
        if (state.policy.discoverable) ...[
          TextField(
            controller: labelController,
            enabled: !state.saving,
            decoration: InputDecoration(labelText: l10n.entryAgentsAgentLabel),
            onChanged: context.read<EntryAgentsCubit>().setAgentLabel,
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        for (final field in editable)
          _PolicyField(
            id: field.key,
            value: field.value,
            allowed:
                state.allowedAccess[field.key] ??
                const {AgentFieldAccess.never},
            enabled: !state.saving,
          ),
        const SizedBox(height: AppSpacing.md),
        Text(
          l10n.entryAgentsDiscoveryPreview,
          style: TextStyle(
            color: AppColors.onSurface(brightness),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        if (!state.policy.discoverable || previewFields.isEmpty)
          Text(
            l10n.entryAgentsDiscoveryEmpty,
            style: TextStyle(color: AppColors.onSurfaceMuted(brightness)),
          )
        else
          for (final field in previewFields.entries)
            Text(
              '${field.key}: ${field.value}',
              style: TextStyle(color: AppColors.onSurface(brightness)),
            ),
        const SizedBox(height: AppSpacing.md),
        FilledButton(
          onPressed: state.saving ? null : onSave,
          child: Text(
            state.saving
                ? l10n.entryAgentsSavingPolicy
                : l10n.entryAgentsSavePolicy,
          ),
        ),
      ],
    );
  }
}

class _PolicyField extends StatelessWidget {
  const _PolicyField({
    required this.id,
    required this.value,
    required this.allowed,
    required this.enabled,
  });

  final String id;
  final AgentFieldAccess value;
  final Set<AgentFieldAccess> allowed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final choices = allowed.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    return Row(
      children: [
        Expanded(child: Text(id)),
        DropdownButton<AgentFieldAccess>(
          value: value,
          items: [
            for (final choice in choices)
              DropdownMenuItem(
                value: choice,
                child: Text(_accessLabel(context, choice)),
              ),
          ],
          onChanged: !enabled
              ? null
              : (next) {
                  if (next != null) {
                    context.read<EntryAgentsCubit>().setFieldAccess(id, next);
                  }
                },
        ),
      ],
    );
  }

  String _accessLabel(BuildContext context, AgentFieldAccess value) {
    final l10n = AppLocalizations.of(context)!;
    return switch (value) {
      AgentFieldAccess.never => l10n.entryAgentsAccessNever,
      AgentFieldAccess.discovery => l10n.entryAgentsAccessDiscovery,
      AgentFieldAccess.onGrantValue => l10n.entryAgentsAccessGrantValue,
      AgentFieldAccess.onGrantDerived => l10n.entryAgentsAccessGrantDerived,
      AgentFieldAccess.onGrantRuntime => l10n.entryAgentsAccessGrantRuntime,
    };
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.text,
    required this.action,
    required this.onAction,
  });

  final String text;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text),
        TextButton(onPressed: onAction, child: Text(action)),
      ],
    ),
  );
}
