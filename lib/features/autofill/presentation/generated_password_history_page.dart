import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/injection.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/secure_clipboard.dart';
import '../../../core/widgets/app_bar_title.dart';
import '../../../core/widgets/app_screen.dart';
import '../../../core/widgets/fab_registrar.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../../vault/domain/entities/vault_entity.dart';
import '../../vault/presentation/cubit/vault_list_cubit.dart';
import '../../vault/presentation/pages/add_entry_page.dart';
import '../../vault/presentation/widgets/choose_entry_vault_sheet.dart';
import '../data/generated_password_history_bridge.dart';

class GeneratedPasswordHistoryPage extends StatefulWidget {
  const GeneratedPasswordHistoryPage({super.key});

  @override
  State<GeneratedPasswordHistoryPage> createState() =>
      _GeneratedPasswordHistoryPageState();
}

class _GeneratedPasswordHistoryPageState
    extends State<GeneratedPasswordHistoryPage>
    with WidgetsBindingObserver {
  final _bridge = GeneratedPasswordHistoryBridge();
  List<GeneratedPasswordSummary> _records = const [];
  String? _visibleId;
  String? _visiblePassword;
  Timer? _hideTimer;
  bool _loading = true;
  bool _unavailable = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _hidePassword();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _visiblePassword = null;
    super.dispose();
  }

  String? get _principalId {
    final auth = context.read<AuthBloc>().state;
    return auth is AuthAuthenticated &&
            !auth.isVaultLocked &&
            auth.privateKey != null
        ? auth.userId
        : null;
  }

  Future<void> _load() async {
    final principal = _principalId;
    if (principal == null) return;
    setState(() {
      _loading = true;
      _unavailable = false;
    });
    try {
      final records = await _bridge.list(
        principal,
        biometricPrompt: AppLocalizations.of(
          context,
        )!.generatedPasswordBiometric,
      );
      if (!mounted || _principalId != principal) return;
      setState(() {
        _records = records.reversed.toList(growable: false);
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _unavailable = true;
        });
      }
    }
  }

  void _hidePassword() {
    _hideTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _visibleId = null;
      _visiblePassword = null;
    });
  }

  Future<String?> _reveal(GeneratedPasswordSummary record) async {
    final principal = _principalId;
    if (principal == null) return null;
    try {
      final password = await _bridge.reveal(
        principal,
        record.id,
        biometricPrompt: AppLocalizations.of(
          context,
        )!.generatedPasswordBiometric,
      );
      if (!mounted || _principalId != principal) return null;
      return password;
    } catch (_) {
      _showUnavailable();
      return null;
    }
  }

  Future<void> _show(GeneratedPasswordSummary record) async {
    final password = await _reveal(record);
    if (password == null) return;
    _hideTimer?.cancel();
    setState(() {
      _visibleId = record.id;
      _visiblePassword = password;
    });
    _hideTimer = Timer(const Duration(seconds: 30), _hidePassword);
  }

  Future<void> _copy(GeneratedPasswordSummary record) async {
    final password = await _reveal(record);
    if (password == null) return;
    await SecureClipboard.copy(password);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.generatedPasswordCopied),
        ),
      );
    }
  }

  Future<void> _saveToVault(GeneratedPasswordSummary record) async {
    final principal = _principalId;
    if (principal == null) return;
    final auth = context.read<AuthBloc>().state as AuthAuthenticated;
    final vaults = getIt<VaultListCubit>();
    await vaults.loadIfNeeded(auth.privateKey);
    if (!mounted || _principalId != principal) return;
    final vault = await showModalBottomSheet<VaultEntity>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: AppColors.modalBackground(Theme.of(context).brightness),
      builder: (_) => BlocProvider<VaultListCubit>.value(
        value: vaults,
        child: ChooseEntryVaultSheet(
          onCreateFirstVault: () {
            Navigator.of(context, rootNavigator: true).pop();
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
    if (!mounted || vault == null || _principalId != principal) return;
    final password = await _reveal(record);
    if (!mounted || password == null) return;
    _hidePassword();
    await AddEntryPage.push(
      context,
      vaultId: vault.id,
      vaultName: vault.name,
      wrappedVK: vault.wrappedVK,
      initialDomain: record.domain,
      initialPassword: password,
    );
  }

  Future<void> _delete(GeneratedPasswordSummary record) async {
    final principal = _principalId;
    if (principal == null) return;
    final l10n = AppLocalizations.of(context)!;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.generatedPasswordDeleteTitle),
        content: Text(l10n.generatedPasswordDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.generatedPasswordCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.generatedPasswordDelete),
          ),
        ],
      ),
    );
    if (approved != true || !mounted || _principalId != principal) return;
    try {
      await _bridge.delete(
        principal,
        record.id,
        biometricPrompt: l10n.generatedPasswordBiometric,
      );
      if (!mounted || _principalId != principal) return;
      _hidePassword();
      setState(
        () =>
            _records = _records.where((item) => item.id != record.id).toList(),
      );
    } catch (_) {
      _showUnavailable();
    }
  }

  Future<void> _clearAll() async {
    final principal = _principalId;
    if (principal == null || _records.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.generatedPasswordClearTitle),
        content: Text(l10n.generatedPasswordClearBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.generatedPasswordCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.generatedPasswordClear),
          ),
        ],
      ),
    );
    if (approved != true || !mounted || _principalId != principal) return;
    try {
      await _bridge.clear(
        principal,
        biometricPrompt: l10n.generatedPasswordBiometric,
      );
      if (!mounted || _principalId != principal) return;
      _hidePassword();
      setState(() => _records = const []);
    } catch (_) {
      _showUnavailable();
    }
  }

  void _showUnavailable() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(context)!.generatedPasswordUnavailable,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return BlocListener<AuthBloc, AuthState>(
      listener: (_, state) {
        if (state is! AuthAuthenticated || state.isVaultLocked) {
          _hidePassword();
          setState(() => _records = const []);
        }
      },
      child: AppScreen.appBar(
        floatingActionButton: const FabRegistrar(fab: null),
        appBar: AppBar(
          titleSpacing: 0,
          centerTitle: false,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          title: AppBarTitle(title: l10n.generatedPasswordTitle),
          actions: [
            if (_records.isNotEmpty)
              IconButton(
                onPressed: _clearAll,
                icon: const Icon(Icons.delete_sweep_outlined),
                tooltip: l10n.generatedPasswordClear,
              ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _unavailable
            ? Center(child: Text(l10n.generatedPasswordUnavailable))
            : _records.isEmpty
            ? Center(child: Text(l10n.generatedPasswordEmpty))
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenH,
                  0,
                  AppSpacing.screenH,
                  AppSpacing.screenBottom,
                ),
                itemCount: _records.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.cardGap),
                itemBuilder: (context, index) {
                  final record = _records[index];
                  final date = MaterialLocalizations.of(
                    context,
                  ).formatMediumDate(record.createdAt);
                  final visible = _visibleId == record.id;
                  return Card(
                    color: AppColors.cardFill(brightness),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.cardPadding),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            record.domain,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            date,
                            style: TextStyle(
                              color: AppColors.onSurfaceMuted(brightness),
                            ),
                          ),
                          if (visible) ...[
                            const SizedBox(height: AppSpacing.sm),
                            Text(_visiblePassword!),
                          ],
                          Wrap(
                            spacing: AppSpacing.sm,
                            children: [
                              TextButton(
                                onPressed: () =>
                                    visible ? _hidePassword() : _show(record),
                                child: Text(
                                  visible
                                      ? l10n.generatedPasswordHide
                                      : l10n.generatedPasswordReveal,
                                ),
                              ),
                              TextButton(
                                onPressed: () => _copy(record),
                                child: Text(l10n.generatedPasswordCopy),
                              ),
                              TextButton(
                                onPressed: () => _saveToVault(record),
                                child: Text(l10n.generatedPasswordSave),
                              ),
                              TextButton(
                                onPressed: () => _delete(record),
                                child: Text(l10n.generatedPasswordDelete),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
