import '../../../domain/entities/custom_field.dart';
import '../../../domain/entities/entry_share.dart';
import '../../../domain/entities/entry_share_copy.dart';
import '../../../domain/entities/vault_plaintext.dart';
import 'entry_share_totp_codec.dart';

final class EntryShareCopyProjectionService {
  const EntryShareCopyProjectionService();

  List<String> missingFields(EntryShareSnapshot snapshot) {
    final present = snapshot.fields.map((field) => field.id).toSet();
    return List.unmodifiable([
      for (final id in _required(snapshot.entryType))
        if (!present.contains(id)) id,
    ]);
  }

  MemberSecret project({
    required EntryShareSnapshot snapshot,
    String? title,
    Map<String, String> completedFields = const {},
  }) {
    final label = title ?? snapshot.title;
    if (label.trim().isEmpty || label.length > 200) {
      throw const EntryShareCopyInputException(
        EntryShareCopyInputError.invalidTitle,
      );
    }
    final missing = missingFields(snapshot).toSet();
    if (completedFields.keys.any((id) => !missing.contains(id))) {
      throw const EntryShareCopyInputException(
        EntryShareCopyInputError.unexpectedCompletion,
      );
    }
    if (!completedFields.keys.toSet().containsAll(missing)) {
      throw const EntryShareCopyInputException(
        EntryShareCopyInputError.missingFields,
      );
    }
    final values = {
      for (final field in snapshot.fields) field.id: field.value,
      ...completedFields,
    };
    final custom = List<VaultCustomField>.unmodifiable([
      for (final field in snapshot.fields)
        if (field.id.startsWith('custom:'))
          VaultCustomField(
            id: CustomField.newId(),
            label: field.label,
            kind: field.type,
            value: field.type == 'totp'
                ? const EntryShareTotpCodec().decode(field.value)
                : field.value,
          ),
    ]);
    final content = switch (snapshot.entryType) {
      'key' => KeySecretContent(
        value: values['key.value']!,
        url: values['key.url'],
        notes: values['notes'],
        customFields: custom,
      ),
      'credential' => CredentialSecretContent(
        username: values['credential.username']!,
        password: values['credential.password']!,
        url: values['credential.url'],
        urlDomain: _domain(values['credential.url']),
        totp: values['credential.totp'] == null
            ? null
            : const EntryShareTotpCodec().decode(values['credential.totp']!),
        notes: values['notes'],
        customFields: custom,
      ),
      'script' => _script(values, custom),
      'creditCard' => CreditCardSecretContent(
        cardholderName: values['creditCard.cardholderName']!,
        cardNumber: values['creditCard.cardNumber']!,
        expiryMonth: values['creditCard.expiryMonth']!,
        expiryYear: values['creditCard.expiryYear']!,
        billingAddress: values['creditCard.billingAddress'],
        notes: values['notes'],
        customFields: custom,
      ),
      _ => throw const EntryShareException(EntryShareErrorKind.invalidSnapshot),
    };
    final secret = MemberSecret(
      entryType: VaultEntryType.parse(snapshot.entryType),
      memberLabel: label,
      agentLabel: null,
      description: values['description'],
      icon: null,
      color: null,
      discoverable: false,
      content: content,
      agentFieldAccess: {
        for (final id in {
          'memberLabel',
          'agentLabel',
          'description',
          'icon',
          'color',
          'entryType',
          ...content.fieldValues().keys,
          ...custom.map((field) => field.fieldId),
        })
          id: AgentFieldAccess.never,
      },
    );
    try {
      // Independent shared plaintext must remain readable by the canonical index.
      MemberIndex.fromJson(
        VaultPlaintextProjector.memberIndex(secret).toJson(),
      );
    } on VaultPlaintextFormatException {
      throw const EntryShareCopyInputException(
        EntryShareCopyInputError.unsupportedContent,
      );
    }
    return secret;
  }

  ScriptSecretContent _script(
    Map<String, String> values,
    List<VaultCustomField> custom,
  ) {
    final source = values['script.source']!;
    final interpreter = values['script.interpreter']!;
    final description = values['script.execution.description']!;
    if (source.trim().isEmpty ||
        !{'bash', 'sh', 'node', 'python'}.contains(interpreter) ||
        description.trim().isEmpty ||
        description.length > 4096) {
      throw const EntryShareCopyInputException(
        EntryShareCopyInputError.invalidScript,
      );
    }
    return ScriptSecretContent(
      source: source,
      interpreter: interpreter,
      refs: const [],
      execution: Map.unmodifiable({
        'contractVersion': 1,
        'description': description,
        'parameters': const [],
        'returnResultToAgent': false,
      }),
      notes: values['notes'],
      customFields: custom,
    );
  }

  String? _domain(String? raw) {
    if (raw == null) return null;
    final url = Uri.tryParse(raw);
    if (url == null ||
        !{'https', 'http'}.contains(url.scheme) ||
        url.host.isEmpty) {
      return null;
    }
    return url.host.toLowerCase();
  }

  List<String> _required(String type) => switch (type) {
    'key' => const ['key.value'],
    'credential' => const ['credential.username', 'credential.password'],
    'script' => const [
      'script.source',
      'script.interpreter',
      'script.execution.description',
    ],
    'creditCard' => const [
      'creditCard.cardholderName',
      'creditCard.cardNumber',
      'creditCard.expiryMonth',
      'creditCard.expiryYear',
    ],
    _ => throw const EntryShareException(EntryShareErrorKind.invalidSnapshot),
  };
}
