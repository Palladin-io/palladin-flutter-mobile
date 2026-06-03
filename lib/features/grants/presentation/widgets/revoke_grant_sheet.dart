import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../onboarding/presentation/widgets/onboarding_text_field.dart';
import '../../../onboarding/presentation/widgets/primary_button.dart';

/// Result of the revoke confirmation sheet: the user confirmed, optionally
/// with a [reason].
class RevokeGrantResult {
  const RevokeGrantResult({this.reason});

  /// Optional trimmed reason, or `null` when left blank.
  final String? reason;
}

/// Confirmation bottom sheet shown before revoking a grant.
///
/// Resolves to a [RevokeGrantResult] when confirmed, or `null` when the
/// user cancels / dismisses.
class RevokeGrantSheet extends StatefulWidget {
  const RevokeGrantSheet({super.key, required this.agentName});

  final String agentName;

  static Future<RevokeGrantResult?> show(
    BuildContext context,
    String agentName,
  ) {
    return showModalBottomSheet<RevokeGrantResult>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RevokeGrantSheet(agentName: agentName),
    );
  }

  @override
  State<RevokeGrantSheet> createState() => _RevokeGrantSheetState();
}

class _RevokeGrantSheetState extends State<RevokeGrantSheet> {
  final TextEditingController _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  void _confirm() {
    final reason = _reasonController.text.trim();
    Navigator.of(context).pop(
      RevokeGrantResult(reason: reason.isEmpty ? null : reason),
    );
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
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom +
              MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.onSurfaceSubtle(brightness)
                        .withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                l10n.grantsRevokeConfirmTitle,
                style: TextStyle(
                  color: AppColors.onSurface(brightness),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.grantsRevokeConfirmBody(widget.agentName),
                style: TextStyle(
                  color: AppColors.onSurfaceMuted(brightness),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              OnboardingTextField(
                controller: _reasonController,
                label: l10n.grantsRevokeReasonLabel,
                hintText: l10n.grantsRevokeReasonHint,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 20),
              PrimaryButton(
                label: l10n.grantsRevoke,
                onPressed: _confirm,
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.onSurface(brightness),
                  side: BorderSide(color: AppColors.onSurface(brightness)),
                  minimumSize: const Size(double.infinity, 44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  l10n.apiKeysCancel,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
