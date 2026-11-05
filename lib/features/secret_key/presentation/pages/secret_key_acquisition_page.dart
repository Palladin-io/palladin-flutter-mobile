import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_bar_title.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../onboarding/presentation/widgets/onboarding_text_field.dart';
import '../cubit/secret_key_acquisition_cubit.dart';
import '../widgets/transfer_widgets.dart';

/// Route arguments: the account from the sign-in bootstrap.
final class SecretKeyAcquisitionArgs {
  const SecretKeyAcquisitionArgs({
    required this.accountId,
    required this.email,
  });
  final String accountId;
  final String email;
}

/// New-device Secret Key setup (CVT-710). Pops with a fresh copy of the
/// 32-byte Secret Key, or `null` when the user leaves; the caller owns and
/// wipes the returned buffer.
class SecretKeyAcquisitionPage extends StatelessWidget {
  const SecretKeyAcquisitionPage({super.key, required this.args});

  final SecretKeyAcquisitionArgs args;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => getIt<SecretKeyAcquisitionCubit>(param1: args.accountId),
    child: const SecretKeyAcquisitionView(),
  );
}

class SecretKeyAcquisitionView extends StatelessWidget {
  const SecretKeyAcquisitionView({super.key, this.scanQr = launchQrScanner});

  final QrScanLauncher scanQr;

  Future<void> _scanComputer(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final cubit = context.read<SecretKeyAcquisitionCubit>();
    final raw = await scanQr(
      context,
      title: l10n.secretKeyEntryScanComputer,
      instruction: l10n.secretKeyEntryScanComputerInstruction,
    );
    if (raw != null) await cubit.onScannedSenderCode(raw);
  }

  Future<void> _scanKit(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final cubit = context.read<SecretKeyAcquisitionCubit>();
    final raw = await scanQr(
      context,
      title: l10n.secretKeyEntryScanKit,
      instruction: l10n.secretKeyEntryScanKitInstruction,
    );
    if (raw != null) cubit.onScannedKitCode(raw);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final cubit = context.read<SecretKeyAcquisitionCubit>();
    return BlocConsumer<SecretKeyAcquisitionCubit, SecretKeyAcquisitionState>(
      listenWhen: (_, state) => state is SecretKeyAcquisitionAcquired,
      listener: (context, state) {
        if (state is SecretKeyAcquisitionAcquired) {
          context.pop<Uint8List>(Uint8List.fromList(state.secret));
        }
      },
      builder: (context, state) {
        final title = switch (state) {
          SecretKeyAcquisitionShowingCode() => l10n.secretKeyEntryShowCodeTitle,
          SecretKeyAcquisitionAwaitingSender() =>
            l10n.deviceTransferCompareTitle,
          SecretKeyAcquisitionKitEntry() => l10n.secretKeyEntryUseKit,
          _ => l10n.secretKeyEntryTitle,
        };
        final onPicker = state is SecretKeyAcquisitionChoose;
        return PopScope(
          canPop: onPicker || state is SecretKeyAcquisitionAcquired,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) cubit.back();
          },
          child: AppScreen.appBar(
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              scrolledUnderElevation: 0,
              titleSpacing: 0,
              centerTitle: false,
              iconTheme: IconThemeData(color: AppColors.onSurface(brightness)),
              title: AppBarTitle(title: title),
            ),
            body: switch (state) {
              SecretKeyAcquisitionChoose() => _MethodPicker(
                onScanComputer: () => _scanComputer(context),
                onShowCode: cubit.showCode,
                onUseKit: cubit.chooseEmergencyKit,
              ),
              SecretKeyAcquisitionPreparing() ||
              SecretKeyAcquisitionAcquired() => const Center(
                child: CircularProgressIndicator(color: AppColors.brandRed),
              ),
              SecretKeyAcquisitionShowingCode(
                :final qrPayload,
                :final sas,
                :final expiresAt,
              ) =>
                _WaitingBody(
                  intro: l10n.secretKeyEntryShowCodeBody,
                  qrPayload: qrPayload,
                  sasLabel: l10n.secretKeyEntrySameCode,
                  sas: sas,
                  waiting: l10n.secretKeyEntryWaiting,
                  expiresAt: expiresAt,
                  onCancel: cubit.back,
                ),
              SecretKeyAcquisitionAwaitingSender(:final sas) => _WaitingBody(
                intro: l10n.secretKeyEntryCompareComputerBody,
                sasLabel: l10n.deviceTransferCodeOnThisPhone,
                sas: sas,
                waiting: l10n.secretKeyEntryWaitingComputer,
                onCancel: cubit.back,
              ),
              SecretKeyAcquisitionKitEntry(:final error) => _KitEntryBody(
                error: error,
                onScanKit: () => _scanKit(context),
                onSubmit: cubit.submitTypedSecretKey,
              ),
              SecretKeyAcquisitionFailed(:final failure) => TransferStatusView(
                icon: failure == DeviceTransferFailure.expired
                    ? Icons.timer_off_outlined
                    : Icons.error_outline,
                iconColor: AppColors.brandRed,
                title: failure == DeviceTransferFailure.expired
                    ? l10n.deviceTransferExpiredTitle
                    : l10n.deviceTransferFailedTitle,
                message: transferFailureMessage(l10n, failure),
                actionLabel: l10n.deviceTransferTryAgain,
                onAction: cubit.back,
              ),
            },
          ),
        );
      },
    );
  }
}

class _MethodPicker extends StatelessWidget {
  const _MethodPicker({
    required this.onScanComputer,
    required this.onShowCode,
    required this.onUseKit,
  });

