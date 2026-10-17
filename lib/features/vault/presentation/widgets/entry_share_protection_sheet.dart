import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/accent_button.dart';
import '../../../../core/widgets/app_action_footer.dart';
import '../../../../core/widgets/app_dropdown_field.dart';
import '../../../../core/widgets/sheet_surface.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../onboarding/presentation/widgets/onboarding_text_field.dart';
import '../../domain/entities/entry_share_creation.dart';

/// The owner retires this form on lock, identity change or backgrounding.
/// Neither the existing secret nor a new secret is persisted or returned.
class EntryShareProtectionSheet extends StatefulWidget {
  const EntryShareProtectionSheet({
    super.key,
    required this.protection,
    required this.authorityEpoch,
    required this.onSave,
  });
  final EntryShareProtection protection;
  final ValueListenable<int> authorityEpoch;
  final Future<bool> Function(EntryShareProtection protection, String? secret)
  onSave;

  @override
  State<EntryShareProtectionSheet> createState() =>
      _EntryShareProtectionSheetState();
}

class _EntryShareProtectionSheetState extends State<EntryShareProtectionSheet> {
  final _secret = TextEditingController();
  final _confirmation = TextEditingController();
  late EntryShareProtection _protection;
  late int _epoch;
  bool _busy = false,
      _retired = false,
      _mismatch = false,
      _requestError = false;
  EntryShareFormError? _error;

  @override
  void initState() {
    super.initState();
    _protection = widget.protection;
    _epoch = widget.authorityEpoch.value;
    widget.authorityEpoch.addListener(_retire);
  }

  void _retire() {
    if (_epoch == widget.authorityEpoch.value) return;
    _secret.clear();
    _confirmation.clear();
    if (mounted) setState(() => _retired = true);
  }

  @override
  void dispose() {
    widget.authorityEpoch.removeListener(_retire);
    _secret.clear();
    _confirmation.clear();
    _secret.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || _retired) return;
    setState(() {
      _error = null;
      _mismatch = false;
      _requestError = false;
    });
    try {
      EntryShareCreationOptions.fromInput(
        protection: _protection,
        protectionSecret: _secret.text,
      );
    } on EntryShareFormException catch (error) {
      setState(() => _error = error.kind);
      return;
    }
    if (_protection != EntryShareProtection.none &&
        _secret.text != _confirmation.text) {
      setState(() => _mismatch = true);
      return;
    }
    setState(() => _busy = true);
    bool success;
    try {
      success = await widget.onSave(
        _protection,
        _protection == EntryShareProtection.none ? null : _secret.text,
      );
    } catch (_) {
      success = false;
    }
    if (!mounted || _retired || _epoch != widget.authorityEpoch.value) return;
    if (success) {
      _secret.clear();
      _confirmation.clear();
      Navigator.of(context).pop(true);
    } else {
      // A retry requires fresh input; do not keep a submitted secret around.
      _secret.clear();
      _confirmation.clear();
      setState(() {
        _busy = false;
        _requestError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final enabled = !_busy && !_retired;
    final pin = _protection == EntryShareProtection.pin;
    final secretError = switch (_error) {
      EntryShareFormError.pin => l10n.sharingPinError,
      EntryShareFormError.password => l10n.sharingPasswordError,
      _ => null,
    };
    Text feedback(String text) => Text(
      text,
      style: const TextStyle(fontSize: 12, color: AppColors.brandRed),
    );
    return SheetSurface(
      title: l10n.sharingChangeProtection,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.screenH),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.sharingProtectionChangeNotice,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.onSurfaceSubtle(
                        Theme.of(context).brightness,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.section),
                  AppDropdownField<EntryShareProtection>(
                    label: l10n.sharingProtection,
                    value: _protection,
                    enabled: enabled,
                    items: [
                      DropdownMenuItem(
                        value: EntryShareProtection.none,
                        child: Text(l10n.sharingProtectionNone),
                      ),
                      DropdownMenuItem(
                        value: EntryShareProtection.password,
                        child: Text(l10n.sharingProtectionPassword),
                      ),
                      DropdownMenuItem(
                        value: EntryShareProtection.pin,
                        child: Text(l10n.sharingProtectionPin),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _protection = value;
                        _secret.clear();
                        _confirmation.clear();
                        _error = null;
                        _mismatch = _requestError = false;
                      });
                    },
                  ),
                  if (_protection != EntryShareProtection.none) ...[
                    const SizedBox(height: AppSpacing.fieldGap),
                    OnboardingTextField(
                      key: const ValueKey('sharing-protection-secret'),
                      controller: _secret,
                      label: pin
                          ? l10n.sharingProtectionPin
                          : l10n.sharingProtectionPassword,
                      enabled: enabled,
                      obscureText: true,
                      keyboardType: pin
                          ? TextInputType.number
                          : TextInputType.visiblePassword,
                      feedbackVisible: secretError != null,
                      feedbackReserveSpace: false,
                      feedbackChild: secretError == null
                          ? null
                          : feedback(secretError),
                      onChanged: (_) => setState(() => _error = null),
                    ),
                    const SizedBox(height: AppSpacing.fieldGap),
                    OnboardingTextField(
                      key: const ValueKey('sharing-protection-confirmation'),
                      controller: _confirmation,
                      label: l10n.sharingConfirmSecret,
                      enabled: enabled,
                      obscureText: true,
                      keyboardType: pin
                          ? TextInputType.number
                          : TextInputType.visiblePassword,
                      feedbackVisible: _mismatch,
                      feedbackReserveSpace: false,
                      feedbackChild: feedback(l10n.sharingSecretMismatch),
                      onChanged: (_) => setState(() => _mismatch = false),
                    ),
                    const SizedBox(height: AppSpacing.fieldGap),
                    Text(l10n.sharingSecretNotice),
                    if (pin) Text(l10n.sharingPinWarning),
                  ],
                  FieldFeedbackSlot(
                    visible: _retired || _requestError,
                    reserveSpace: false,
                    child: feedback(
                      _retired
                          ? l10n.sharingUnavailable
                          : l10n.sharingProtectionChangeError,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AppActionFooter(
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: AccentButton(
                      height: null,
                      label: l10n.approvalCancel,
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pop(false),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: AccentButton(
                      height: null,
                      label: _busy
                          ? l10n.sharingSavingProtection
                          : l10n.entrySaveAction,
                      onPressed: enabled ? _save : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
