import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_action_footer.dart';
import '../../../../core/widgets/app_dropdown_field.dart';
import '../../../../core/widgets/app_form_section.dart';
import '../../../../core/widgets/app_toggle.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../onboarding/presentation/widgets/onboarding_text_field.dart';
import '../../domain/entities/entry_share_creation.dart';
import '../../domain/entities/entry_share_selection.dart';
import '../../domain/entities/entry_entity.dart';
import '../../domain/entities/vault_entity.dart';
import 'vault_visuals.dart';

class EntryShareCreationForm extends StatefulWidget {
  const EntryShareCreationForm({
    super.key,
    required this.selection,
    required this.entry,
    this.vault,
    required this.busy,
    required this.onCreate,
    this.failure,
  });
  final EntryShareSelection selection;
  final EntryEntity entry;
  final VaultEntity? vault;
  final bool busy;
  final String? failure;
  final ValueChanged<EntryShareCreationOptions> onCreate;

  @override
  State<EntryShareCreationForm> createState() => _EntryShareCreationFormState();
}

class _EntryShareCreationFormState extends State<EntryShareCreationForm> {
  final _email = TextEditingController();
  final _secret = TextEditingController();
  final _confirmation = TextEditingController();
  bool _confirmationError = false;
  final _limit = TextEditingController();
  EntryShareRecipientMode _recipient = EntryShareRecipientMode.anyoneWithLink;
  EntryShareProtection _protection = EntryShareProtection.none;
  EntryShareFormError? _error;
  int _hours = 24;
  bool _notify = false;

