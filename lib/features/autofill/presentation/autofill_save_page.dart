import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/injection.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_action_footer.dart';
import '../../../core/widgets/app_bar_title.dart';
import '../../../core/widgets/app_dropdown_field.dart';
import '../../../core/widgets/app_screen.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../../onboarding/presentation/widgets/onboarding_text_field.dart';
import '../../vault/data/services/key_entry_creation_service.dart';
import '../../vault/domain/entities/vault_entity.dart';
import '../../vault/presentation/cubit/vault_list_cubit.dart';
import '../../vault/presentation/widgets/choose_entry_vault_sheet.dart';
import '../../vault/presentation/widgets/entry_form_widgets.dart';
import '../data/autofill_save_controller.dart';

class AutoFillSavePage extends StatefulWidget {
  const AutoFillSavePage({
    super.key,
    required this.controller,
    required this.draft,
  });
  final AutoFillSaveController controller;
  final AutoFillSaveDraft draft;
  @override
  State<AutoFillSavePage> createState() => _AutoFillSavePageState();
}

class _AutoFillSavePageState extends State<AutoFillSavePage>
    with WidgetsBindingObserver {
  final _label = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  String? _domain;
  VaultEntity? _vault;
  bool _busy = false;
  bool _failed = false;
  bool _closing = false;
  bool get _current => mounted && !_closing && widget.draft.valid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.draft.addListener(_changed);
    _username.text = widget.draft.username;
    _password.text = widget.draft.password;
    widget.draft.username = '';
    widget.draft.password = '';
    if (widget.draft.isWeb) _domain = widget.draft.domains.single;
    _label.text = _domain ?? widget.draft.packageName;
  }

  void _changed() {
    if (widget.draft.valid) return;
    _label.clear();
    _username.clear();
    _password.clear();
    if (!_closing && mounted) {
      _closing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).removeRoute(ModalRoute.of(context)!);
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      widget.controller.cancelDraft(widget.draft);
    }
  }

  @override
  void dispose() {
    _closing = true;
    WidgetsBinding.instance.removeObserver(this);
    widget.draft.removeListener(_changed);
    _label.clear();
    _username.clear();
    _password.clear();
    _label.dispose();
    _username.dispose();
    _password.dispose();
    widget.controller.cancelDraft(widget.draft);
    super.dispose();
  }

  Future<void> _chooseVault() async {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated || auth.isVaultLocked || !_current) return;
    final vaults = getIt<VaultListCubit>();
    await vaults.loadIfNeeded(auth.privateKey);
    if (!mounted || !_current) return;
    final selected = await showModalBottomSheet<VaultEntity>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: AppColors.modalBackground(Theme.of(context).brightness),
      builder: (sheetContext) => BlocProvider.value(
        value: vaults,
        child: ChooseEntryVaultSheet(
          onCreateFirstVault: () {
            Navigator.of(sheetContext).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  AppLocalizations.of(
                    context,
                  )!.generatedPasswordCreateVaultFirst,
                ),
              ),
            );
          },
        ),
      ),
    );
    if (_current && selected != null) setState(() => _vault = selected);
  }

  Future<void> _save() async {
    if (!_current ||
        _busy ||
        _vault == null ||
        _domain == null ||
        _label.text.trim().isEmpty ||
        _username.text.isEmpty ||
        _password.text.isEmpty) {
      return;
    }
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated ||
        auth.isVaultLocked ||
        auth.privateKey == null) {
      return;
    }
    final domain = _domain!;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      if (!await widget.controller.validate(widget.draft, domain) ||
          !_current) {
        widget.controller.cancelDraft(widget.draft);
        return;
      }
      await getIt<KeyEntryCreationService>().createCredential(
        vaultId: _vault!.id,
        label: _label.text.trim(),
        description: '',
        icon: '',
        content: {
          'type': 'CREDENTIAL', 'username': _username.text,
          'password': _password.text,
          // Native verified association is not evidence of HTTPS transport.
          'url': widget.draft.isWeb ? 'https://$domain' : domain,
        },
        memberPrivateKey: auth.privateKey!,
        exposeUsername: false,
        exposeDomain: false,
        isOperationCurrent: () => _current,
        validateOperation: () =>
            widget.controller.validate(widget.draft, domain),
      );
      if (mounted && _current) Navigator.of(context).pop();
    } catch (_) {
      if (_current) setState(() => _failed = true);
    } finally {
      if (_current) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AppScreen.appBar(
      appBar: AppBar(
        titleSpacing: 0,
        centerTitle: false,
        title: AppBarTitle(title: l10n.autoFillSaveTitle),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.screenH),
              children: [
                Text(
                  widget.draft.isWeb
                      ? l10n.autoFillSaveWebSource
                      : l10n.autoFillSaveNativeSource,
                ),
                Text(widget.draft.sourceLabel ?? widget.draft.packageName),
                const SizedBox(height: AppSpacing.fieldGap),
                if (widget.draft.isWeb)
                  Text('https://${widget.draft.domains.single}')
                else
                  AppDropdownField<String>(
                    label: l10n.autoFillSaveHost,
                    value: _domain,
                    hint: Text(l10n.autoFillSaveHost),
                    items: widget.draft.domains
                        .map(
                          (host) =>
                              DropdownMenuItem(value: host, child: Text(host)),
                        )
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _domain = value),
                  ),
                const SizedBox(height: AppSpacing.fieldGap),
                OnboardingTextField(
                  controller: _label,
                  label: l10n.entryLabelLabel,
                  enabled: !_busy,
                ),
                const SizedBox(height: AppSpacing.fieldGap),
                OnboardingTextField(
                  controller: _username,
                  label: l10n.entryUsernameLabel,
                  enabled: !_busy,
                  autocorrect: false,
                  enableSuggestions: false,
                ),
                const SizedBox(height: AppSpacing.fieldGap),
                OnboardingTextField(
                  controller: _password,
                  label: l10n.entryPasswordLabel,
                  enabled: !_busy,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                ),
                const SizedBox(height: AppSpacing.fieldGap),
                TextButton(
                  onPressed: _busy ? null : _chooseVault,
                  child: Text(_vault?.name ?? l10n.globalEntriesChooseVault),
                ),
                if (_failed) Text(l10n.autoFillSaveUnavailable),
              ],
            ),
          ),
          AppActionFooter(
            child: EntrySaveButton(
              isLoading: _busy,
              onPressed: _vault != null && _domain != null && widget.draft.valid
                  ? _save
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
