import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/secure_clipboard.dart';
import '../../../../core/widgets/app_bar_title.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/warning_zone.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../onboarding/presentation/widgets/onboarding_text_field.dart';
import '../../../onboarding/presentation/widgets/primary_button.dart';
import '../../domain/password_auth_exceptions.dart';
import '../cubit/totp_enroll_cubit.dart';

/// TOTP enrollment screen.
///
/// Shows the otpauth QR + the base32 secret for manual entry, confirms a
/// generated 6-digit code, then reveals the one-time recovery codes.
class TotpEnrollPage extends StatelessWidget {
  const TotpEnrollPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<TotpEnrollCubit>(
      create: (_) => getIt<TotpEnrollCubit>()..enroll(),
      child: const _TotpEnrollView(),
    );
  }
}

class _TotpEnrollView extends StatefulWidget {
  const _TotpEnrollView();

  @override
  State<_TotpEnrollView> createState() => _TotpEnrollViewState();
}

class _TotpEnrollViewState extends State<_TotpEnrollView> {
  final _codeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _codeController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AppScreen.appBar(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        centerTitle: false,
        title: AppBarTitle(title: l10n.authTotpEnrollTitle),
      ),
      body: BlocBuilder<TotpEnrollCubit, TotpEnrollState>(
        builder: (context, state) => switch (state) {
          TotpEnrollLoading() => const Center(
            child: CircularProgressIndicator(color: AppColors.brandRed),
          ),
          TotpEnrollLoadFailed(:final error) => _LoadFailed(error: error),
          TotpEnrollReady() => _ReadyBody(
            state: state,
            codeController: _codeController,
          ),
          TotpEnrollConfirmed(:final recoveryCodes) => _RecoveryCodesBody(
            codes: recoveryCodes,
          ),
        },
      ),
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: AppScreen.screenPadding,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off, color: AppColors.brandRed, size: 40),
          const SizedBox(height: AppSpacing.section),
          Text(
            _message(l10n),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.onSurfaceSubtle(brightness),
            ),
          ),
          const SizedBox(height: AppSpacing.section),
          PrimaryButton(
            label: l10n.authTotpEnrollRetry,
            onPressed: () => context.read<TotpEnrollCubit>().enroll(),
          ),
        ],
      ),
    );
  }

  String _message(AppLocalizations l10n) {
    if (error is PasswordAuthServerException) {
      return switch ((error as PasswordAuthServerException).kind) {
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

class _ReadyBody extends StatelessWidget {
  const _ReadyBody({required this.state, required this.codeController});

  final TotpEnrollReady state;
  final TextEditingController codeController;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final hasError = state.error is TotpInvalidException;
    final canConfirm =
        !state.confirming && codeController.text.trim().length >= 6;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        0,
        AppSpacing.screenH,
        AppSpacing.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.authTotpEnrollSubtitle,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.onSurfaceSubtle(brightness),
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.section),
          Center(
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.cardPadding),
              decoration: BoxDecoration(
                // White quiet-zone so the QR is scannable in both themes.
                color: AppColors.onBrandRed,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: state.otpauthUri,
                version: QrVersions.auto,
                size: 180,
                backgroundColor: AppColors.onBrandRed,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.section),
          _SecretRow(secret: state.secret),
          const SizedBox(height: AppSpacing.section),
          OnboardingTextField(
            label: l10n.authTotpEnrollCodeLabel,
            controller: codeController,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            textInputAction: TextInputAction.done,
            onSubmitted: canConfirm ? (_) => _confirm(context) : null,
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
            label: l10n.authTotpEnrollConfirmButton,
            isLoading: state.confirming,
            onPressed: canConfirm ? () => _confirm(context) : null,
          ),
        ],
      ),
    );
  }

  void _confirm(BuildContext context) {
    FocusScope.of(context).unfocus();
    context.read<TotpEnrollCubit>().confirm(codeController.text.trim());
  }
}

class _SecretRow extends StatelessWidget {
  const _SecretRow({required this.secret});

  final String secret;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder(brightness)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.authTotpEnrollSecretLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurfaceMuted(brightness),
            ),
          ),
          const SizedBox(height: AppSpacing.innerGap),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  secret,
                  style: TextStyle(
                    fontSize: 14,
                    fontFamily: 'monospace',
                    letterSpacing: 1.2,
                    color: AppColors.onSurface(brightness),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.content_copy,
                  size: 18,
                  color: AppColors.brandRed,
                ),
                tooltip: l10n.authTotpEnrollCopyKey,
                onPressed: () => _copy(context, l10n),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _copy(BuildContext context, AppLocalizations l10n) async {
    await SecureClipboard.copy(secret);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.authTotpEnrollKeyCopied),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }
}

class _RecoveryCodesBody extends StatelessWidget {
  const _RecoveryCodesBody({required this.codes});

  final List<String> codes;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        0,
        AppSpacing.screenH,
        AppSpacing.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.authTotpEnrollRecoveryTitle,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface(brightness),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.authTotpEnrollRecoverySubtitle,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.onSurfaceSubtle(brightness),
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.section),
          WarningZone(
            title: l10n.authTotpEnrollRecoveryWarningTitle,
            message: l10n.authTotpEnrollRecoveryWarning,
          ),
          const SizedBox(height: AppSpacing.section),
          if (codes.isEmpty)
            Text(
              l10n.authTotpEnrollNoCodes,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.onSurfaceSubtle(brightness),
              ),
            )
          else
            _CodesGrid(codes: codes),
          const SizedBox(height: AppSpacing.section),
          if (codes.isNotEmpty)
            OutlinedButton.icon(
              icon: const Icon(
                Icons.content_copy,
                size: 16,
                color: AppColors.brandRed,
              ),
              label: Text(
                l10n.authTotpEnrollCopyCodes,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.brandRed,
                ),
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                side: BorderSide(color: AppColors.cardBorder(brightness)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => _copyCodes(context, l10n),
            ),
          const SizedBox(height: AppSpacing.section),
          PrimaryButton(
            label: l10n.authTotpEnrollDone,
            onPressed: () => context.pop(),
          ),
        ],
      ),
    );
  }

  Future<void> _copyCodes(BuildContext context, AppLocalizations l10n) async {
    await SecureClipboard.copy(codes.join('\n'));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.authTotpEnrollCodesCopied),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }
}

class _CodesGrid extends StatelessWidget {
  const _CodesGrid({required this.codes});

  final List<String> codes;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder(brightness)),
      ),
      child: Wrap(
        spacing: AppSpacing.section,
        runSpacing: AppSpacing.innerGap,
        children: [
          for (final code in codes)
            SizedBox(
              width: 130,
              child: SelectableText(
                code,
                style: TextStyle(
                  fontSize: 14,
                  fontFamily: 'monospace',
                  letterSpacing: 1.0,
                  color: AppColors.onSurface(brightness),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
