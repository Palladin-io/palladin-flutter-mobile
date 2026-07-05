import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/generated/app_localizations.dart';

/// Full-screen camera QR scanner for TOTP setup.
///
/// Pops with the scanned `otpauth://` string on success, or `null` when
/// the user backs out. Camera-permission denial degrades gracefully to an
/// in-screen message with a shortcut to system settings — the caller
/// still offers manual entry (spec §CVT-176).
class TotpScannerPage extends StatefulWidget {
  const TotpScannerPage({super.key});

  static Future<String?> push(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push<String>(
      MaterialPageRoute(builder: (_) => const TotpScannerPage()),
    );
  }

  @override
  State<TotpScannerPage> createState() => _TotpScannerPageState();
}

class _TotpScannerPageState extends State<TotpScannerPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  /// Guards against popping more than once when several frames decode the
  /// same code in quick succession.
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
      if (raw != null && raw.toLowerCase().startsWith('otpauth://')) {
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
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.onBrandRed),
        title: Text(
          l10n.totpScannerTitle,
          style: const TextStyle(
            color: AppColors.onBrandRed,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: MobileScanner(
        controller: _controller,
        onDetect: _onDetect,
        errorBuilder: (context, error) => _ScannerError(
          isPermission:
              error.errorCode == MobileScannerErrorCode.permissionDenied,
          l10n: l10n,
        ),
        overlayBuilder: (context, constraints) => _ScanInstruction(l10n: l10n),
      ),
    );
  }
}

class _ScanInstruction extends StatelessWidget {
  const _ScanInstruction({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: AppColors.darkBackground.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            l10n.totpScanInstruction,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.onBrandRed,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ),
      ),
    );
  }
}

class _ScannerError extends StatelessWidget {
  const _ScannerError({required this.isPermission, required this.l10n});

  final bool isPermission;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Center(
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
              l10n.totpCameraDenied,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.onBrandRed,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            if (isPermission) ...[
              const SizedBox(height: AppSpacing.section),
              TextButton(
                onPressed: () => AppSettings.openAppSettings(),
                child: Text(
                  l10n.totpCameraOpenSettings,
                  style: const TextStyle(
                    color: AppColors.brandRed,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
