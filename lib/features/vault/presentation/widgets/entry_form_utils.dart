import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/entities/custom_field.dart';
import '../../domain/entities/entry_entity.dart';
import '../../domain/exceptions/entry_exceptions.dart';

/// Pure helper functions shared by Add Entry and Edit Entry pages.
///
/// These were previously copy-pasted 1:1 between `add_entry_page.dart`
/// and `entry_detail_page.dart`. None of them touches widget state — they
/// either map raw text into a domain value or pick a localized string for
/// a given error kind. Keeping them here means both pages compute URL
/// validation, payload shape and error copy from a single source of truth.
class EntryFormUtils {
  EntryFormUtils._();

  /// Returns `true` when [raw] is empty (URL is optional) or when it
  /// parses into a host with at least one dot, the literal `localhost`,
  /// or a bare IPv4/IPv6 address. Used by both forms to decide whether
  /// to block the save action and surface the validation error.
  static bool isValidUrl(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return true;
    final toParse = text.contains('://') ? text : 'https://$text';
    final uri = Uri.tryParse(toParse);
    final host = uri?.host ?? '';
    return host.isNotEmpty &&
        (host == 'localhost' ||
            host.contains('.') ||
            RegExp(r'^\[?[\da-fA-F:]+\]?$').hasMatch(host));
  }

  /// Pulls just the host out of a URL the user typed in. Returns null
  /// when the input is blank or has no usable host. Falls back to a
  /// scheme-stripped first segment when [Uri.parse] cannot recognize the
  /// authority (e.g. `example.com/path` without scheme).
  static String? extractDomain(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    try {
      final uri = Uri.parse(trimmed);
      if (uri.hasAuthority && uri.host.isNotEmpty) return uri.host;
    } on FormatException {
      // fall through to the scheme-strip fallback below
    }
    final withoutScheme =
        trimmed.replaceFirst(RegExp(r'^[a-zA-Z][a-zA-Z0-9+\-.]*://'), '');
    final firstSegment = withoutScheme.split('/').first;
    return firstSegment.isEmpty ? null : firstSegment;
  }

  /// Builds the plaintext payload map (blob schema v2) for the given entry
  /// [type] from the already-trimmed text values plus any custom [fields].
  /// The result is what the cubit will encrypt on-device before sending to
  /// the API.
  ///
  /// [credentialTotp] carries a legacy `otpauth://` TOTP string forward on
  /// a credential edit so it is not silently dropped (v2 moves TOTP into a
  /// custom field, but older imported entries may still carry the flat
  /// field).
  static Map<String, dynamic> buildPayload({
    required EntryType type,
    String value = '',
    String username = '',
    String password = '',
    String url = '',
    String notes = '',
    List<CustomField> fields = const [],
    String script = '',
    ScriptInterpreter interpreter = ScriptInterpreter.bash,
    List<ScriptRef> refs = const [],
    String? credentialTotp,
  }) {
    final urlOrNull = url.trim().isEmpty ? null : url.trim();
    final notesOrNull = notes.trim().isEmpty ? null : notes.trim();
    return switch (type) {
      EntryType.key => KeyPayload(
          value: value.trim(),
          url: urlOrNull,
          notes: notesOrNull,
          fields: fields,
        ).toJson(),
      EntryType.credential => CredentialPayload(
          username: username.trim(),
          password: password.trim(),
          url: urlOrNull,
          notes: notesOrNull,
          totp: credentialTotp,
          fields: fields,
        ).toJson(),
      EntryType.script => ScriptPayload(
          script: script.trim(),
          interpreter: interpreter,
          notes: notesOrNull,
          refs: refs,
          fields: fields,
        ).toJson(),
    };
  }

  /// Returns `true` when the user can submit the form: label is non-empty
  /// and the type-specific required field(s) are non-empty.
  static bool canSubmit({
    required EntryType type,
    required String label,
    String value = '',
    String username = '',
    String password = '',
    String script = '',
  }) {
    if (label.trim().isEmpty) return false;
    return switch (type) {
      EntryType.key => value.trim().isNotEmpty,
      EntryType.credential =>
        username.trim().isNotEmpty && password.trim().isNotEmpty,
      EntryType.script => script.trim().isNotEmpty,
    };
  }

  /// Maps an [EntryErrorKind] to a localized error string. Used directly
  /// under the save button on both Add Entry and Edit Entry forms.
  static String errorMessage(AppLocalizations l10n, EntryErrorKind kind) =>
      switch (kind) {
        EntryErrorKind.notFound => l10n.entryErrorNotFound,
        EntryErrorKind.forbidden => l10n.entryErrorForbidden,
        EntryErrorKind.validation => l10n.entryErrorValidation,
        EntryErrorKind.cryptoFailure => l10n.entryErrorCrypto,
        EntryErrorKind.networkError => l10n.errorCannotConnectToServer,
        EntryErrorKind.unknown => l10n.entryErrorUnknown,
      };
}
