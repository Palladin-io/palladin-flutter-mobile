import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/secure_clipboard.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/auth_legal_footer.dart';
import '../../../../core/widgets/brand_hero.dart';
import '../../../../core/widgets/mnemonic_word_grid.dart';
import '../../../../core/widgets/warning_zone.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../onboarding/domain/mnemonic.dart';
import '../../../onboarding/domain/password_strength.dart';
import '../../../onboarding/presentation/widgets/onboarding_scaffold.dart';
import '../../../onboarding/presentation/widgets/onboarding_text_field.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../data/services/hibp_service.dart';
import '../../domain/password_auth_exceptions.dart';
import '../bloc/auth_bloc.dart';
import '../cubit/password_security_cubit.dart';
import '../cubit/register_cubit.dart';
import '../widgets/auth_brand_header.dart';
import '../widgets/password_security_status.dart';

/// Registration wizard: email + master password + recovery
/// mnemonic backup + confirmation, then `POST /api/auth/register`.
///
/// On success the freshly derived keys are handed to [AuthBloc] via
/// [PasswordSessionEstablished]; the router then forwards the user to the
/// email-verification gate.
class RegisterPage extends StatelessWidget {
  const RegisterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<RegisterCubit>(
      create: (_) => getIt<RegisterCubit>(),
      child: const _RegisterView(),
    );
  }
}

class _RegisterView extends StatelessWidget {
  const _RegisterView();

