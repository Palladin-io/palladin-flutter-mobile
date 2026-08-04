import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/entities/entry_entity.dart';

/// An addressable well-known field on an entry: its wire name (the key the
/// agent CLI uses with `--field`) and a localized display label.
typedef WellKnownField = ({String wire, String label});

/// Well-known, agent-addressable fields for a target entry [type] (spec
/// §4). Script entries expose no simple field, so they are not valid
/// reference targets.
List<WellKnownField> wellKnownFieldsFor(EntryType type, AppLocalizations l10n) {
  return switch (type) {
    EntryType.key => [
      (wire: 'value', label: l10n.entryValueLabel),
      (wire: 'url', label: l10n.entryUrlLabel),
      (wire: 'notes', label: l10n.entryNotesLabel),
    ],
    EntryType.credential => [
      (wire: 'username', label: l10n.entryUsernameLabel),
      (wire: 'password', label: l10n.entryPasswordLabel),
      (wire: 'url', label: l10n.entryUrlLabel),
      (wire: 'notes', label: l10n.entryNotesLabel),
    ],
    EntryType.script => const [],
    EntryType.creditCard => [
      (wire: 'cardholderName', label: l10n.entryCardholderNameLabel),
      (wire: 'cardNumber', label: l10n.entryCardNumberLabel),
      (wire: 'expiryMonth', label: l10n.entryExpiryMonthLabel),
      (wire: 'expiryYear', label: l10n.entryExpiryYearLabel),
      (wire: 'securityCode', label: l10n.entrySecurityCodeLabel),
      (wire: 'pin', label: l10n.entryPinLabel),
      (wire: 'billingAddress', label: l10n.entryBillingAddressLabel),
    ],
  };
}