  @override
  void dispose() {
    for (final controller in [_email, _secret, _confirmation, _limit]) {
      controller.clear();
      controller.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (widget.busy ||
        widget.selection.unsupported.isNotEmpty ||
        widget.selection.choices.isEmpty) {
      return;
    }
    try {
      final options = EntryShareCreationOptions.fromInput(
        recipientMode: _recipient,
        recipientEmail: _email.text,
        protection: _protection,
        protectionSecret: _secret.text,
        lifetimeHours: _hours,
        maximumReceipts: _limit.text,
        notifyOnFirstReceipt: _notify,
      );
      if (_protection != EntryShareProtection.none &&
          _secret.text != _confirmation.text) {
        setState(() => _confirmationError = true);
        return;
      }
      setState(() => _error = null);
      FocusScope.of(context).unfocus();
      widget.onCreate(options);
    } on EntryShareFormException catch (error) {
      setState(() => _error = error.kind);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final enabled = !widget.busy;
    final vaultId = widget.entry.vaultId;
    final vaultName =
        widget.vault?.name ??
        (vaultId.length <= 15
            ? vaultId
            : '${vaultId.substring(0, 8)}…${vaultId.substring(vaultId.length - 6)}');
    String errorText(EntryShareFormError kind) => switch (kind) {
      EntryShareFormError.email => l10n.sharingEmailError,
      EntryShareFormError.password => l10n.sharingPasswordError,
      EntryShareFormError.pin => l10n.sharingPinError,
      EntryShareFormError.maximumReceipts => l10n.sharingLimitError,
      EntryShareFormError.lifetime => l10n.sharingLifetimeError,
    };
    Widget input(
      TextEditingController controller,
      String label,
      EntryShareFormError kind, {
      bool secret = false,
      TextInputType? keyboard,
      String? hint,
    }) => OnboardingTextField(
      controller: controller,
      label: label,
      enabled: enabled,
      obscureText: secret,
      keyboardType: keyboard,
      hintText: hint,
      feedbackVisible: _error == kind,
      feedbackReserveSpace: false,
      feedbackChild: Text(
        errorText(kind),
        style: const TextStyle(fontSize: 12, color: AppColors.brandRed),
      ),
      onChanged: (_) {
        setState(() {
          if (_error == kind) _error = null;
        });
      },
    );
    Widget note(String text) => Text(
      text,
      style: TextStyle(
        fontSize: 13,
        color: AppColors.onSurfaceSubtle(brightness),
      ),
    );
    Widget choice(String label, bool value, ValueChanged<bool> changed) => Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.onSurface(brightness),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.innerGap),
        Semantics(
          label: label,
          toggled: value,
          enabled: enabled,
          child: AppToggle(value: value, onChanged: enabled ? changed : null),
        ),
      ],
    );
    const gap = SizedBox(height: AppSpacing.fieldGap);
    final protectionLabel = switch (_protection) {
      EntryShareProtection.none => l10n.sharingNoProtection,
      EntryShareProtection.password => l10n.sharingProtectionPassword,
      EntryShareProtection.pin => l10n.sharingProtectionPin,
    };
    final lifetimeLabel = switch (_hours) {
      1 => l10n.sharingLifetimeHour,
      72 => l10n.sharingLifetimeThreeDays,
      168 => l10n.sharingLifetimeWeek,
      _ => l10n.sharingLifetimeDay,
    };
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
            children: [
              Row(
                children: [
                  Icon(
                    EntryVisuals.iconFor(
                      widget.entry.icon ??
                          EntryVisuals.defaultIconForType(widget.entry.type),
                    ),
                    size: 20,
                    color: AppColors.onSurface(brightness),
                  ),
                  const SizedBox(width: AppSpacing.innerGap),
                  Expanded(
                    child: Text(
                      widget.selection.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface(brightness),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.section),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Icon(
                          VaultVisuals.iconFor(widget.vault?.icon),
                          size: 14,
                          color: AppColors.onSurfaceSubtle(brightness),
                        ),
                        const SizedBox(width: AppSpacing.innerGap),
                        Flexible(
                          child: Text(
                            vaultName,
                            textAlign: TextAlign.end,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.onSurfaceSubtle(brightness),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              gap,
              note(l10n.sharingCreateNotice),
              for (final field in widget.selection.unsupported)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.cardGap),
                  child: note(
                    '${entryShareFieldLabel(l10n, field.id, field.label)} — ${l10n.sharingUnsupportedField}',
                  ),
                ),
              AppFormSection(
                label: l10n.sharingRecipientSection,
                summary: _recipient == EntryShareRecipientMode.anyoneWithLink
                    ? l10n.sharingAnyone
                    : (_email.text.isEmpty
                          ? l10n.sharingNamedRecipient
                          : _email.text),
                error: _error == EntryShareFormError.email
                    ? errorText(_error!)
                    : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppDropdownField<EntryShareRecipientMode>(
                      label: l10n.sharingRecipient,
                      value: _recipient,
                      enabled: enabled,
                      items: [
                        DropdownMenuItem(
                          value: EntryShareRecipientMode.namedRecipient,
                          child: Text(
                            l10n.sharingNamedRecipient,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: EntryShareRecipientMode.anyoneWithLink,
                          child: Text(
                            l10n.sharingAnyone,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _recipient = value;
                            _email.clear();
                            _error = null;
                          });
                        }
                      },
                    ),
                    gap,
                    if (_recipient ==
                        EntryShareRecipientMode.namedRecipient) ...[
                      input(
                        _email,
                        l10n.sharingEmail,
                        EntryShareFormError.email,
                        keyboard: TextInputType.emailAddress,
                      ),
                      gap,
                      note(l10n.sharingEmailNotice),
                    ] else
                      note(l10n.sharingAnyoneWarning),
                  ],
                ),
              ),
              AppFormSection(
                label: l10n.sharingSecuritySection,
                summary: protectionLabel,
                error:
                    _error == EntryShareFormError.pin ||
                        _error == EntryShareFormError.password
                    ? errorText(_error!)
                    : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppDropdownField<EntryShareProtection>(
                      label: l10n.sharingProtection,
                      value: _protection,
                      enabled: enabled,
                      items: [
                        DropdownMenuItem(
                          value: EntryShareProtection.none,
                          child: Text(
                            l10n.sharingProtectionNone,
                            overflow: TextOverflow.ellipsis,
                          ),
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
                        if (value != null) {
                          setState(() {
                            _protection = value;
                            _secret.clear();
                            _confirmation.clear();
                            _confirmationError = false;
                            _error = null;
                          });
                        }
                      },
                    ),
                    if (_protection != EntryShareProtection.none) ...[
                      gap,
                      input(
                        _secret,
                        _protection == EntryShareProtection.pin
                            ? l10n.sharingProtectionPin
                            : l10n.sharingProtectionPassword,
                        _protection == EntryShareProtection.pin
                            ? EntryShareFormError.pin
                            : EntryShareFormError.password,
                        secret: true,
                        keyboard: _protection == EntryShareProtection.pin
                            ? TextInputType.number
                            : TextInputType.visiblePassword,
                      ),
                      gap,
                      OnboardingTextField(
                        controller: _confirmation,
                        label: l10n.sharingConfirmSecret,
                        enabled: enabled,
                        obscureText: true,
                        keyboardType: _protection == EntryShareProtection.pin
                            ? TextInputType.number
                            : TextInputType.visiblePassword,
                        feedbackVisible: _confirmationError,
                        feedbackReserveSpace: false,
                        feedbackChild: Text(
                          l10n.sharingSecretMismatch,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.brandRed,
                          ),
                        ),
                        onChanged: (_) =>
                            setState(() => _confirmationError = false),
                      ),
                      gap,
                      note(l10n.sharingSecretNotice),
                      if (_protection == EntryShareProtection.pin) ...[
                        gap,
                        note(l10n.sharingPinWarning),
                      ],
                    ],
                  ],
                ),
              ),
              AppFormSection(
                label: l10n.sharingLifetime,
                summary: lifetimeLabel,
                child: AppDropdownField<int>(
                  label: l10n.sharingLifetime,
                  value: _hours,
                  enabled: enabled,
                  items: [
                    DropdownMenuItem(
                      value: 1,
                      child: Text(l10n.sharingLifetimeHour),
                    ),
                    DropdownMenuItem(
                      value: 24,
                      child: Text(l10n.sharingLifetimeDay),
                    ),
                    DropdownMenuItem(
                      value: 72,
                      child: Text(l10n.sharingLifetimeThreeDays),
                    ),
                    DropdownMenuItem(
                      value: 168,
                      child: Text(l10n.sharingLifetimeWeek),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _hours = value);
                  },
                ),
              ),
              AppFormSection(
                label: l10n.sharingMaximumReceipts,
                summary: _limit.text.trim().isEmpty
                    ? l10n.sharingUnlimited
                    : _limit.text,
                error: _error == EntryShareFormError.maximumReceipts
                    ? errorText(_error!)
                    : null,
                child: input(
                  _limit,
                  l10n.sharingMaximumReceipts,
                  EntryShareFormError.maximumReceipts,
                  keyboard: TextInputType.number,
                  hint: l10n.sharingUnlimited,
                ),
              ),
              const SizedBox(height: AppSpacing.section),
              choice(
                l10n.sharingNotifyChoice,
                _notify,
                (value) => setState(() => _notify = value),
              ),
              if (widget.failure != null) ...[
                gap,
                Text(
                  widget.failure!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.brandRed,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.section),
            ],
          ),
        ),
        EntryShareActionFooter(
          label: l10n.sharingCreate,
          busy: widget.busy,
          onPressed:
              enabled &&
                  widget.selection.unsupported.isEmpty &&
                  widget.selection.choices.isNotEmpty
              ? _submit
              : null,
        ),
      ],
    );
  }
}

