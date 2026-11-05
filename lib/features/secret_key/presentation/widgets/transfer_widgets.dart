import 'dart:async';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_bar_title.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../cubit/device_transfer_failure.dart';

/// Opens a camera scanner and returns the first decoded QR payload.
/// Injectable so widget tests never start the camera.
typedef QrScanLauncher =
    Future<String?> Function(
      BuildContext context, {
      required String title,
      required String instruction,
    });

Future<String?> launchQrScanner(
  BuildContext context, {
  required String title,
  required String instruction,
}) => Navigator.of(context, rootNavigator: true).push<String>(
  MaterialPageRoute(
    builder: (_) =>
        TransferQrScannerPage(title: title, instruction: instruction),
  ),
);

String transferFailureMessage(
  AppLocalizations l10n,
  DeviceTransferFailure failure,
) => switch (failure) {
  DeviceTransferFailure.invalidCode => l10n.deviceTransferErrorInvalidCode,
  DeviceTransferFailure.codeForSignedInDevice =>
    l10n.deviceTransferErrorCodeForSignedInDevice,
  DeviceTransferFailure.codeForNewDevice =>
    l10n.deviceTransferErrorCodeForNewDevice,
  DeviceTransferFailure.keyMismatch => l10n.deviceTransferErrorKeyMismatch,
  DeviceTransferFailure.accountMismatch =>
    l10n.deviceTransferErrorAccountMismatch,
  DeviceTransferFailure.decryptFailed => l10n.deviceTransferErrorDecrypt,
  DeviceTransferFailure.secretKeyMissing =>
    l10n.deviceTransferErrorSecretKeyMissing,
  DeviceTransferFailure.expired => l10n.deviceTransferExpiredBody,
  DeviceTransferFailure.network => l10n.deviceTransferErrorNetwork,
  DeviceTransferFailure.server => l10n.deviceTransferErrorServer,
};

String transferFailureTitle(
  AppLocalizations l10n,
  DeviceTransferFailure failure,
) => switch (failure) {
  DeviceTransferFailure.expired => l10n.deviceTransferExpiredTitle,
  DeviceTransferFailure.codeForSignedInDevice ||
  DeviceTransferFailure.codeForNewDevice => l10n.deviceTransferWrongCodeTitle,
  _ => l10n.deviceTransferFailedTitle,
};

/// The short authentication string both devices must show identically.
class SasCodeCard extends StatelessWidget {
  const SasCodeCard({super.key, required this.label, required this.code});

