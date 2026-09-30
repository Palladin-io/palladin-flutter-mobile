import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_dropdown_field.dart';
import '../../../../core/widgets/skeleton_box.dart';
import '../../../../core/widgets/warning_zone.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../onboarding/presentation/widgets/onboarding_text_field.dart';
import '../../data/services/entry_sharing/entry_share_copy_projection_service.dart';
import '../../domain/entities/entry_share.dart';
import '../../domain/entities/entry_share_copy.dart';
import '../cubit/entry_share_copy_cubit.dart';
import 'entry_share_creation_form.dart';

class EntryShareCopyPanel extends StatefulWidget {
  const EntryShareCopyPanel({
    super.key,
    required this.cubit,
    required this.snapshot,
    required this.onCancel,
    required this.onSaved,
  });
  final EntryShareCopyCubit cubit;
  final EntryShareSnapshot snapshot;
  final VoidCallback onCancel, onSaved;

  @override
  State<EntryShareCopyPanel> createState() => _EntryShareCopyPanelState();
}

class _EntryShareCopyPanelState extends State<EntryShareCopyPanel> {
  late final TextEditingController _title;
  late final Map<String, TextEditingController> _fields;
  late final StreamSubscription<EntryShareCopyState> _subscription;
  List<EntryShareCopyDestination> _vaults = const [];
  bool _unavailableVaults = false;
  String? _selected;
  bool _loading = false, _loadFailed = false, _missing = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.snapshot.title);
    _fields = {
      for (final id in const EntryShareCopyProjectionService().missingFields(
        widget.snapshot,
      ))
        id: TextEditingController(),
    };
    _subscription = widget.cubit.stream.listen((state) {
      if ({
        EntryShareCopyPhase.saving,
        EntryShareCopyPhase.retry,
        EntryShareCopyPhase.saved,
        EntryShareCopyPhase.unavailable,
      }.contains(state.phase)) {
        _clearInputs();
      }
      if (state.phase == EntryShareCopyPhase.unavailable) {
        _generation++;
        _vaults = const [];
        _selected = null;
      }
    });
    unawaited(_load());
  }

  bool _live(int generation) =>
      mounted &&
      generation == _generation &&
      widget.cubit.state.phase != EntryShareCopyPhase.unavailable;

  Future<void> _load() async {
    if (_loading) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      if (!await widget.cubit.revalidate() || !_live(generation)) return;
      final vaults = await widget.cubit.loadDestinations();
      if (!await widget.cubit.revalidate() || !_live(generation)) return;
      setState(() {
        _vaults = vaults.items;
        _unavailableVaults = vaults.unavailable > 0;
        _selected = null;
      });
    } catch (_) {
      if (await widget.cubit.revalidate() && _live(generation)) {
        setState(() => _loadFailed = true);
      }
    } finally {
      if (_live(generation)) setState(() => _loading = false);
    }
  }

  void _clearInputs() {
    _title.clear();
    for (final field in _fields.values) {
      field.clear();
    }
  }

  Future<void> _createPersonalVault() async {
    final generation = _generation;
    final reload = await widget.cubit.createPersonalVault(
      AppLocalizations.of(context)!.defaultVaultName,
    );
    if (reload && _live(generation)) await _load();
  }

  @override
  void dispose() {
    _generation++;
    _clearInputs();
    _title.dispose();
    for (final field in _fields.values) {
      field.dispose();
    }
    _fields.clear();
    _vaults = const [];
    unawaited(_subscription.cancel());
    unawaited(widget.cubit.close());
    super.dispose();
  }

  void _save() {
    if (widget.cubit.state.phase != EntryShareCopyPhase.editing ||
        _selected == null) {
      return;
    }
    final missing = _fields.values.any((field) => field.text.isEmpty);
    setState(() => _missing = missing);
    if (missing) return;
    FocusScope.of(context).unfocus();
    unawaited(
      widget.cubit.save(
        vaultId: _selected!,
        title: _title.text,
        completedFields: {
          for (final field in _fields.entries) field.key: field.value.text,
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    const gap = SizedBox(height: AppSpacing.fieldGap);
    return BlocBuilder<EntryShareCopyCubit, EntryShareCopyState>(
      bloc: widget.cubit,
      builder: (context, state) {
        if (state.phase == EntryShareCopyPhase.unavailable) {
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.screenH),
            child: Text(l10n.sharingReceiveUnavailable),
          );
        }
        final editing = state.phase == EntryShareCopyPhase.editing;
        final busy =
            state.phase == EntryShareCopyPhase.creatingVault ||
            state.phase == EntryShareCopyPhase.preparing ||
            state.phase == EntryShareCopyPhase.saving;
        final retry = state.phase == EntryShareCopyPhase.retry;
        final saved = state.phase == EntryShareCopyPhase.saved;
        return Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.screenH),
                children: [
                  Text(
                    l10n.sharingSaveCopy,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  gap,
                  if (saved)
                    Text(l10n.sharingCopySaved)
                  else if (retry || state.phase == EntryShareCopyPhase.saving)
                    Text(l10n.sharingCopyRetryNotice)
                  else ...[
                    Text(l10n.sharingCopyNotice),
                    gap,
                    if (_loading) ...[
                      const SkeletonBox(height: AppSpacing.controlHeight),
                      gap,
                    ] else if (_loadFailed) ...[
                      Text(l10n.sharingCopyVaultError),
                      TextButton(
                        onPressed: editing ? _load : null,
                        child: Text(l10n.sharingRefresh),
                      ),
                      gap,
                    ] else if (_vaults.isEmpty) ...[
                      Text(l10n.sharingCopyNoVault),
                      if (widget.cubit.canCreatePersonalVault ||
                          state.phase == EntryShareCopyPhase.creatingVault) ...[
                        gap,
                        Text(l10n.sharingCopyCreateVaultNotice),
                        TextButton(
                          onPressed: editing ? _createPersonalVault : null,
                          child: Text(l10n.sharingCopyCreateVault),
                        ),
                      ],
                      if (state.vaultCreationFailed)
                        Text(
                          l10n.sharingCopyCreateVaultError,
                          style: const TextStyle(color: AppColors.brandRed),
                        ),
                      gap,
                    ] else ...[
                      AppDropdownField<String>(
                        key: const ValueKey('sharing-copy-vault'),
                        label: l10n.sharingCopyVault,
                        value: _selected,
                        hint: Text(l10n.sharingCopyChooseVault),
                        enabled: editing,
                        items: [
                          for (final vault in _vaults)
                            DropdownMenuItem(
                              value: vault.id,
                              child: Text(
                                vault.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) => setState(() => _selected = value),
                      ),
                      gap,
                    ],
                    WarningZone(
                      title: l10n.sharingCopyAccessTitle,
                      message: l10n.sharingCopyAccessNotice,
                    ),
                    if (_unavailableVaults) ...[
                      gap,
                      Text(l10n.sharingCopyCorruptVaults),
                    ],
                    gap,
                    OnboardingTextField(
                      key: const ValueKey('sharing-copy-title'),
                      controller: _title,
                      label: l10n.entryLabelLabel,
                      enabled: editing,
                      feedbackReserveSpace: false,
                      feedbackVisible:
                          state.inputError ==
                          EntryShareCopyInputError.invalidTitle,
                      feedbackChild: Text(
                        l10n.sharingCopyTitleError,
                        style: const TextStyle(
                          color: AppColors.brandRed,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    gap,
                    if (_fields.isNotEmpty) ...[
                      Text(l10n.sharingCopyMissingNotice),
                      gap,
                    ],
                    for (final field in _fields.entries) ...[
                      OnboardingTextField(
                        key: ValueKey('sharing-copy-${field.key}'),
                        controller: field.value,
                        label: field.key == 'script.execution.description'
                            ? l10n.sharingCopyScriptDescription
                            : entryShareFieldLabel(l10n, field.key, ''),
                        enabled: editing,
                        obscureText: {
                          'credential.password',
                          'key.value',
                          'creditCard.cardNumber',
                        }.contains(field.key),
                        maxLines:
                            field.key == 'script.source' ||
                                field.key == 'script.execution.description'
                            ? 3
                            : 1,
                        feedbackReserveSpace: false,
                        feedbackVisible: _missing && field.value.text.isEmpty,
                        feedbackChild: Text(
                          l10n.sharingCopyRequired,
                          style: const TextStyle(
                            color: AppColors.brandRed,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      gap,
                    ],
                    if (state.inputError != null &&
                        state.inputError !=
                            EntryShareCopyInputError.invalidTitle)
                      Text(
                        _inputError(l10n, state.inputError!),
                        style: const TextStyle(color: AppColors.brandRed),
                      ),
                    if (state.failed)
                      Text(
                        l10n.sharingCopySaveError,
                        style: const TextStyle(color: AppColors.brandRed),
                      ),
                    TextButton(
                      onPressed: editing ? widget.onCancel : null,
                      child: Text(l10n.sharingCopyBack),
                    ),
                  ],
                  if (saved)
                    TextButton(
                      onPressed: widget.onSaved,
                      child: Text(l10n.sharingCopyBack),
                    ),
                  Text(
                    l10n.sharingCopySessionNotice,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.onSurfaceSubtle(brightness),
                    ),
                  ),
                ],
              ),
            ),
            if (!saved)
              EntryShareActionFooter(
                label: state.phase == EntryShareCopyPhase.creatingVault
                    ? l10n.sharingCopyCreateVault
                    : retry
                    ? l10n.sharingRetryCreate
                    : l10n.sharingSaveCopy,
                busy: busy,
                onPressed: retry
                    ? () => unawaited(widget.cubit.retry())
                    : editing && !_loading && !_loadFailed && _selected != null
                    ? _save
                    : null,
              ),
          ],
        );
      },
    );
  }

  String _inputError(AppLocalizations l10n, EntryShareCopyInputError error) =>
      switch (error) {
        EntryShareCopyInputError.invalidTitle => l10n.sharingCopyTitleError,
        EntryShareCopyInputError.missingFields => l10n.sharingCopyRequired,
        EntryShareCopyInputError.invalidScript => l10n.sharingCopyScriptError,
        _ => l10n.sharingCopyUnsupported,
      };
}
