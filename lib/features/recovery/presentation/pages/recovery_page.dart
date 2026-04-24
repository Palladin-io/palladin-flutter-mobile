import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/analytics/analytics_service.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../onboarding/presentation/widgets/onboarding_text_field.dart';
import '../../../onboarding/presentation/widgets/primary_button.dart';
import '../../domain/recovery_exceptions.dart';
import '../cubit/recovery_cubit.dart';

/// Internal step of the account-recovery wizard.
///
/// Driven by local state on [_RecoveryView] rather than cubit state so
/// that transient loading/error emissions from [RecoveryCubit] don't
/// push the user back to step 1 on every rebuild.
enum _RecoveryStep {
  /// Step 1 — user enters / pastes / imports their 24-word mnemonic.
  enterKey,

  /// Step 2 — user picks a new master password.
  newPassword,

  /// Step 3 — user is shown the freshly generated recovery mnemonic
  /// and must confirm they saved it before leaving the flow.
  saveNewKey,
}

/// Account Recovery wizard.
///
/// Three-step flow:
///   1. User types, pastes, or imports a 24-word recovery mnemonic. We
///      validate it client-side by attempting to unwrap the private key
///      and advance only on success.
///   2. User picks a new master password (with confirmation). The full
///      recovery pipeline runs: derive fresh MK, re-wrap private key,
///      generate a new mnemonic, derive a new RK, re-wrap again, then
///      PUT everything to `/api/account/recovery`.
///   3. Display the new mnemonic with copy / export affordances; user
///      must tick a "I saved it" checkbox to finish.
///
/// Analytics:
///   * `mb:recovery:page-viewed`         on mount
///   * `mb:recovery:recovery-started`    after step 1 validation submit
///   * `mb:recovery:recovery-failed`     on any failure at any step
///   * `mb:recovery:recovery-completed`  on "Finish" tap
class RecoveryPage extends StatelessWidget {
  const RecoveryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<RecoveryCubit>(
      create: (_) => getIt<RecoveryCubit>(),
      child: const _RecoveryView(),
    );
  }
}

class _RecoveryView extends StatefulWidget {
  const _RecoveryView();

  @override
  State<_RecoveryView> createState() => _RecoveryViewState();
}

class _RecoveryViewState extends State<_RecoveryView> {
  _RecoveryStep _step = _RecoveryStep.enterKey;

  final _mnemonicController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _passwordVisible = false;
  bool _confirmVisible = false;

  /// Local validation error on step 2 — shown when the two password
  /// fields disagree. Kept out of cubit state since it's purely a UI
  /// concern (no crypto/network touched).
  bool _passwordMismatch = false;

  /// Step-3 gate: user must tick the checkbox before "Finish" enables.
  bool _newKeySaved = false;

