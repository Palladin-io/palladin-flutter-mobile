import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/sheet_action_buttons.dart';
import '../../../../core/widgets/sheet_drag_handle.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../onboarding/presentation/widgets/onboarding_text_field.dart';
import '../../domain/entities/totp_config.dart';
import '../pages/totp_scanner_page.dart';

/// Bottom sheet that captures a TOTP secret three ways (spec §CVT-176):
/// scan a QR code, paste an `otpauth://` URI, or type a base32 secret with
/// optional issuer/account. Returns the parsed [TotpConfig] or null on
/// cancel. The secret never leaves this flow except inside the returned
/// config.
class TotpSetupSheet {
  const TotpSetupSheet._();

  static Future<TotpConfig?> show(
    BuildContext context, {
    TotpConfig? initial,
  }) {
    return showModalBottomSheet<TotpConfig>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TotpSetupBody(initial: initial),
    );
  }
}

class _TotpSetupBody extends StatefulWidget {
  const _TotpSetupBody({this.initial});

  final TotpConfig? initial;

  @override
  State<_TotpSetupBody> createState() => _TotpSetupBodyState();
}

class _TotpSetupBodyState extends State<_TotpSetupBody> {
  late final TextEditingController _keyController;
  late final TextEditingController _issuerController;
  late final TextEditingController _accountController;
  bool _showError = false;

  @override
  void initState() {
    super.initState();
    _keyController = TextEditingController(text: widget.initial?.secret ?? '');
    _issuerController =
        TextEditingController(text: widget.initial?.issuer ?? '');
    _accountController =
        TextEditingController(text: widget.initial?.account ?? '');
  }

  @override
  void dispose() {
    _keyController.dispose();
    _issuerController.dispose();
    _accountController.dispose();
    super.dispose();
  }

  /// Parses the current inputs into a config. Accepts either an
  /// `otpauth://` URI (issuer/account come from the URI) or a raw base32
  /// secret (issuer/account come from the two optional fields).
  TotpConfig? _parse() {
    final raw = _keyController.text.trim();
    if (raw.isEmpty) return null;
    if (raw.toLowerCase().startsWith('otpauth://')) {
      return TotpConfig.parseUri(raw);
    }
    return TotpConfig.fromSecret(
      raw,
      issuer: _issuerController.text,
      account: _accountController.text,
    );
  }

  void _submit() {
    final config = _parse();
    if (config == null) {
      setState(() => _showError = true);
      return;
    }
    Navigator.of(context).pop(config);
  }

  Future<void> _scan() async {
    final scanned = await TotpScannerPage.push(context);
    if (scanned == null || !mounted) return;
    final config = TotpConfig.parseUri(scanned);
    if (config == null) {
      setState(() {
        _keyController.text = scanned;
        _showError = true;
      });
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(config);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.modalBackground(brightness),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Center(child: SheetDragHandle()),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenH,
              AppSpacing.sm,
              AppSpacing.screenH,
              AppSpacing.section,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.totpSetupTitle,
                  style: TextStyle(
                    color: AppColors.onSurface(brightness),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.section),
                SizedBox(
                  height: AppSpacing.controlHeight,
                  child: OutlinedButton.icon(
                    onPressed: _scan,
                    icon: const Icon(Icons.qr_code_scanner, size: 18),
                    label: Text(l10n.totpScanQr),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.brandRed,
                      side: BorderSide(
                        color: AppColors.brandRed.withValues(alpha: 0.5),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.section),
                _OrDivider(label: l10n.totpOr, brightness: brightness),
                const SizedBox(height: AppSpacing.section),
                OnboardingTextField(
                  label: l10n.totpSetupKeyLabel,
                  hintText: l10n.totpSetupKeyHint,
                  controller: _keyController,
                  textInputAction: TextInputAction.next,
                  borderColor: _showError ? AppColors.brandRed : null,
                  focusBorderColor: _showError ? AppColors.brandRed : null,
                  onChanged: (_) {
                    if (_showError) setState(() => _showError = false);
                  },
                  feedbackChild: Text(
                    l10n.totpInvalidKey,
                    style: const TextStyle(
                      color: AppColors.brandRed,
                      fontSize: 11,
                    ),
                  ),
                  feedbackVisible: _showError,
                  feedbackReserveSpace: false,
                ),
                const SizedBox(height: AppSpacing.fieldGap),
                OnboardingTextField(
                  label: l10n.totpIssuerLabel,
                  controller: _issuerController,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: AppSpacing.fieldGap),
                OnboardingTextField(
                  label: l10n.totpAccountLabel,
                  controller: _accountController,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                ),
              ],
            ),
          ),
          SheetActionButtons(
            onCancel: () => Navigator.of(context).pop(),
            onConfirm: _submit,
            confirmLabel: l10n.entrySaveAction,
            confirmColor: AppColors.brandRed,
          ),
        ],
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider({required this.label, required this.brightness});

  final String label;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final line = Expanded(
      child: Divider(
        color: AppColors.onSurface(brightness).withValues(alpha: 0.12),
        thickness: 1,
      ),
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