  final VoidCallback onScanComputer;
  final VoidCallback onShowCode;
  final VoidCallback onUseKit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        0,
        AppSpacing.screenH,
        AppSpacing.screenBottom,
      ),
      children: [
        TransferIntroText(l10n.secretKeyEntryIntro),
        const SizedBox(height: AppSpacing.section),
        TransferMethodTile(
          icon: Icons.qr_code_scanner,
          title: l10n.secretKeyEntryScanComputer,
          subtitle: l10n.secretKeyEntryScanComputerHint,
          onTap: onScanComputer,
        ),
        const SizedBox(height: AppSpacing.cardGap),
        TransferMethodTile(
          icon: Icons.qr_code_2,
          title: l10n.secretKeyEntryShowCode,
          subtitle: l10n.secretKeyEntryShowCodeHint,
          onTap: onShowCode,
        ),
        const SizedBox(height: AppSpacing.section),
        _OrDivider(label: l10n.secretKeyEntryOr),
        const SizedBox(height: AppSpacing.section),
        TransferMethodTile(
          icon: Icons.description_outlined,
          title: l10n.secretKeyEntryUseKit,
          subtitle: l10n.secretKeyEntryUseKitHint,
          onTap: onUseKit,
        ),
      ],
    );
  }
}

class _WaitingBody extends StatelessWidget {
  const _WaitingBody({
    required this.intro,
    required this.sasLabel,
    required this.sas,
    required this.waiting,
    required this.onCancel,
    this.qrPayload,
    this.expiresAt,
  });

  final String intro;
  final String? qrPayload;
  final String sasLabel;
  final String sas;
  final String waiting;
  final DateTime? expiresAt;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        0,
        AppSpacing.screenH,
        AppSpacing.screenBottom,
      ),
      children: [
        TransferIntroText(intro),
        const SizedBox(height: AppSpacing.section),
        if (qrPayload case final payload?) ...[
          Center(
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.onBrandRed,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                key: const Key('transfer-qr'),
                data: payload,
                size: 220,
                backgroundColor: AppColors.onBrandRed,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.section),
        ],
        SasCodeCard(label: sasLabel, code: sas),
        const SizedBox(height: AppSpacing.section),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.brandRed,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                waiting,
                style: TextStyle(
                  color: AppColors.onSurfaceMuted(brightness),
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        if (expiresAt case final expiry?) ...[
          const SizedBox(height: AppSpacing.sm),
          TransferCountdown(expiresAt: expiry),
        ],
        const SizedBox(height: AppSpacing.section),
        Center(
          child: TextButton(
            onPressed: onCancel,
            child: Text(
              l10n.secretKeyEntryCancel,
              style: const TextStyle(color: AppColors.brandRed),
            ),
          ),
        ),
      ],
    );
  }
}

class _KitEntryBody extends StatefulWidget {
  const _KitEntryBody({
    required this.error,
    required this.onScanKit,
    required this.onSubmit,
  });

  final SecretKeyEntryError? error;
  final VoidCallback onScanKit;
  final ValueChanged<String> onSubmit;

  @override
  State<_KitEntryBody> createState() => _KitEntryBodyState();
}

class _KitEntryBodyState extends State<_KitEntryBody> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _errorText(AppLocalizations l10n) => switch (widget.error) {
    SecretKeyEntryError.malformed => l10n.secretKeyEntryErrorMalformed,
    SecretKeyEntryError.checksumMismatch => l10n.secretKeyEntryErrorChecksum,
    SecretKeyEntryError.kitAccountMismatch =>
      l10n.secretKeyEntryErrorKitAccount,
    SecretKeyEntryError.notKitCode => l10n.secretKeyEntryErrorKitQr,
    null => null,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final error = _errorText(l10n);
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
            children: [
              TransferIntroText(l10n.secretKeyEntryKitBody),
              const SizedBox(height: AppSpacing.section),
              OutlinedButton.icon(
                onPressed: widget.onScanKit,
                icon: const Icon(Icons.qr_code_scanner, size: 18),
                label: Text(l10n.secretKeyEntryScanKit),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.onSurface(brightness),
                  side: BorderSide(color: AppColors.cardBorder(brightness)),
                  minimumSize: const Size.fromHeight(AppSpacing.controlHeight),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.section),
              _OrDivider(label: l10n.secretKeyEntryOr),
              const SizedBox(height: AppSpacing.section),
              OnboardingTextField(
                label: l10n.secretKeyEntryFieldLabel,
                controller: _controller,
                monospace: true,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.done,
                onSubmitted: widget.onSubmit,
                borderColor: error == null ? null : AppColors.brandRed,
                feedbackChild: Text(
                  error ?? l10n.secretKeyEntryFieldHint,
                  style: TextStyle(
                    color: error == null
                        ? AppColors.onSurfaceSubtle(brightness)
                        : AppColors.brandRed,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
                feedbackVisible: true,
                feedbackReserveSpace: false,
              ),
            ],
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH,
            AppSpacing.md,
            AppSpacing.screenH,
            AppSpacing.screenBottom,
          ),
          decoration: BoxDecoration(
            color: AppColors.cardFill(brightness),
            border: Border(
              top: BorderSide(color: AppColors.navBorder(brightness)),
            ),
          ),
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, value, _) => PrimaryButton(
              label: l10n.secretKeyEntryContinue,
              onPressed: value.text.trim().isEmpty
                  ? null
                  : () => widget.onSubmit(value.text.trim()),
            ),
          ),
        ),
      ],
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final line = Expanded(
      child: Divider(color: AppColors.cardBorder(brightness), height: 1),
    );
    return Row(
      children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text(
            label,
            style: TextStyle(
              color: AppColors.onSurfaceSubtle(brightness),
              fontSize: 12,
            ),
          ),
        ),
        line,
      ],
    );
  }
}
