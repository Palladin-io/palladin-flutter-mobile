import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_bar_title.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/fab_registrar.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/sheet_action_buttons.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../cubit/device_transfer_sender_cubit.dart';
import '../widgets/transfer_widgets.dart';

/// Settings › Devices: approves a new device by scanning its QR code
/// (CVT-709). Reachable only from the unlocked shell.
class DeviceTransferApprovePage extends StatelessWidget {
  const DeviceTransferApprovePage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthBloc>().state;
    final accountId = auth is AuthAuthenticated ? auth.userId : '';
    return BlocProvider(
      create: (_) => getIt<DeviceTransferSenderCubit>(param1: accountId),
      child: const DeviceTransferApproveView(),
    );
  }
}

class DeviceTransferApproveView extends StatelessWidget {
  const DeviceTransferApproveView({super.key, this.scanQr = launchQrScanner});

  final QrScanLauncher scanQr;

  Future<void> _scan(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final cubit = context.read<DeviceTransferSenderCubit>();
    final raw = await scanQr(
      context,
      title: l10n.deviceTransferAddDevice,
      instruction: l10n.deviceTransferScanInstruction,
    );
    if (raw != null) await cubit.onScanned(raw);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final state = context.watch<DeviceTransferSenderCubit>().state;
    final cubit = context.read<DeviceTransferSenderCubit>();
    final title = state is DeviceTransferSenderCompare
        ? l10n.deviceTransferCompareTitle
        : l10n.deviceTransferSettingsTitle;
    return AppScreen.appBar(
      floatingActionButton: const FabRegistrar(fab: null),
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
        DeviceTransferSenderReady() => _DevicesBody(
          hasSecretKey: cubit.hasSecretKey,
          onAddDevice: () => _scan(context),
        ),
        DeviceTransferSenderLoading() => const Center(
          child: CircularProgressIndicator(color: AppColors.brandRed),
        ),
        DeviceTransferSenderCompare(:final sas, :final sealing) => _CompareBody(
          sas: sas,
          sealing: sealing,
          onApprove: cubit.approve,
          onReject: cubit.reject,
        ),
        DeviceTransferSenderApproved() => TransferStatusView(
          icon: Icons.devices_outlined,
          iconColor: AppColors.positiveAccent,
          title: l10n.deviceTransferApprovedTitle,
          message: l10n.deviceTransferApprovedBody,
          actionLabel: l10n.deviceTransferDone,
          onAction: () => context.pop(),
        ),
        DeviceTransferSenderRejected() => TransferStatusView(
          icon: Icons.block_outlined,
          iconColor: AppColors.brandRed,
          title: l10n.deviceTransferRejectedTitle,
          message: l10n.deviceTransferRejectedBody,
          actionLabel: l10n.deviceTransferDone,
          onAction: () => context.pop(),
        ),
        DeviceTransferSenderFailed(:final failure) => TransferStatusView(
          icon: failure == DeviceTransferFailure.expired
              ? Icons.timer_off_outlined
              : Icons.error_outline,
          iconColor: AppColors.brandRed,
          title: failure == DeviceTransferFailure.expired
              ? l10n.deviceTransferExpiredTitle
              : l10n.deviceTransferFailedTitle,
          message: transferFailureMessage(l10n, failure),
          actionLabel: failure == DeviceTransferFailure.secretKeyMissing
              ? l10n.deviceTransferDone
              : l10n.deviceTransferScanAgain,
          onAction: failure == DeviceTransferFailure.secretKeyMissing
              ? () => context.pop()
              : () {
                  cubit.restart();
                  _scan(context);
                },
        ),
      },
    );
  }
}

class _DevicesBody extends StatefulWidget {
  const _DevicesBody({required this.hasSecretKey, required this.onAddDevice});

  final Future<bool> Function() hasSecretKey;
  final VoidCallback onAddDevice;

  @override
  State<_DevicesBody> createState() => _DevicesBodyState();
}

class _DevicesBodyState extends State<_DevicesBody> {
  late final Future<bool> _hasSecretKey = widget.hasSecretKey();

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
        TransferIntroText(l10n.deviceTransferDevicesSubtitle),
        const SizedBox(height: AppSpacing.section),
        Text(
          l10n.deviceTransferThisPhone,
          style: TextStyle(
            color: AppColors.onSurfaceMuted(brightness),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        FutureBuilder<bool>(
          future: _hasSecretKey,
          builder: (context, snapshot) {
            final saved = snapshot.data ?? true;
            return Container(
              padding: const EdgeInsets.all(AppSpacing.cardPadding),
              decoration: BoxDecoration(
                color: AppColors.cardFill(brightness),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.cardBorder(brightness)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.smartphone_outlined,
                    color: AppColors.onSurface(brightness),
                    size: 22,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      saved
                          ? l10n.deviceTransferSecretKeySaved
                          : l10n.deviceTransferSecretKeyMissing,
                      style: TextStyle(
                        color: AppColors.onSurface(brightness),
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Text(
                    l10n.deviceTransferCurrent,
                    style: const TextStyle(
                      color: AppColors.positiveAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.section),
        PrimaryButton(
          label: l10n.deviceTransferAddDevice,
          leading: const Icon(
            Icons.qr_code_scanner,
            size: 18,
            color: AppColors.onBrandRed,
          ),
          onPressed: widget.onAddDevice,
        ),
        const SizedBox(height: AppSpacing.md),
        TransferIntroText(l10n.deviceTransferAddDeviceHint),
      ],
    );
  }
}

class _CompareBody extends StatelessWidget {
  const _CompareBody({
    required this.sas,
    required this.sealing,
    required this.onApprove,
    required this.onReject,
  });

  final String sas;
  final bool sealing;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
            children: [
              TransferIntroText(l10n.deviceTransferCompareBody),
              const SizedBox(height: AppSpacing.section),
              SasCodeCard(label: l10n.deviceTransferCodeOnThisPhone, code: sas),
              const SizedBox(height: AppSpacing.section),
              Text(
                l10n.deviceTransferNotYou,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.onSurfaceSubtle(brightness),
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        SheetActionButtons(
          onCancel: onReject,
          onConfirm: onApprove,
          cancelLabel: l10n.deviceTransferReject,
          confirmLabel: l10n.deviceTransferApprove,
          confirmColor: AppColors.positiveAccent,
          busy: sealing,
          equalActions: true,
        ),
      ],
    );
  }
}