  /// Freshly generated mnemonic captured from [RecoveryCompleted] so we
  /// can render step 3 without depending on cubit state (which may
  /// rebuild back to Initial).
  List<String> _newMnemonic = const [];

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.capture('recovery', 'page-viewed');
    _mnemonicController.addListener(_onTextChanged);
    _passwordController.addListener(_onTextChanged);
    _confirmPasswordController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _mnemonicController.removeListener(_onTextChanged);
    _passwordController.removeListener(_onTextChanged);
    _confirmPasswordController.removeListener(_onTextChanged);
    _mnemonicController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    // Re-render the enabled/disabled state of the primary button and
    // clear any "passwords do not match" error as soon as the user
    // starts editing again.
    setState(() {
      if (_passwordMismatch &&
          _passwordController.text == _confirmPasswordController.text) {
        _passwordMismatch = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<RecoveryCubit, RecoveryState>(
      listener: _handleStateChange,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Container(
          decoration: const BoxDecoration(
            gradient: AppColors.darkBackgroundGradient,
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: _buildStep(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep(BuildContext context) {
    switch (_step) {
      case _RecoveryStep.enterKey:
        return _EnterKeyStep(
          controller: _mnemonicController,
          onPaste: _pasteFromClipboard,
          onImport: _importFromFile,
          onSubmit: _submitMnemonic,
        );
      case _RecoveryStep.newPassword:
        return _NewPasswordStep(
          passwordController: _passwordController,
          confirmController: _confirmPasswordController,
          passwordVisible: _passwordVisible,
          confirmVisible: _confirmVisible,
          onTogglePassword: () =>
              setState(() => _passwordVisible = !_passwordVisible),
          onToggleConfirm: () =>
              setState(() => _confirmVisible = !_confirmVisible),
          passwordMismatch: _passwordMismatch,
          onBack: _goBackToEnterKey,
          onSubmit: _submitNewPassword,
        );
      case _RecoveryStep.saveNewKey:
        return _SaveNewKeyStep(
          mnemonic: _newMnemonic,
          saved: _newKeySaved,
          onSavedChanged: (v) => setState(() => _newKeySaved = v ?? false),
          onFinish: _finish,
        );
    }
  }

  // ─── step transitions ────────────────────────────────────────────────

  void _submitMnemonic() {
    final mnemonic = _mnemonicController.text.trim();
    if (mnemonic.isEmpty) return;
    AnalyticsService.instance.capture('recovery', 'recovery-started');
    FocusScope.of(context).unfocus();
    context.read<RecoveryCubit>().validateAndProceed(mnemonic);
  }

  void _submitNewPassword() {
    final password = _passwordController.text;
    final confirm = _confirmPasswordController.text;
    if (password.isEmpty) return;
    if (password != confirm) {
      setState(() => _passwordMismatch = true);
      return;
    }
    setState(() => _passwordMismatch = false);
    FocusScope.of(context).unfocus();
    context.read<RecoveryCubit>().completeRecovery(password);
  }

  void _goBackToEnterKey() {
    // Reset mnemonic so the user can type a different one if they
    // realised step 1 was wrong. Also drop any stale cubit error/loading
    // state so the previously-visited step doesn't re-render with a
    // lingering error banner.
    context.read<RecoveryCubit>().reset();
    setState(() {
      _step = _RecoveryStep.enterKey;
      _passwordController.clear();
      _confirmPasswordController.clear();
      _passwordMismatch = false;
    });
  }

  void _finish() {
    AnalyticsService.instance.capture('recovery', 'recovery-completed');
    // Route back to unlock — the user will sign in with their freshly
    // chosen master password. The router redirects "authenticated +
    // locked" sessions to /unlock so this is a natural landing point.
    context.go('/unlock');
  }

  // ─── cubit listener ──────────────────────────────────────────────────

  void _handleStateChange(BuildContext context, RecoveryState state) {
    if (state is RecoveryKeyValidated) {
      setState(() {
        _step = _RecoveryStep.newPassword;
      });
    } else if (state is RecoveryCompleted) {
      setState(() {
        _step = _RecoveryStep.saveNewKey;
        _newMnemonic = List<String>.from(state.newRecoveryMnemonic);
        _newKeySaved = false;
      });
    } else if (state is RecoveryFailed) {
      AnalyticsService.instance.capture(
        'recovery',
        'recovery-failed',
        properties: {'reason': _failureReason(state.error)},
      );
    }
  }

  String _failureReason(Object error) {
    if (error is WrongRecoveryKeyException) return 'wrong_recovery_key';
    if (error is RecoveryMaterialMissingException) return 'material_missing';
    if (error is RecoveryServerException) return 'server_error';
    return 'unknown';
  }

  // ─── clipboard / file import helpers ─────────────────────────────────

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final text = data?.text;
    if (text == null || text.trim().isEmpty) return;
    _mnemonicController.text = _normaliseMnemonic(text);
    _mnemonicController.selection = TextSelection.fromPosition(
      TextPosition(offset: _mnemonicController.text.length),
    );
  }

  Future<void> _importFromFile() async {
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.recoveryImportComingSoon),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  /// Collapses arbitrary whitespace/newlines/numbered lines into a
  /// single space-separated mnemonic. Handles both plain pastes
  /// (`"word word word"`) and the `"1. word"` format exported by the
  /// onboarding flow.
  String _normaliseMnemonic(String raw) {
    final tokens = raw
        .split(RegExp(r'\s+'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        // Drop purely numeric tokens like "1." or "12" that come from
        // exported numbered lists.
        .where((t) => !RegExp(r'^\d+\.?$').hasMatch(t))
        // Strip a leading number-dot prefix ("1.word") if present.
        .map((t) => t.replaceFirst(RegExp(r'^\d+\.'), ''))
        .where((t) => t.isNotEmpty);
    return tokens.join(' ');
  }
}

// ─────────────────────────────────────────────────────────────────────
// Step 1 — enter recovery key
// ─────────────────────────────────────────────────────────────────────

class _EnterKeyStep extends StatelessWidget {
  const _EnterKeyStep({
    required this.controller,
    required this.onPaste,
    required this.onImport,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final VoidCallback onPaste;
  final VoidCallback onImport;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BlocBuilder<RecoveryCubit, RecoveryState>(
      builder: (context, state) {
        final isLoading = state is RecoveryLoading;
        final hasError = state is RecoveryFailed;
        final hasText = controller.text.trim().isNotEmpty;
        final canSubmit = !isLoading && hasText;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              onBack: () => context.go('/unlock'),
              title: l10n.recoveryTitle,
              subtitle: l10n.recoverySubtitle,
            ),
            const SizedBox(height: 24),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _MnemonicTextArea(
                      controller: controller,
                      hintText: l10n.recoveryEnterKeyLabel,
                      hasError: hasError,
                    ),
                    if (hasError) ...[
                      const SizedBox(height: 8),
                      Text(
                        _errorMessage(context, state.error),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.brandRed,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _SecondaryButton(
              icon: Icons.content_paste_outlined,
              label: l10n.recoveryPasteButton,
              onPressed: isLoading ? null : onPaste,
            ),
            const SizedBox(height: 8),
            _SecondaryButton(
              icon: Icons.file_upload_outlined,
              label: l10n.recoveryImportButton,
              onPressed: isLoading ? null : onImport,
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: l10n.onboardingContinue,
              isLoading: isLoading,
              onPressed: canSubmit ? onSubmit : null,
            ),
          ],
        );
      },
    );
  }

  String _errorMessage(BuildContext context, Object error) {
    final l10n = AppLocalizations.of(context)!;
    if (error is WrongRecoveryKeyException) return l10n.recoveryWrongKey;
    if (error is RecoveryMaterialMissingException) {
      return l10n.recoveryMaterialMissing;
    }
    if (error is RecoveryServerException) {
      return switch (error.kind) {
        RecoveryServerErrorKind.serverNotResponding =>
          l10n.errorServerNotResponding,
        RecoveryServerErrorKind.cannotConnect =>
          l10n.errorCannotConnectToServer,
        RecoveryServerErrorKind.connectionFailed =>
          l10n.errorConnectionFailed,
        RecoveryServerErrorKind.invalidResponse =>
          l10n.errorInvalidServerResponse,
      };
    }
    return l10n.recoveryServerError;
  }
}

class _MnemonicTextArea extends StatelessWidget {
  const _MnemonicTextArea({
    required this.controller,
    required this.hintText,
    required this.hasError,
  });

  final TextEditingController controller;
  final String hintText;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final borderColor = hasError ? AppColors.brandRed : Colors.transparent;
    final focusColor = hasError ? AppColors.brandRed : AppColors.tealAccent;

    return TextField(
      controller: controller,
      maxLines: 6,
      minLines: 6,
      autocorrect: false,
      enableSuggestions: false,
      textCapitalization: TextCapitalization.none,
      textInputAction: TextInputAction.newline,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, height: 1.5),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(color: AppColors.textHint),
        filled: true,
        fillColor: AppColors.darkSurface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: hasError
              ? BorderSide(color: borderColor, width: 1)
              : BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: focusColor, width: 1.5),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Step 2 — set new master password
// ─────────────────────────────────────────────────────────────────────

class _NewPasswordStep extends StatelessWidget {
  const _NewPasswordStep({
    required this.passwordController,
    required this.confirmController,
    required this.passwordVisible,
    required this.confirmVisible,
    required this.onTogglePassword,
    required this.onToggleConfirm,
    required this.passwordMismatch,
    required this.onBack,
    required this.onSubmit,
  });

  final TextEditingController passwordController;
  final TextEditingController confirmController;
  final bool passwordVisible;
  final bool confirmVisible;
  final VoidCallback onTogglePassword;
  final VoidCallback onToggleConfirm;
  final bool passwordMismatch;
  final VoidCallback onBack;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BlocBuilder<RecoveryCubit, RecoveryState>(
      builder: (context, state) {
        final isLoading = state is RecoveryLoading;
        final hasServerError = state is RecoveryFailed;
        final password = passwordController.text;
        final confirm = confirmController.text;
        final canSubmit = !isLoading &&
            password.isNotEmpty &&
            confirm.isNotEmpty;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              onBack: isLoading ? null : onBack,
              title: l10n.recoveryNewPasswordTitle,
              subtitle: l10n.recoveryNewPasswordSubtitle,
            ),
            const SizedBox(height: 24),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OnboardingTextField(
                      label: l10n.recoveryNewPasswordLabel,
                      controller: passwordController,
                      obscureText: !passwordVisible,
                      suffixIcon: IconButton(
                        icon: Icon(
                          passwordVisible
                              ? Icons.visibility_off
                              : Icons.visibility,
                          size: 20,
                          color: AppColors.iconMuted,
                        ),
                        onPressed: onTogglePassword,
                      ),
                    ),
                    const SizedBox(height: 16),
                    OnboardingTextField(
                      label: l10n.recoveryConfirmPasswordLabel,
                      controller: confirmController,
                      obscureText: !confirmVisible,
                      borderColor: passwordMismatch
                          ? AppColors.brandRed
                          : null,
                      focusBorderColor: passwordMismatch
                          ? AppColors.brandRed
                          : null,
                      feedbackVisible: passwordMismatch,
                      feedbackChild: passwordMismatch
                          ? Text(
                              l10n.recoveryPasswordMismatch,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.brandRed,
                              ),
                            )
                          : const SizedBox.shrink(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          confirmVisible
                              ? Icons.visibility_off
                              : Icons.visibility,
                          size: 20,
                          color: AppColors.iconMuted,
                        ),
                        onPressed: onToggleConfirm,
                      ),
                    ),
                    if (hasServerError) ...[
                      const SizedBox(height: 12),
                      Text(
                        _errorMessage(context, state.error),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.brandRed,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            PrimaryButton(
              label: l10n.recoveryRecoverButton,
              isLoading: isLoading,
              onPressed: canSubmit ? onSubmit : null,
            ),
          ],
        );
      },
    );
  }

  String _errorMessage(BuildContext context, Object error) {
    final l10n = AppLocalizations.of(context)!;
    if (error is WrongRecoveryKeyException) return l10n.recoveryWrongKey;
    if (error is RecoveryMaterialMissingException) {
      return l10n.recoveryMaterialMissing;
    }
    if (error is RecoveryServerException) {
      return switch (error.kind) {
        RecoveryServerErrorKind.serverNotResponding =>
          l10n.errorServerNotResponding,
        RecoveryServerErrorKind.cannotConnect =>
          l10n.errorCannotConnectToServer,
        RecoveryServerErrorKind.connectionFailed =>
          l10n.errorConnectionFailed,
        RecoveryServerErrorKind.invalidResponse =>
          l10n.errorInvalidServerResponse,
      };
    }
    return l10n.recoveryServerError;
  }
}

// ─────────────────────────────────────────────────────────────────────
// Step 3 — show new recovery key
// ─────────────────────────────────────────────────────────────────────

class _SaveNewKeyStep extends StatelessWidget {
  const _SaveNewKeyStep({
    required this.mnemonic,
    required this.saved,
    required this.onSavedChanged,
    required this.onFinish,
  });

  final List<String> mnemonic;
  final bool saved;
  final ValueChanged<bool?> onSavedChanged;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          onBack: null,
          title: l10n.recoverySaveKeyTitle,
          subtitle: l10n.onboardingRecoverySubtitle,
        ),
        const SizedBox(height: 24),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _WarningBanner(message: l10n.onboardingRecoveryWarning),
                const SizedBox(height: 16),
                _MnemonicGrid(words: mnemonic),
                const SizedBox(height: 16),
                _SecondaryButton(
                  icon: Icons.content_copy,
                  label: l10n.recoveryCopyButton,
                  onPressed: () => _copyToClipboard(context, l10n),
                ),
                const SizedBox(height: 8),
                _SecondaryButton(
                  icon: Icons.file_download_outlined,
                  label: l10n.onboardingRecoveryExport,
                  onPressed: () => _exportToFile(context),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Checkbox(
                      value: saved,
                      onChanged: onSavedChanged,
                      checkColor: AppColors.darkBackground,
                      activeColor: AppColors.tealAccent,
                    ),
                    Expanded(
                      child: Text(
                        l10n.recoverySaveKeyCheckbox,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        PrimaryButton(
          label: l10n.recoveryFinishButton,
          onPressed: saved ? onFinish : null,
        ),
      ],
    );
  }

  Future<void> _copyToClipboard(
    BuildContext context,
    AppLocalizations l10n,
  ) async {
    await Clipboard.setData(ClipboardData(text: mnemonic.join(' ')));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.onboardingRecoveryCopied),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Future<void> _exportToFile(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final content = mnemonic
        .asMap()
        .entries
        .map((e) => '${e.key + 1}. ${e.value}')
        .join('\n');
    final bytes = Uint8List.fromList(utf8.encode(content));

    // On iPad the share sheet needs a source rect — fall back to a
    // centered zero-rect when the context doesn't expose one (phones
    // ignore the value).
    final box = context.findRenderObject() as RenderBox?;
    final origin =
        box != null ? box.localToGlobal(Offset.zero) & box.size : Rect.zero;

    await Share.shareXFiles(
      [XFile.fromData(bytes, mimeType: 'text/plain')],
      fileNameOverrides: const ['clawvault-recovery-key.txt'],
      subject: l10n.recoveryShareSubject,
      sharePositionOrigin: origin,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Shared sub-widgets
// ─────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.onBack,
    required this.title,
    required this.subtitle,
  });

  final VoidCallback? onBack;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 28,
          child: onBack != null
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: GestureDetector(
                    onTap: onBack,
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.only(right: 12, top: 4, bottom: 4),
                      child: Icon(
                        Icons.arrow_back_ios_new,
                        color: AppColors.textSecondary,
                        size: 18,
                      ),
                    ),
                  ),
                )
              : null,
        ),
        const SizedBox(height: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textTertiary,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: OutlinedButton.icon(
        icon: Icon(icon, size: 16, color: AppColors.textPrimary),
        label: Text(
          label,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.transparent,
          side: const BorderSide(color: AppColors.buttonBorder),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        onPressed: onPressed,
      ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.warningBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.brandRed.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: AppColors.brandRed, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textPrimary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MnemonicGrid extends StatelessWidget {
  const _MnemonicGrid({required this.words});

  final List<String> words;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: words.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        childAspectRatio: 3.2,
      ),
      itemBuilder: (_, index) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: AppColors.textPrimary.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.textPrimary.withValues(alpha: 0.06),
            ),
          ),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              SizedBox(
                width: 18,
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textHintFaint,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  words[index],
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
