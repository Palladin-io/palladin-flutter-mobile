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
      (wire: 'key.value', label: l10n.entryValueLabel),
      (wire: 'key.url', label: l10n.entryUrlLabel),
      (wire: 'notes', label: l10n.entryNotesLabel),
    ],
    EntryType.credential => [
      (wire: 'credential.username', label: l10n.entryUsernameLabel),
      (wire: 'credential.password', label: l10n.entryPasswordLabel),
      (wire: 'credential.url', label: l10n.entryUrlLabel),
      (wire: 'notes', label: l10n.entryNotesLabel),
    ],
    EntryType.script => const [],
    // Card fields are not valid script references; grant methods are selected
    // independently from the Entry type.
    EntryType.creditCard => const [],
  };
}
