import '../../../domain/entities/entry_share.dart';
import '../../../domain/entities/entry_share_selection.dart';
import '../canonical_entry_detail_service.dart';

final class EntryShareSelectionService {
  const EntryShareSelectionService();

  EntryShareSelection project(CanonicalEntrySnapshot source) {
    const invalid = EntryShareException(EntryShareErrorKind.invalidSnapshot);
    final type = switch (source.secret['entryType']) {
      0 => 'key',
      1 => 'credential',
      2 => 'script',
      3 => 'creditCard',
      _ => throw invalid,
    };
    final title = source.secret['memberLabel'];
    if (title is! String || title.isEmpty || title.length > 512) throw invalid;
    final choices = <EntryShareFieldChoice>[];
    final unsupported = <UnsupportedEntryShareField>[];
    final ids = <String>{};

    void add(
      String id,
      String label,
      String kind,
      Object? raw, {
      bool selectedByDefault = false,
    }) {
      if (!ids.add(id)) throw invalid;
      final value = kind == 'totp' ? _totpUri(raw) : raw;
      if (value is! String ||
          id.isEmpty ||
          id.length > 160 ||
          label.length > 256 ||
          value.length > 262144 ||
          !{'text', 'multiline', 'concealed', 'totp'}.contains(kind)) {
        unsupported.add(UnsupportedEntryShareField(id: id, label: label));
        return;
      }
      choices.add(
        EntryShareFieldChoice(
          id: id,
          label: label,
          type: kind,
          value: value,
          selectedByDefault: selectedByDefault,
        ),
      );
    }

    void native(String name, String kind, {bool selected = true}) {
      final value = source.payload[name];
      if (value != null) {
        add('$type.$name', '', kind, value, selectedByDefault: selected);
      }
    }

    switch (type) {
      case 'key':
        native('value', 'concealed');
        native('url', 'text');
      case 'credential':
        native('username', 'text');
        native('password', 'concealed');
        native('url', 'text');
        native('totp', 'totp', selected: false);
      case 'script':
        native('source', 'multiline');
        native('interpreter', 'text');
      case 'creditCard':
        native('cardholderName', 'text');
        native('cardNumber', 'concealed');
        native('expiryMonth', 'text');
        native('expiryYear', 'text');
        native('billingAddress', 'multiline', selected: false);
    }
    if (source.secret['description'] != null) {
      add('description', '', 'multiline', source.secret['description']);
    }
    if (source.payload['notes'] != null) {
      add('notes', '', 'multiline', source.payload['notes']);
    }
    final custom = source.payload['fields'];
    if (custom != null && custom is! List) throw invalid;
    for (final raw in (custom as List? ?? const [])) {
      if (raw is! Map ||
          raw['id'] is! String ||
          (raw['id'] as String).isEmpty ||
          raw['label'] is! String ||
          raw['type'] is! String) {
        throw invalid;
      }
      // The canonical-to-form adapter retains the raw custom-field identity.
      add('custom:${raw['id']}', raw['label'], raw['type'], raw['value']);
    }
    return EntryShareSelection(
      title: title,
      entryType: type,
      choices: choices,
      unsupported: unsupported,
    );
  }

  String? _totpUri(Object? raw) {
    if (raw is! Map ||
        raw.keys.any(
          (key) => !{
            'secret',
            'algorithm',
            'digits',
            'period',
            'issuer',
            'account',
          }.contains(key),
        ) ||
        raw['secret'] is! String ||
        !RegExp(r'^[A-Z2-7]+$').hasMatch(raw['secret'] as String) ||
        !{'SHA1', 'SHA256', 'SHA512'}.contains(raw['algorithm']) ||
        raw['digits'] is! int ||
        !{6, 8}.contains(raw['digits']) ||
        raw['period'] is! int ||
        (raw['period'] as int) < 15 ||
        (raw['period'] as int) > 120 ||
        (raw['issuer'] != null && raw['issuer'] is! String) ||
        (raw['account'] != null && raw['account'] is! String)) {
      return null;
    }
    final issuer = raw['issuer'] as String? ?? '';
    final account = raw['account'] as String? ?? '';
    final label = issuer.isEmpty ? account : '$issuer:$account';
    return Uri(
      scheme: 'otpauth',
      host: 'totp',
      pathSegments: [label],
      queryParameters: {
        'secret': raw['secret'] as String,
        'algorithm': raw['algorithm'] as String,
        'digits': '${raw['digits']}',
        'period': '${raw['period']}',
        // Explicit empty issuer keeps colons in issuer-less account labels.
        'issuer': issuer,
      },
    ).toString();
  }
}