  final String label;
  final String code;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder(brightness)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppColors.onSurfaceMuted(brightness),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SelectionContainer.disabled(
            child: Text(
              code,
              key: const Key('transfer-sas'),
              style: TextStyle(
                color: AppColors.onSurface(brightness),
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tappable option row used on the method picker.
class TransferMethodTile extends StatelessWidget {
  const TransferMethodTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        decoration: BoxDecoration(
          color: AppColors.cardFill(brightness),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.cardBorder(brightness)),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.brandRed, size: 22),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: AppColors.onSurface(brightness),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: AppColors.onSurfaceMuted(brightness),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(
              Icons.chevron_right,
              color: AppColors.onSurfaceSubtle(brightness),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

/// Centered terminal state: received, approved, rejected, expired or failed.
/// Without an action it is a transient confirmation.
class TransferStatusView extends StatelessWidget {
  const TransferStatusView({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        0,
        AppSpacing.screenH,
        AppSpacing.screenBottom,
      ),
      child: Column(
        children: [
          const Spacer(),
          Icon(icon, size: 48, color: iconColor),
          const SizedBox(height: AppSpacing.section),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.onSurface(brightness),
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.onSurfaceMuted(brightness),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const Spacer(),
          if (actionLabel case final label?)
            PrimaryButton(label: label, onPressed: onAction),
        ],
      ),
    );
  }
}

/// Muted explanatory paragraph under a screen title.
class TransferIntroText extends StatelessWidget {
  const TransferIntroText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      color: AppColors.onSurfaceMuted(Theme.of(context).brightness),
      fontSize: 13,
      height: 1.4,
    ),
  );
}

/// Counts down to [expiresAt] once per second.
class TransferCountdown extends StatefulWidget {
  const TransferCountdown({super.key, required this.expiresAt});

  final DateTime expiresAt;

  @override
  State<TransferCountdown> createState() => _TransferCountdownState();
}

class _TransferCountdownState extends State<TransferCountdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.expiresAt.difference(DateTime.now());
    final seconds = remaining.isNegative ? 0 : remaining.inSeconds;
    final time =
        '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    final brightness = Theme.of(context).brightness;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.timer_outlined,
          size: 16,
          color: AppColors.onSurfaceSubtle(brightness),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          AppLocalizations.of(context)!.deviceTransferExpiresIn(time),
          style: TextStyle(
            color: AppColors.onSurfaceSubtle(brightness),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

/// Full-screen camera scanner returning the first QR payload.
class TransferQrScannerPage extends StatefulWidget {
  const TransferQrScannerPage({
    super.key,
    required this.title,
    required this.instruction,
  });

  final String title;
  final String instruction;

  @override
  State<TransferQrScannerPage> createState() => _TransferQrScannerPageState();
}

class _TransferQrScannerPageState extends State<TransferQrScannerPage> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null && raw.isNotEmpty) {
        _handled = true;
        Navigator.of(context).pop(raw);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        titleSpacing: 0,
        centerTitle: false,
        leading: const BackButton(color: AppColors.onBrandRed),
        // The camera UI stays dark in both themes.
        title: Theme(
          data: Theme.of(context).copyWith(brightness: Brightness.dark),
          child: AppBarTitle(title: widget.title),
        ),
      ),
      body: MobileScanner(
        controller: _controller,
        onDetect: _onDetect,
        errorBuilder: (context, error) => _CameraError(
          permissionDenied:
              error.errorCode == MobileScannerErrorCode.permissionDenied,
          l10n: l10n,
        ),
        overlayBuilder: (context, _) => Stack(
          fit: StackFit.expand,
          children: [
            const IgnorePointer(
              child: CustomPaint(painter: _ScanFramePainter()),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: const EdgeInsets.fromLTRB(
                  AppSpacing.xxl,
                  0,
                  AppSpacing.xxl,
                  AppSpacing.xxxl,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                decoration: BoxDecoration(
                  color: AppColors.darkBackground.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  widget.instruction,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.onBrandRed,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dims the preview around a rounded square guide; purely visual, the
/// scanner still decodes the whole preview.
class _ScanFramePainter extends CustomPainter {
  const _ScanFramePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final side = (size.shortestSide * 0.68).clamp(180.0, 280.0);
    final frame = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: size.center(Offset.zero),
        width: side,
        height: side,
      ),
      const Radius.circular(24),
    );
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRRect(frame),
      Paint()..color = AppColors.darkBackground.withValues(alpha: 0.55),
    );
    canvas.drawRRect(
      frame,
      Paint()
        ..color = AppColors.onBrandRed
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_ScanFramePainter oldDelegate) => false;
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.permissionDenied, required this.l10n});

  final bool permissionDenied;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.no_photography_outlined,
            size: 40,
            color: AppColors.onBrandRed,
          ),
          const SizedBox(height: AppSpacing.section),
          Text(
            permissionDenied
                ? l10n.deviceTransferCameraDenied
                : l10n.deviceTransferErrorServer,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.onBrandRed, fontSize: 14),
          ),
          if (permissionDenied) ...[
            const SizedBox(height: AppSpacing.section),
            TextButton(
              onPressed: () => AppSettings.openAppSettings(),
              child: Text(
                l10n.deviceTransferOpenSettings,
                style: const TextStyle(color: AppColors.brandRed),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