class EntryShareActionFooter extends StatelessWidget {
  const EntryShareActionFooter({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  @override
  Widget build(BuildContext context) => AppActionFooter(
    child: PrimaryButton(label: label, onPressed: onPressed, isLoading: busy),
  );
}

String entryShareFieldLabel(AppLocalizations l10n, String id, String label) =>
    switch (id) {
      'credential.username' => l10n.entryUsernameLabel,
      'credential.password' => l10n.entryPasswordLabel,
      'credential.url' || 'key.url' => l10n.entryUrlLabel,
      'credential.totp' => l10n.sharingTotpSource,
      'key.value' => l10n.entryValueLabel,
      'script.source' => l10n.entryScriptLabel,
      'script.interpreter' => l10n.entryInterpreterLabel,
      'creditCard.cardholderName' => l10n.entryCardholderNameLabel,
      'creditCard.cardNumber' => l10n.entryCardNumberLabel,
      'creditCard.cvv' => l10n.entryCvvLabel,
      'creditCard.expiryMonth' => l10n.entryExpiryMonthLabel,
      'creditCard.expiryYear' => l10n.entryExpiryYearLabel,
      'creditCard.billingAddress' => l10n.entryBillingAddressLabel,
      'description' => l10n.entryDescriptionLabel,
      'notes' => l10n.entryNotesLabel,
      _ => label,
    };
