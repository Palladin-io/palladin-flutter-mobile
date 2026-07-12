import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/brand_hero.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../onboarding/presentation/widgets/onboarding_text_field.dart';
import '../../../onboarding/presentation/widgets/primary_button.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../domain/password_auth_exceptions.dart';
import '../bloc/auth_bloc.dart';
import '../cubit/login_cubit.dart';
import '../widgets/oauth_button.dart';

/// Sign-in screen (CVT-272) — email + master password, with the in-flow
/// TOTP challenge (CVT-275) and the existing OAuth providers.
///
/// The [LoginCubit] runs salt → authHash → login → master-key derivation;
/// on success the page hands the derived keys to [AuthBloc] via
/// [PasswordSessionEstablished] and the router forwards on (verify-email
/// gate or vault).
class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<LoginCubit>(
      create: (_) => getIt<LoginCubit>(),
      child: const _LoginView(),
    );
  }
}

class _LoginView extends StatefulWidget {
  const _LoginView();

  @override
  State<_LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<_LoginView> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _codeController = TextEditingController();
  bool _passwordVisible = false;
  bool _useRecoveryCode = false;

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_onChanged);
    _passwordController.addListener(_onChanged);
    _codeController.addListener(_onChanged);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return MultiBlocListener(
      listeners: [
        BlocListener<LoginCubit, LoginState>(listener: _handleLoginState),
        BlocListener<AuthBloc, AuthState>(listener: _handleOAuthState),
      ],
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Container(
          decoration: BoxDecoration(
            gradient: AppColors.backgroundGradient(brightness),
          ),
          child: SafeArea(
            child: BlocBuilder<LoginCubit, LoginState>(
              builder: (context, state) {
                final onTotp =
                    state is LoginTotpChallenge || state is LoginTotpVerifying;
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.screenH,
                    vertical: AppSpacing.xxl,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: MediaQuery.sizeOf(context).height -
                          MediaQuery.paddingOf(context).vertical -
                          AppSpacing.xxl * 2,
                    ),
                    child: onTotp
                        ? _buildTotpChallenge(context, state)
                        : _buildLoginForm(context, state),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // ─── login form ──────────────────────────────────────────────────────

  Widget _buildLoginForm(BuildContext context, LoginState state) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final isLoading = state is LoginLoading;
    final failure = state is LoginFailure ? state.error : null;
    final canSubmit = !isLoading &&
        _emailController.text.trim().isNotEmpty &&
        _passwordController.text.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.xxl),
        Center(child: BrandHero(textColor: BrandHero.textColorFor(brightness))),
        const SizedBox(height: AppSpacing.xs),
        Text(
          l10n.authLoginSubtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: AppColors.onSurfaceSubtle(brightness),
            height: 1.4,
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        OnboardingTextField(
          label: l10n.authEmailLabel,
          controller: _emailController,
          hintText: l10n.authEmailHint,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.fieldGap),
        OnboardingTextField(
          label: l10n.authPasswordLabel,
          controller: _passwordController,
          obscureText: !_passwordVisible,
          textInputAction: TextInputAction.done,
          onSubmitted: canSubmit ? (_) => _submitLogin() : null,
          borderColor: failure != null ? AppColors.brandRed : null,
          focusBorderColor: failure != null ? AppColors.brandRed : null,
          feedbackVisible: failure != null,
          feedbackReserveSpace: false,
          feedbackChild: Text(
            failure != null ? _loginErrorMessage(context, failure) : '',
            style: const TextStyle(fontSize: 12, color: AppColors.brandRed),
          ),
          suffixIcon: _visibilityToggle(
            _passwordVisible,
            () => setState(() => _passwordVisible = !_passwordVisible),
          ),
        ),
        const SizedBox(height: AppSpacing.section),
        PrimaryButton(
          label: l10n.authLoginButton,
          isLoading: isLoading,
          onPressed: canSubmit ? _submitLogin : null,
        ),
        const SizedBox(height: AppSpacing.md),
        _signUpRow(context, l10n, brightness),
        const SizedBox(height: AppSpacing.xl),
        _orDivider(context, l10n, brightness),
        const SizedBox(height: AppSpacing.xl),
        _oauthButtons(context, l10n, isLoading),
        const SizedBox(height: AppSpacing.section),
        _legalFooter(context, l10n, brightness),
      ],
    );
  }

  Widget _signUpRow(
    BuildContext context,
    AppLocalizations l10n,
    Brightness brightness,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          l10n.authNoAccountPrompt,
          style: TextStyle(
            fontSize: 13,
            color: AppColors.onSurfaceSubtle(brightness),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        GestureDetector(
          onTap: () => context.go('/register'),
          child: Text(
            l10n.authSignUpLink,
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

  Widget _orDivider(
    BuildContext context,
    AppLocalizations l10n,
    Brightness brightness,
  ) {
    final line = Expanded(
      child: Divider(color: AppColors.cardBorder(brightness), height: 1),
    );
    return Row(
      children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text(
            l10n.authOrDivider,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.onSurfaceSubtle(brightness),
            ),
          ),
        ),
        line,
      ],
    );
  }

  Widget _oauthButtons(
    BuildContext context,
    AppLocalizations l10n,
    bool isLoading,
  ) {
    return Column(
      children: [
        OAuthButton(
          label: l10n.continueWithGoogle,
          icon: _providerGlyph('G', AppColors.googleBlue),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          onPressed: isLoading
              ? null
              : () => context.read<AuthBloc>().add(const AuthLoginWithGoogle()),
        ),
        const SizedBox(height: AppSpacing.fieldGap),
        OAuthButton(
          label: l10n.continueWithApple,
          icon: const Icon(Icons.apple, color: Colors.white, size: 24),
          backgroundColor: AppColors.disabledButtonBackground,
          foregroundColor: Colors.white,
          enabled: false,
          onDisabledTap: () => _comingSoon(context, 'Apple'),
        ),
        const SizedBox(height: AppSpacing.fieldGap),
        OAuthButton(
          label: l10n.continueWithX,
          icon: _providerGlyph('X', Colors.white),
          backgroundColor: AppColors.disabledButtonBackground,
          foregroundColor: Colors.white,
          enabled: false,
          onDisabledTap: () => _comingSoon(context, 'X'),
        ),
      ],
    );
  }

  Widget _legalFooter(
    BuildContext context,
    AppLocalizations l10n,
    Brightness brightness,
  ) {
    return Text(
      l10n.legalFooter,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 12,
        color: BrandHero.textColorFor(brightness).withValues(alpha: 0.4),
      ),
    );
  }

  // ─── TOTP challenge ───────────────────────────────────────────────────

  Widget _buildTotpChallenge(BuildContext context, LoginState state) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final isVerifying = state is LoginTotpVerifying;
    final hasError =
        state is LoginTotpChallenge && state.error is TotpInvalidException;
    final canSubmit = !isVerifying && _codeController.text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.xxl),
        Center(child: BrandHero(textColor: BrandHero.textColorFor(brightness))),
        const SizedBox(height: AppSpacing.xxl),
        Text(
          l10n.authTotpChallengeTitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.onSurface(brightness),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          _useRecoveryCode
              ? l10n.authTotpRecoverySubtitle
              : l10n.authTotpChallengeSubtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: AppColors.onSurfaceSubtle(brightness),
            height: 1.4,
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        OnboardingTextField(
          label: _useRecoveryCode
              ? l10n.authTotpRecoveryLabel
              : l10n.authTotpCodeLabel,
          controller: _codeController,
          keyboardType:
              _useRecoveryCode ? TextInputType.text : TextInputType.number,
          inputFormatters: _useRecoveryCode
              ? null
              : [FilteringTextInputFormatter.digitsOnly],
          textInputAction: TextInputAction.done,
          onSubmitted: canSubmit ? (_) => _submitTotp() : null,
          borderColor: hasError ? AppColors.brandRed : null,
          focusBorderColor: hasError ? AppColors.brandRed : null,
          feedbackVisible: hasError,
          feedbackReserveSpace: false,
          feedbackChild: Text(
            l10n.authTotpInvalid,
            style: const TextStyle(fontSize: 12, color: AppColors.brandRed),
          ),
        ),
        const SizedBox(height: AppSpacing.section),
        PrimaryButton(
          label: l10n.authTotpVerifyButton,
          isLoading: isVerifying,
          onPressed: canSubmit ? _submitTotp : null,
        ),
        const SizedBox(height: AppSpacing.md),
        TextButton(
          onPressed: isVerifying
              ? null
              : () {
                  _codeController.clear();
                  setState(() => _useRecoveryCode = !_useRecoveryCode);
                },
          child: Text(
            _useRecoveryCode
                ? l10n.authTotpUseCode
                : l10n.authTotpUseRecovery,
            style: const TextStyle(fontSize: 13, color: AppColors.brandRed),
          ),
        ),
      ],
    );
  }

  // ─── actions ──────────────────────────────────────────────────────────

  void _submitLogin() {
    FocusScope.of(context).unfocus();
    context.read<LoginCubit>().login(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
  }

  void _submitTotp() {
    FocusScope.of(context).unfocus();
    context.read<LoginCubit>().submitTotp(_codeController.text.trim());
  }

  void _handleLoginState(BuildContext context, LoginState state) {
    if (state is LoginSuccess) {
      context.read<AuthBloc>().add(
            PasswordSessionEstablished(
              masterKey: state.masterKey,
              privateKey: state.privateKey,
            ),
          );
    }
  }

  void _handleOAuthState(BuildContext context, AuthState state) {
    if (state is AuthError) {
      _showSnack(context, _oauthErrorMessage(context, state.error));
    }
  }

  // ─── helpers ──────────────────────────────────────────────────────────

  Widget _visibilityToggle(bool visible, VoidCallback onToggle) {
    return IconButton(
      icon: Icon(
        visible ? Icons.visibility_off : Icons.visibility,
        size: 20,
        color: AppColors.iconMuted,
      ),
      onPressed: onToggle,
    );
  }

  Widget _providerGlyph(String letter, Color color) {
    return Center(
      child: Text(
        letter,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  String _loginErrorMessage(BuildContext context, Object error) {
    final l10n = AppLocalizations.of(context)!;
    if (error is InvalidCredentialsException) return l10n.authInvalidCredentials;
    if (error is LoginRateLimitedException) return l10n.authRateLimited;
    if (error is PasswordAuthServerException) {
      return _serverErrorMessage(context, error.kind);
    }
    return l10n.errorConnectionFailed;
  }

  String _oauthErrorMessage(BuildContext context, Object error) {
    final l10n = AppLocalizations.of(context)!;
    if (error is AuthServerException) {
      return switch (error.kind) {
        AuthServerErrorKind.serverNotResponding =>
          l10n.errorServerNotResponding,
        AuthServerErrorKind.cannotConnect => l10n.errorCannotConnectToServer,
        AuthServerErrorKind.connectionFailed => l10n.errorConnectionFailed,
        AuthServerErrorKind.invalidResponse => l10n.errorInvalidServerResponse,
      };
    }
    return l10n.errorConnectionFailed;
  }

  String _serverErrorMessage(
    BuildContext context,
    PasswordAuthServerErrorKind kind,
  ) {
    final l10n = AppLocalizations.of(context)!;
    return switch (kind) {
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

  void _comingSoon(BuildContext context, String provider) {
    final l10n = AppLocalizations.of(context)!;
    _showSnack(context, l10n.providerComingSoon(provider));
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.brandRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }
}
