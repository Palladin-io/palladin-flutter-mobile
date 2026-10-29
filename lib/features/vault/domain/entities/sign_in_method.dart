import 'package:unorm_dart/unorm_dart.dart' as unicode;

import 'custom_field.dart';
import 'entry_entity.dart';

/// Closed set of external sign-in providers in `palladin.signin.v1`.
enum SignInProvider {
  google,
  apple,
  microsoft,
  github,
  facebook;

  String get wireName => name;

  static SignInProvider? tryParse(Object? raw) {
    for (final provider in values) {
      if (provider.wireName == raw) return provider;
    }
    return null;
  }
}

/// The remembered way the user signs in to the Credential's external service.
final class SignInMethodBinding {
  const SignInMethodBinding({required this.provider, this.account});

  final SignInProvider provider;

  /// Provider account as confirmed by the user, or null when not specified.
  final String? account;

  Map<String, Object?> toValue() => {
    'provider': provider.wireName,
    'account': account,
  };

  @override
  bool operator ==(Object other) =>
      other is SignInMethodBinding &&
      other.provider == provider &&
      other.account == account;

  @override
  int get hashCode => Object.hash(provider, account);
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
  static const maxAccountLength = 256;

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

  /// Strictly parses a field value; anything outside the contract is null.
  static SignInMethodBinding? parseValue(Object? value) {
    if (value is! Map || value.length != 2) return null;
    if (!value.containsKey('provider') || !value.containsKey('account')) {
      return null;
    }
    final provider = SignInProvider.tryParse(value['provider']);
    if (provider == null) return null;
    final account = value['account'];
    if (account == null) return SignInMethodBinding(provider: provider);
    if (account is! String || !_isCanonicalAccount(account)) return null;
    return SignInMethodBinding(provider: provider, account: account);
  }

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

  static bool _isCanonicalAccount(String account) =>
      account.isNotEmpty &&
      account.length <= maxAccountLength &&
      account == account.trim() &&
      account == unicode.nfc(account);
}

/// Typed failure for sign-in method input.
final class SignInAccountException implements Exception {
  const SignInAccountException(this.kind);

  final SignInAccountError kind;
}
