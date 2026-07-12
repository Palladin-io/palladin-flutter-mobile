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
import '../../../../core/widgets/mnemonic_word_grid.dart';
import '../../../../core/widgets/warning_zone.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../onboarding/domain/mnemonic.dart';
import '../../../onboarding/domain/password_strength.dart';
import '../../../onboarding/presentation/widgets/onboarding_scaffold.dart';
import '../../../onboarding/presentation/widgets/onboarding_text_field.dart';
import '../../../onboarding/presentation/widgets/password_strength_bar.dart';
import '../../../onboarding/presentation/widgets/primary_button.dart';
import '../../data/services/hibp_service.dart';
import '../../domain/password_auth_exceptions.dart';
import '../bloc/auth_bloc.dart';
import '../cubit/register_cubit.dart';

/// Registration wizard (CVT-271): email + master password + recovery
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
          context.read<AuthBloc>().add(PasswordSessionEstablished(
                masterKey: keys.masterKey,
                privateKey: keys.privateKey,
              ));
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
              transitionBuilder: (child, animation) {
                final offset = Tween<Offset>(
                  begin: const Offset(0.04, 0),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(parent: animation, curve: Curves.easeOut),
                );
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: offset, child: child),
                );
              },
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

  final HibpService _hibp = getIt<HibpService>();
  Timer? _hibpDebounce;
  HibpResult _hibpResult = HibpResult.unknown;
  bool _hibpChecking = false;

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void initState() {
    super.initState();
    final cubit = context.read<RegisterCubit>();
    if (cubit.state.email.isNotEmpty) _emailController.text = cubit.state.email;
    // Password draft lives on the cubit (never in observable state); pre-fill
    // it when the user navigates back to this step.
    final passwordDraft = cubit.passwordDraft;
    if (passwordDraft.isNotEmpty) {
      _passwordController.text = passwordDraft;
      _confirmController.text = passwordDraft;
    }
    _emailController.addListener(_onChanged);
    _passwordController.addListener(_onPasswordChanged);
    _confirmController.addListener(_onChanged);
  }

  @override
  void dispose() {
    _hibpDebounce?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  void _onPasswordChanged() {
    setState(() {
      // A password edit invalidates the previous breach signal.
      _hibpResult = HibpResult.unknown;
    });
    _hibpDebounce?.cancel();
    final password = _passwordController.text;
    if (password.length < 8) {
      setState(() => _hibpChecking = false);
      return;
    }
    setState(() => _hibpChecking = true);
    _hibpDebounce = Timer(const Duration(milliseconds: 500), () async {
      final result = await _hibp.check(password);
      if (!mounted || _passwordController.text != password) return;
      setState(() {
        _hibpResult = result;
        _hibpChecking = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmController.text;
    final emailValid = _emailPattern.hasMatch(email);
    final strength = evaluatePasswordStrength(password);
    final passwordsMatch = password.isNotEmpty && password == confirm;
    final breached = _hibpResult == HibpResult.pwned;
    final canSubmit = emailValid &&
        strength.isAcceptable &&
        passwordsMatch &&
        !breached &&
        !_hibpChecking;

    return OnboardingScaffold(
      currentStep: 0,
      title: l10n.authRegisterTitle,
      subtitle: l10n.authRegisterSubtitle,
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          PrimaryButton(
            label: l10n.onboardingContinue,
            onPressed: canSubmit ? _submit : null,
          ),
          const SizedBox(height: AppSpacing.md),
          _signInRow(context, l10n),
        ],
      ),
      children: [
        OnboardingTextField(
          label: l10n.authEmailLabel,
          controller: _emailController,
          hintText: l10n.authEmailHint,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          borderColor: (email.isNotEmpty && !emailValid)
              ? AppColors.brandRed
              : null,
          focusBorderColor: (email.isNotEmpty && !emailValid)
              ? AppColors.brandRed
              : null,
          feedbackVisible: email.isNotEmpty && !emailValid,
          feedbackReserveSpace: false,
          feedbackChild: Text(
            l10n.authEmailInvalid,
            style: const TextStyle(fontSize: 12, color: AppColors.brandRed),
          ),
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
          feedbackVisible: password.isNotEmpty,
          feedbackReserveSpace: false,
          feedbackChild: Text(
            _strengthLabel(l10n, strength),
            style: TextStyle(
              fontSize: 12,
              color: _strengthColor(strength),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        SizedBox(
          height: AppSpacing.fieldGap,
          child: AnimatedOpacity(
            opacity: password.isNotEmpty ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 180),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: PasswordStrengthBar(strength: strength),
            ),
          ),
        ),
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
          feedbackVisible: confirm.isNotEmpty && !passwordsMatch,
          feedbackReserveSpace: false,
          feedbackChild: Text(
            l10n.onboardingPasswordsDoNotMatch,
            style: const TextStyle(fontSize: 12, color: AppColors.brandRed),
          ),
          suffixIcon: _visibilityToggle(
            _confirmVisible,
            () => setState(() => _confirmVisible = !_confirmVisible),
          ),
        ),
        const SizedBox(height: AppSpacing.fieldGap),
        if (breached)
          WarningZone(
            title: l10n.authPasswordBreachedTitle,
            message: l10n.authPasswordBreached,
          )
        else if (_hibpChecking)
          _CheckingRow(label: l10n.authPasswordChecking),
      ],
    );
  }

  Widget _signInRow(BuildContext context, AppLocalizations l10n) {
    final brightness = Theme.of(context).brightness;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          l10n.authRegisterHaveAccount,
          style: TextStyle(
            fontSize: 13,
            color: AppColors.onSurfaceSubtle(brightness),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        GestureDetector(
          onTap: () => context.go('/login'),
          child: Text(
            l10n.authRegisterSignIn,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.brandRed,
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

  String _strengthLabel(AppLocalizations l10n, PasswordStrength strength) {
    return switch (strength) {
      PasswordStrength.tooShort => l10n.onboardingPasswordStrengthTooShort,
      PasswordStrength.weak => l10n.onboardingPasswordStrengthWeak,
      PasswordStrength.fair => l10n.onboardingPasswordStrengthFair,
      PasswordStrength.strong => l10n.onboardingPasswordStrengthStrong,
      PasswordStrength.veryStrong => l10n.onboardingPasswordStrengthVeryStrong,
    };
  }

  Color _strengthColor(PasswordStrength strength) {
    return switch (strength) {
      PasswordStrength.tooShort ||
      PasswordStrength.weak =>
        AppColors.brandRed,
      PasswordStrength.fair => AppColors.strengthFair,
      PasswordStrength.strong ||
      PasswordStrength.veryStrong =>
        AppColors.positiveAccent,
    };
  }
}

class _CheckingRow extends StatelessWidget {
  const _CheckingRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 1.6,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(width: AppSpacing.innerGap),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
        ),
      ],
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
    final origin =
        box != null ? box.localToGlobal(Offset.zero) & box.size : Rect.zero;
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
    _controllers =
        List.generate(_indices.length, (_) => TextEditingController());
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
        final allCorrect =
            results.every((r) => r == _WordCheckResult.correct);

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
                        preferredLanguage:
                            Localizations.localeOf(context).languageCode,
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
    final focusBorderColor =
        result == _WordCheckResult.empty ? AppColors.brandRed : borderColor;
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
                color:
                    isCorrect ? AppColors.positiveAccent : AppColors.brandRed,
              ),
              const SizedBox(width: AppSpacing.innerGap),
              Text(
                isCorrect
                    ? l10n.onboardingConfirmCorrect
                    : l10n.onboardingConfirmIncorrect,
                style: TextStyle(
                  fontSize: 12,
                  color:
                      isCorrect ? AppColors.positiveAccent : AppColors.brandRed,
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
    final brightness = Theme.of(context).brightness;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          gradient: AppColors.backgroundGradient(brightness),
        ),
        child: const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
