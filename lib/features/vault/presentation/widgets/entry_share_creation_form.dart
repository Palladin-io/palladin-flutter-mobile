import 'package:flutter/material.dart';
import 'entry_share_field_card.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_dropdown_field.dart';
import '../../../../core/widgets/app_toggle.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/warning_zone.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../onboarding/presentation/widgets/onboarding_text_field.dart';
import '../../domain/entities/entry_share_creation.dart';
import '../../domain/entities/entry_share_selection.dart';

class EntryShareCreationForm extends StatefulWidget {
  const EntryShareCreationForm({
    super.key,
    required this.selection,
    required this.busy,
    required this.onCreate,
    this.failure,
  });
  final EntryShareSelection selection;
  final bool busy;
  final String? failure;
  final void Function(EntryShareCreationOptions, Set<String>) onCreate;

  @override
  State<EntryShareCreationForm> createState() => _EntryShareCreationFormState();
}

class _EntryShareCreationFormState extends State<EntryShareCreationForm> {
  final _email = TextEditingController();
  final _secret = TextEditingController();
  final _limit = TextEditingController(text: '1');
  late final Set<String> _selected;
  EntryShareRecipientMode _recipient = EntryShareRecipientMode.namedRecipient;
  EntryShareProtection _protection = EntryShareProtection.none;
  EntryShareFormError? _error;
  int _hours = 24;
  bool _notify = false, _reviewed = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.selection.choices
        .where((field) => field.selectedByDefault)
        .map((field) => field.id)
        .toSet();
  }

  @override
  void dispose() {
    for (final controller in [_email, _secret, _limit]) {
      controller.clear();
      controller.dispose();
    }
    _selected.clear();
    super.dispose();
  }

  void _submit() {
    if (widget.busy || !_reviewed || _selected.isEmpty) return;
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
      setState(() => _error = null);
      FocusScope.of(context).unfocus();
      widget.onCreate(options, Set.unmodifiable(_selected));
    } on EntryShareFormException catch (error) {
      setState(() => _error = error.kind);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final enabled = !widget.busy;
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
    }) => OnboardingTextField(
      controller: controller,
      label: label,
      enabled: enabled,
      obscureText: secret,
      keyboardType: keyboard,
      feedbackVisible: _error == kind,
      feedbackReserveSpace: false,
      feedbackChild: Text(
        errorText(kind),
        style: const TextStyle(fontSize: 12, color: AppColors.brandRed),
      ),
      onChanged: (_) {
        if (_error == kind) setState(() => _error = null);
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
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
            children: [
              Text(
                widget.selection.title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface(brightness),
                ),
              ),
              gap,
              note(l10n.sharingCreateNotice),
              gap,
              Text(
                l10n.sharingSelectFields,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface(brightness),
                ),
              ),
              gap,
              note(l10n.sharingSelectNotice),
              gap,
              for (final field in widget.selection.choices)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.cardGap),
                  child: _FieldChoice(
                    key: ValueKey(field.id),
                    field: field,
                    selected: _selected.contains(field.id),
                    enabled: enabled,
                    onChanged: (selected) => setState(() {
                      selected
                          ? _selected.add(field.id)
                          : _selected.remove(field.id);
                      _reviewed = false;
                    }),
                  ),
                ),
              for (final field in widget.selection.unsupported)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.cardGap),
                  child: note(
                    '${entryShareFieldLabel(l10n, field.id, field.label)} — ${l10n.sharingUnsupportedField}',
                  ),
                ),
              gap,
              choice(
                l10n.sharingPreviewConfirmed,
                _reviewed,
                (value) => setState(() => _reviewed = value),
              ),
              const SizedBox(height: AppSpacing.section),
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
              if (_recipient == EntryShareRecipientMode.namedRecipient) ...[
                input(
                  _email,
                  l10n.sharingEmail,
                  EntryShareFormError.email,
                  keyboard: TextInputType.emailAddress,
                ),
                gap,
                note(l10n.sharingEmailNotice),
              ] else
                WarningZone(
                  title: l10n.sharingAnyoneTitle,
                  message: l10n.sharingAnyoneWarning,
                ),
              const SizedBox(height: AppSpacing.section),
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
                note(l10n.sharingSecretNotice),
                if (_protection == EntryShareProtection.pin) ...[
                  gap,
                  WarningZone(
                    title: l10n.sharingProtectionPin,
                    message: l10n.sharingPinWarning,
                  ),
                ],
              ],
              const SizedBox(height: AppSpacing.section),
              AppDropdownField<int>(
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
              gap,
              input(
                _limit,
                l10n.sharingMaximumReceipts,
                EntryShareFormError.maximumReceipts,
                keyboard: TextInputType.number,
              ),
              const SizedBox(height: AppSpacing.section),
              choice(
                l10n.sharingNotifyChoice,
                _notify,
                (value) => setState(() => _notify = value),
              ),
              gap,
              note(l10n.sharingNotifyNotice),
              gap,
              note(l10n.sharingCancelNotice),
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
          onPressed: enabled && _reviewed && _selected.isNotEmpty
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
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        AppSpacing.md,
        AppSpacing.screenH,
        AppSpacing.screenBottom,
      ),
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        border: Border(top: BorderSide(color: AppColors.navBorder(brightness))),
      ),
      child: PrimaryButton(label: label, onPressed: onPressed, isLoading: busy),
    );
  }
}

class _FieldChoice extends StatelessWidget {
  const _FieldChoice({
    super.key,
    required this.field,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });
  final EntryShareFieldChoice field;
  final bool selected, enabled;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final label = entryShareFieldLabel(l10n, field.id, field.label);
    return EntryShareFieldCard(
      label: label,
      type: field.type,
      value: field.value,
      enabled: enabled,
      trailing: Semantics(
        label: label,
        toggled: selected,
        enabled: enabled,
        child: AppToggle(
          value: selected,
          onChanged: enabled ? onChanged : null,
        ),
      ),
    );
  }
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
      'creditCard.expiryMonth' => l10n.entryExpiryMonthLabel,
      'creditCard.expiryYear' => l10n.entryExpiryYearLabel,
      'creditCard.billingAddress' => l10n.entryBillingAddressLabel,
      'description' => l10n.entryDescriptionLabel,
      'notes' => l10n.entryNotesLabel,
      _ => label,
    };