  @override
  Widget build(BuildContext context) {
    return BlocListener<RegisterCubit, RegisterState>(
      listenWhen: (p, c) =>
          p.step != c.step && c.step == RegisterStep.completed,
      listener: (context, state) {
        final keys = state.unlockKeys;
        if (keys != null) {
          context.read<AuthBloc>().add(
            PasswordSessionEstablished(
              masterKey: keys.masterKey,
              privateKey: keys.privateKey,
            ),
          );
          context.read<RegisterCubit>().clearUnlockKeys();
        }
      },
      child: BlocBuilder<RegisterCubit, RegisterState>(
        buildWhen: (p, c) => p.step != c.step || p.mnemonic != c.mnemonic,
        builder: (context, state) {
          return PopScope(
            canPop: state.step == RegisterStep.credentials,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) return;
              context.read<RegisterCubit>().goBack();
            },
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: KeyedSubtree(
                key: ValueKey(
                  state.step == RegisterStep.submitting
                      ? RegisterStep.recoveryKeyConfirm
                      : state.step,
                ),
                child: _pageForStep(state.step),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _pageForStep(RegisterStep step) {
    switch (step) {
      case RegisterStep.credentials:
        return const _CredentialsStep();
      case RegisterStep.recoveryKeyBackup:
        return const _RecoveryBackupStep();
      case RegisterStep.recoveryKeyConfirm:
      case RegisterStep.submitting:
        return const _RecoveryConfirmStep();
      case RegisterStep.completed:
        return const _CompletedPlaceholder();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────
// Step 1 — email + master password
// ─────────────────────────────────────────────────────────────────────

class _CredentialsStep extends StatefulWidget {
  const _CredentialsStep();

  @override
  State<_CredentialsStep> createState() => _CredentialsStepState();
}

class _CredentialsStepState extends State<_CredentialsStep> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _passwordVisible = false;
  bool _confirmVisible = false;
  bool _showEmailError = false;

  Timer? _emailValidationTimer;

  late final PasswordSecurityCubit _passwordSecurity;

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static const _emailValidationDelay = Duration(milliseconds: 500);

  @override
  void initState() {
    super.initState();
    _passwordSecurity = PasswordSecurityCubit(
      check: getIt<HibpService>().check,
    );
    final cubit = context.read<RegisterCubit>();
    if (cubit.state.email.isNotEmpty) _emailController.text = cubit.state.email;
    // Password draft lives on the cubit (never in observable state); pre-fill
    // it when the user navigates back to this step.
    final passwordDraft = cubit.passwordDraft;
    if (passwordDraft.isNotEmpty) {
      _passwordController.text = passwordDraft;
      _confirmController.text = passwordDraft;
      _passwordSecurity.checkPassword(passwordDraft);
    }
    _emailController.addListener(_onEmailChanged);
    _passwordController.addListener(_onPasswordChanged);
    _confirmController.addListener(_onChanged);
  }

  @override
  void dispose() {
    _emailValidationTimer?.cancel();
    _passwordSecurity.close();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  void _onEmailChanged() {
    _emailValidationTimer?.cancel();
    final email = _emailController.text.trim();
    setState(() => _showEmailError = false);
    if (email.isEmpty) return;

    _emailValidationTimer = Timer(_emailValidationDelay, () {
      if (!mounted || _emailController.text.trim() != email) return;
      setState(() => _showEmailError = !_emailPattern.hasMatch(email));
    });
  }

  void _onPasswordChanged() {
    _passwordSecurity.checkPassword(_passwordController.text);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PasswordSecurityCubit, PasswordSecurityState>(
      bloc: _passwordSecurity,
      builder: (context, securityState) =>
          _buildCredentials(context, securityState),
    );
  }

  Widget _buildCredentials(
    BuildContext context,
    PasswordSecurityState securityState,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmController.text;
    final emailValid = _emailPattern.hasMatch(email);
    final emailInvalid = _showEmailError && email.isNotEmpty && !emailValid;
    final strength = evaluatePasswordStrength(password);
    final passwordsMatch = password.isNotEmpty && password == confirm;
    final formError = emailInvalid
        ? l10n.authEmailInvalid
        : confirm.isNotEmpty && !passwordsMatch
        ? l10n.onboardingPasswordsDoNotMatch
        : null;
    final passwordFeedback = resolvePasswordSecurityFeedback(
      l10n: l10n,
      password: password,
      isAcceptable: strength.isAcceptable,
      securityState: securityState,
      message: formError,
      secureMessage: '',
    );
    final supportingText = passwordFeedback.text.isEmpty
        ? l10n.authRegisterSubtitle
        : passwordFeedback.text;
    final supportingColor = passwordFeedback.text.isEmpty
        ? AppColors.onSurfaceSubtle(Theme.of(context).brightness)
        : passwordFeedback.color;
    final canSubmit =
        emailValid &&
        strength.isAcceptable &&
        passwordsMatch &&
        !securityState.blocksSubmission;

    return OnboardingScaffold(
      currentStep: 0,
      title: '',
      subtitle: '',
      useAuthBrandLayout: true,
      header: const AuthBrandHeader(),
      contentTopSpacing: AuthBrandHeader.denseFormTopSpacing,
      showTitleBlock: false,
      centerFooterInRemainingSpace: true,
      footer: _registrationMessage(
        message: supportingText,
        messageColor: supportingColor,
        emphasized: passwordFeedback.text.isNotEmpty,
      ),
      bottom: const AuthLegalFooter(),
      children: [
        OnboardingTextField(
          label: l10n.authEmailLabel,
          controller: _emailController,
          hintText: l10n.authEmailHint,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          borderColor: emailInvalid ? AppColors.brandRed : null,
          focusBorderColor: emailInvalid ? AppColors.brandRed : null,
        ),
        const SizedBox(height: AppSpacing.fieldGap),
        OnboardingTextField(
          label: l10n.authPasswordLabel,
          controller: _passwordController,
          obscureText: !_passwordVisible,
          suffixIcon: _visibilityToggle(
            _passwordVisible,
            () => setState(() => _passwordVisible = !_passwordVisible),
          ),
        ),
        const SizedBox(height: AppSpacing.fieldGap),
        OnboardingTextField(
          label: l10n.authRegisterConfirmLabel,
          controller: _confirmController,
          obscureText: !_confirmVisible,
          borderColor: (confirm.isNotEmpty && !passwordsMatch)
              ? AppColors.brandRed
              : null,
          focusBorderColor: (confirm.isNotEmpty && !passwordsMatch)
              ? AppColors.brandRed
              : null,
          suffixIcon: _visibilityToggle(
            _confirmVisible,
            () => setState(() => _confirmVisible = !_confirmVisible),
          ),
        ),
        const SizedBox(height: AppSpacing.section),
        PrimaryButton(
          label: l10n.authRegisterButton,
          onPressed: canSubmit ? _submit : null,
        ),
        const SizedBox(height: AppSpacing.fieldGap),
        _signInRow(context, l10n),
      ],
    );
  }

  Widget _registrationMessage({
    required String message,
    required Color messageColor,
    required bool emphasized,
  }) {
    return SizedBox(
      height: AppSpacing.xxxl + AppSpacing.xs,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        layoutBuilder: (currentChild, previousChildren) => Stack(
          alignment: Alignment.center,
          children: [...previousChildren, ?currentChild],
        ),
        transitionBuilder: (child, animation) =>
            FadeTransition(opacity: animation, child: child),
        child: Text(
          message,
          key: ValueKey(message),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            fontWeight: emphasized ? FontWeight.w500 : FontWeight.w400,
            color: messageColor,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  Widget _signInRow(BuildContext context, AppLocalizations l10n) {
    final brightness = Theme.of(context).brightness;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: AppSpacing.xs,
      children: [
        Text(
          l10n.authRegisterHaveAccount,
          style: TextStyle(
            fontSize: 13,
            color: AppColors.onSurfaceSubtle(brightness),
          ),
        ),
        GestureDetector(
          onTap: () => context.go('/login'),
          child: Text(
            l10n.authRegisterSignIn,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: BrandHero.textColorFor(brightness),
            ),
          ),
        ),
      ],
    );
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    context.read<RegisterCubit>().submitCredentials(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );
  }

  Widget _visibilityToggle(bool visible, VoidCallback onToggle) {
    final brightness = Theme.of(context).brightness;
    return IconButton(
      icon: Icon(
        visible ? Icons.visibility_off : Icons.visibility,
        size: 20,
        color: AppColors.iconDefault(brightness),
      ),
      onPressed: onToggle,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Step 2 — recovery mnemonic backup
// ─────────────────────────────────────────────────────────────────────

class _RecoveryBackupStep extends StatefulWidget {
  const _RecoveryBackupStep();

  @override
  State<_RecoveryBackupStep> createState() => _RecoveryBackupStepState();
}

class _RecoveryBackupStepState extends State<_RecoveryBackupStep> {
  final _exportButtonKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final mnemonic = context.select<RegisterCubit, List<String>>(
      (c) => c.state.mnemonic,
    );

    return OnboardingScaffold(
      currentStep: 1,
      title: l10n.onboardingRecoveryTitle,
      subtitle: l10n.onboardingRecoverySubtitle,
      onBack: () => context.read<RegisterCubit>().goBack(),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _OutlineAction(
            icon: Icons.content_copy,
            label: l10n.onboardingRecoveryCopy,
            onPressed: () => _copy(mnemonic, l10n),
          ),
          const SizedBox(height: AppSpacing.innerGap),
          _OutlineAction(
            key: _exportButtonKey,
            icon: Icons.file_download_outlined,
            label: l10n.onboardingRecoveryExport,
            onPressed: () => _export(mnemonic, l10n),
          ),
          const SizedBox(height: AppSpacing.innerGap),
          PrimaryButton(
            label: l10n.onboardingRecoverySaved,
            onPressed: () =>
                context.read<RegisterCubit>().acknowledgeRecoveryBackup(),
          ),
        ],
      ),
      children: [
        WarningZone(
          title: l10n.authRecoveryWarningTitle,
          message: l10n.onboardingRecoveryWarning,
        ),
        const SizedBox(height: AppSpacing.section),
        MnemonicWordGrid(words: mnemonic),
      ],
    );
  }

  Future<void> _copy(List<String> words, AppLocalizations l10n) async {
    await SecureClipboard.copy(words.join(' '));
    if (!mounted) return;
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

  Future<void> _export(List<String> words, AppLocalizations l10n) async {
    final box =
        _exportButtonKey.currentContext?.findRenderObject() as RenderBox?;
    final origin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : Rect.zero;
    final content = words
        .asMap()
        .entries
        .map((e) => '${e.key + 1}. ${e.value}')
        .join('\n');
    final bytes = Uint8List.fromList(utf8.encode(content));
    await Share.shareXFiles(
      [XFile.fromData(bytes, mimeType: 'text/plain')],
      fileNameOverrides: const ['palladin-recovery-key.txt'],
      subject: l10n.recoveryShareSubject,
      sharePositionOrigin: origin,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Step 3 — confirm the mnemonic
// ─────────────────────────────────────────────────────────────────────

class _RecoveryConfirmStep extends StatefulWidget {
  const _RecoveryConfirmStep();

  @override
  State<_RecoveryConfirmStep> createState() => _RecoveryConfirmStepState();
}

class _RecoveryConfirmStepState extends State<_RecoveryConfirmStep> {
  late final List<int> _indices;
  late final List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    final mnemonic = context.read<RegisterCubit>().state.mnemonic;
    _indices = pickVerificationIndices(length: mnemonic.length);
    _controllers = List.generate(
      _indices.length,
      (_) => TextEditingController(),
    );
    for (final c in _controllers) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BlocConsumer<RegisterCubit, RegisterState>(
      listenWhen: (p, c) => p.error != c.error && c.error != null,
      listener: (context, state) {
        final error = state.error;
        if (error == null) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(_errorMessage(l10n, error)),
              backgroundColor: AppColors.brandRed,
              behavior: SnackBarBehavior.floating,
            ),
          );
      },
      builder: (context, state) {
        final mnemonic = state.mnemonic;
        final isSubmitting = state.step == RegisterStep.submitting;
        final results = List<_WordCheckResult>.generate(_indices.length, (i) {
          final expected = mnemonic[_indices[i]].trim();
          final actual = _controllers[i].text.trim();
          if (actual.isEmpty) return _WordCheckResult.empty;
          return actual.toLowerCase() == expected.toLowerCase()
              ? _WordCheckResult.correct
              : _WordCheckResult.incorrect;
        });
        final allCorrect = results.every((r) => r == _WordCheckResult.correct);

        return OnboardingScaffold(
          currentStep: 2,
          title: l10n.onboardingConfirmTitle,
          subtitle: l10n.onboardingConfirmSubtitle,
          onBack: isSubmitting
              ? null
              : () => context.read<RegisterCubit>().goBack(),
          children: [
            for (var i = 0; i < _indices.length; i++) ...[
              _ConfirmationInput(
                wordIndex: _indices[i] + 1,
                controller: _controllers[i],
                result: results[i],
                l10n: l10n,
              ),
              const SizedBox(height: AppSpacing.fieldGap),
            ],
            const SizedBox(height: AppSpacing.xs),
            PrimaryButton(
              label: l10n.onboardingConfirmVerify,
              isLoading: isSubmitting,
              onPressed: allCorrect && !isSubmitting
                  ? () => context.read<RegisterCubit>().completeRegistration(
                      preferredLanguage: Localizations.localeOf(
                        context,
                      ).languageCode,
                    )
                  : null,
            ),
          ],
        );
      },
    );
  }

  String _errorMessage(AppLocalizations l10n, Object error) {
    if (error is EmailAlreadyRegisteredException) {
      return l10n.authRegisterEmailTaken;
    }
    if (error is PasswordAuthServerException) {
      return switch (error.kind) {
        PasswordAuthServerErrorKind.serverNotResponding =>
          l10n.errorServerNotResponding,
        PasswordAuthServerErrorKind.cannotConnect =>
          l10n.errorCannotConnectToServer,
        PasswordAuthServerErrorKind.connectionFailed =>
          l10n.errorConnectionFailed,
        PasswordAuthServerErrorKind.invalidResponse =>
          l10n.errorInvalidServerResponse,
      };
    }
    return l10n.errorConnectionFailed;
  }
}

enum _WordCheckResult { empty, correct, incorrect }

class _ConfirmationInput extends StatelessWidget {
  const _ConfirmationInput({
    required this.wordIndex,
    required this.controller,
    required this.result,
    required this.l10n,
  });

  final int wordIndex;
  final TextEditingController controller;
  final _WordCheckResult result;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final borderColor = switch (result) {
      _WordCheckResult.empty => null,
      _WordCheckResult.correct => AppColors.positiveAccent,
      _WordCheckResult.incorrect => AppColors.brandRed,
    };
    final focusBorderColor = result == _WordCheckResult.empty
        ? AppColors.brandRed
        : borderColor;
    final isVisible = result != _WordCheckResult.empty;
    final isCorrect = result == _WordCheckResult.correct;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OnboardingTextField(
          label: l10n.onboardingConfirmWordLabel(wordIndex),
          controller: controller,
          hintText: l10n.onboardingConfirmWordHint(wordIndex),
          borderColor: borderColor,
          focusBorderColor: focusBorderColor,
        ),
        FieldFeedbackSlot(
          visible: isVisible,
          reserveSpace: false,
          child: Row(
            children: [
              Icon(
                isCorrect ? Icons.check_circle_outline : Icons.error_outline,
                size: 14,
                color: isCorrect
                    ? AppColors.positiveAccent
                    : AppColors.brandRed,
              ),
              const SizedBox(width: AppSpacing.innerGap),
              Text(
                isCorrect
                    ? l10n.onboardingConfirmCorrect
                    : l10n.onboardingConfirmIncorrect,
                style: TextStyle(
                  fontSize: 12,
                  color: isCorrect
                      ? AppColors.positiveAccent
                      : AppColors.brandRed,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Shared
// ─────────────────────────────────────────────────────────────────────

class _OutlineAction extends StatelessWidget {
  const _OutlineAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final foreground = AppColors.onSurface(brightness);
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: OutlinedButton.icon(
        icon: Icon(icon, size: 16, color: foreground),
        label: Text(
          label,
          style: TextStyle(
            color: foreground,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.transparent,
          side: BorderSide(color: AppColors.cardBorder(brightness)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        onPressed: onPressed,
      ),
    );
  }
}

class _CompletedPlaceholder extends StatelessWidget {
  const _CompletedPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const AppScreen(
      body: Center(child: CircularProgressIndicator(color: AppColors.brandRed)),
    );
  }
}
