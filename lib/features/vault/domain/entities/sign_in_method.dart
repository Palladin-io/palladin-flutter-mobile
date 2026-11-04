import 'dart:convert';

import 'package:unorm_dart/unorm_dart.dart' as unicode;

import 'custom_field.dart';
import 'entry_entity.dart';

/// Closed set of external sign-in providers in `palladin.signin.v1`.
enum SignInProvider {
  google({'google.com'}),
  apple({'apple.com'}),
  microsoft({'live.com', 'microsoftonline.com', 'microsoft.com'}),
  github({'github.com'}),
  facebook({'facebook.com'});

  const SignInProvider(this.accountDomains);

  /// Registrable domains whose Credentials are candidate provider accounts.
  final Set<String> accountDomains;

  String get wireName => name;

  /// Whether [host] belongs to one of [accountDomains]. Every listed domain is
  /// itself a registrable domain, so an exact or subdomain match is exactly
  /// "its registrable domain is one of the provider account domains".
  bool ownsHost(String host) {
    final normalized = host.toLowerCase();
    return accountDomains.any(
      (domain) => normalized == domain || normalized.endsWith('.$domain'),
    );
  }

  static SignInProvider? tryParse(Object? raw) {
    for (final provider in values) {
      if (provider.wireName == raw) return provider;
    }
    return null;
  }
}

/// The provider Credential an Agent may request a grant for.
final class SignInEntryReference {
  const SignInEntryReference({required this.vaultId, required this.entryId});

  final String vaultId;
  final String entryId;

  Map<String, Object?> toValue() => {'vaultId': vaultId, 'entryId': entryId};

  @override
  bool operator ==(Object other) =>
      other is SignInEntryReference &&
      other.vaultId == vaultId &&
      other.entryId == entryId;

  @override
  int get hashCode => Object.hash(vaultId, entryId);
}

/// The remembered way the user signs in to the Credential's external service.
final class SignInMethodBinding {
  const SignInMethodBinding({required this.provider, this.account, this.entry});

  final SignInProvider provider;

  /// Provider account as confirmed by the user, or null when not specified.
  final String? account;

  /// Set only when the user explicitly chose an existing discoverable
  /// Palladin Credential of this provider.
  final SignInEntryReference? entry;

  Map<String, Object?> toValue() => {
    'provider': provider.wireName,
    'account': account,
    'entry': entry?.toValue(),
  };

  @override
  bool operator ==(Object other) =>
      other is SignInMethodBinding &&
      other.provider == provider &&
      other.account == account &&
      other.entry == entry;

  @override
  int get hashCode => Object.hash(provider, account, entry);
}

/// Result of reading the sign-in method of one Entry.
sealed class SignInMethodState {
  const SignInMethodState();
}

/// No binding, or an Entry type on which the binding has no meaning.
final class SignInMethodAbsent extends SignInMethodState {
  const SignInMethodAbsent();
}

/// Exactly one well-formed binding.
final class SignInMethodRecognized extends SignInMethodState {
  const SignInMethodRecognized({required this.fieldId, required this.binding});

  final String fieldId;
  final SignInMethodBinding binding;
}

/// Exactly one binding field whose value this client does not understand.
/// It is shown neutrally and never used for suggestions.
final class SignInMethodUnrecognized extends SignInMethodState {
  const SignInMethodUnrecognized();
}

/// More than one binding field; none of them is used.
final class SignInMethodAmbiguous extends SignInMethodState {
  const SignInMethodAmbiguous(this.count);

  final int count;
}

/// Rejected user input for a new binding.
enum SignInAccountError { tooLong }

/// Reads and replaces the canonical `palladin.signin.v1` custom field.
abstract final class SignInMethodField {
  static const type = 'palladin.signin.v1';
  static const discoveryFieldId = 'signIn';
  static const maxAccountLength = 256;

  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  /// Classifies the binding carried by [fields] of an Entry of [entryType].
  static SignInMethodState read({
    required EntryType entryType,
    required List<CustomField> fields,
  }) {
    if (entryType != EntryType.credential) return const SignInMethodAbsent();
    final matches = fields.where((field) => field.rawType == type).toList();
    if (matches.isEmpty) return const SignInMethodAbsent();
    if (matches.length > 1) return SignInMethodAmbiguous(matches.length);
    final binding = parseValue(matches.single.value);
    return binding == null
        ? const SignInMethodUnrecognized()
        : SignInMethodRecognized(fieldId: matches.single.id, binding: binding);
  }

  /// Strictly parses a field value; anything outside the contract (including
  /// the retired two-key shape) is null.
  static SignInMethodBinding? parseValue(Object? value) {
    if (value is! Map || value.length != 3) return null;
    if (!value.containsKey('provider') ||
        !value.containsKey('account') ||
        !value.containsKey('entry')) {
      return null;
    }
    final provider = SignInProvider.tryParse(value['provider']);
    if (provider == null) return null;
    final account = value['account'];
    if (account != null &&
        (account is! String || !_isCanonicalAccount(account))) {
      return null;
    }
    final rawEntry = value['entry'];
    SignInEntryReference? entry;
    if (rawEntry != null) {
      if (rawEntry is! Map ||
          rawEntry.length != 2 ||
          !_isUuid(rawEntry['vaultId']) ||
          !_isUuid(rawEntry['entryId'])) {
        return null;
      }
      entry = SignInEntryReference(
        vaultId: rawEntry['vaultId'] as String,
        entryId: rawEntry['entryId'] as String,
      );
    }
    return SignInMethodBinding(
      provider: provider,
      account: account as String?,
      entry: entry,
    );
  }

  /// Agent access modes admitted for a binding field. Discovery requires a
  /// Credential and a well-formed value; Agents never receive a grant value.
  static bool allowsDiscovery({
    required bool credential,
    required Object? value,
  }) => credential && parseValue(value) != null;

  /// Canonical sorted-key JSON carried as the Discovery `signIn` value. It
  /// never contains the provider account.
  static String discoveryValue(SignInMethodBinding binding) => jsonEncode({
    'entry': switch (binding.entry) {
      null => null,
      final entry => {'entryId': entry.entryId, 'vaultId': entry.vaultId},
    },
    'provider': binding.provider.wireName,
    'schema': type,
  });

  /// Normalizes user input to the stored account form. Blank input means
  /// "not specified".
  static String? normalizeAccount(String raw) {
    final normalized = unicode.nfc(raw).trim();
    if (normalized.isEmpty) return null;
    if (normalized.length > maxAccountLength) {
      throw const SignInAccountException(SignInAccountError.tooLong);
    }
    return normalized;
  }

  /// Removes every binding field and, when [binding] is given, appends
  /// exactly one new field. All other fields keep their order and values.
  static List<CustomField> replace(
    List<CustomField> fields, {
    required SignInMethodBinding? binding,
    required String label,
    required String newId,
  }) => [
    for (final field in fields)
      if (field.rawType != type) field,
    if (binding != null)
      CustomField(
        id: newId,
        label: label,
        type: CustomFieldType.unknown,
        rawType: type,
        value: binding.toValue(),
      ),
  ];

  static bool _isUuid(Object? value) =>
      value is String && _uuid.hasMatch(value);

  static bool _isCanonicalAccount(String account) =>
      account.isNotEmpty &&
      account.length <= maxAccountLength &&
      account == unicode.nfc(account).trim();
}

/// Typed failure for sign-in method input.
final class SignInAccountException implements Exception {
  const SignInAccountException(this.kind);

  final SignInAccountError kind;
}
