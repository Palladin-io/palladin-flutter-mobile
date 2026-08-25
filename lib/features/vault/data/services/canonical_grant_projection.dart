import 'dart:convert';
import 'dart:typed_data';

/// Projects only requested Agent-grant fields from authenticated canonical
/// MemberSecret bytes. Unrequested values are skipped as bytes and are never
/// decoded into Dart Strings or a complete object graph.
Uint8List projectCanonicalGrantPayload(
  Uint8List memberSecretBytes,
  Set<String> fieldIds,
) => _CanonicalGrantProjectionParser(memberSecretBytes, fieldIds).project();

final class _CanonicalGrantProjectionParser {
  _CanonicalGrantProjectionParser(this._bytes, Set<String> fieldIds)
    : _fieldIds = Set.unmodifiable(fieldIds);

  final Uint8List _bytes;
  final Set<String> _fieldIds;
  final Map<String, Uint8List> _values = {};
  final Map<String, String> _access = {};
  final Map<String, String> _customKinds = {};
  int _offset = 0;
  String? _schema;
  String? _entryType;

  Uint8List project() {
    if (_fieldIds.isEmpty || _fieldIds.length > 64) {
      throw const FormatException('Invalid grant projection field set');
    }
    try {
      _readRoot();
      _skipWhitespace();
      if (_offset != _bytes.length ||
          _schema != 'palladin.member-secret.v1' ||
          _entryType == null ||
          !_values.keys.toSet().containsAll(_fieldIds) ||
          !_access.keys.toSet().containsAll(_fieldIds)) {
        throw const FormatException('Incomplete canonical grant projection');
      }
      final sorted = _fieldIds.toList()..sort();
      final output = BytesBuilder(copy: false);
      output.add(ascii.encode('{"entryType":'));
      output.add(utf8.encode(jsonEncode(_entryType)));
      output.add(ascii.encode(',"fields":['));
      for (var index = 0; index < sorted.length; index++) {
        final id = sorted[index];
        final mode = switch (_access[id]) {
          'onGrantValue' => 'value',
          'onGrantDerived' => 'derived',
          'onGrantRuntime' => 'runtime',
          _ => throw FormatException('$id is not grant-authorized'),
        };
        final kind = _kind(id);
        if (index > 0) output.addByte(0x2c);
        output.add(ascii.encode('{"id":'));
        output.add(utf8.encode(jsonEncode(id)));
        output.add(ascii.encode(',"kind":'));
        output.add(utf8.encode(jsonEncode(kind)));
        output.add(ascii.encode(',"mode":'));
        output.add(utf8.encode(jsonEncode(mode)));
        output.add(ascii.encode(',"value":'));
        output.add(_values[id]!);
        output.addByte(0x7d);
      }
      output.add(ascii.encode('],"schema":"palladin.grant-payload.v1"}'));
      return output.takeBytes();
    } finally {
      for (final value in _values.values) {
        value.fillRange(0, value.length, 0);
      }
      _values.clear();
      _access.clear();
      _customKinds.clear();
    }
  }

  void _readRoot() {
    _readObject((key) {
      switch (key) {
        case 'schema':
          _schema = _readString();
        case 'entryType':
          final raw = _readRawValue();
          try {
            final value = jsonDecode(utf8.decode(raw));
            _entryType = switch (value) {
              'key' || 0 => 'key',
              'credential' || 1 => 'credential',
              'script' || 2 => 'script',
              'creditCard' || 3 => 'creditCard',
              _ => throw const FormatException('Unknown Entry type'),
            };
          } finally {
            raw.fillRange(0, raw.length, 0);
          }
        case 'content':
          _readContent();
        case 'agentFieldAccess':
          _readAccessMap();
        default:
          _skipValue();
      }
    });
  }

  void _readContent() {
    _readObject((key) {
      if (key == 'customFields') {
        _readCustomFields();
        return;
      }
      final id = switch (key) {
        'value' => 'key.value',
        'username' => 'credential.username',
        'password' => 'credential.password',
        'url' => 'credential.url',
        'urlDomain' => 'credential.urlDomain',
        'totp' => 'credential.totp',
        'source' || 'script' => 'script.source',
        'interpreter' => 'script.interpreter',
        'refs' => 'script.refs',
        'cardholderName' => 'creditCard.cardholderName',
        'cardNumber' => 'creditCard.cardNumber',
        'expiryMonth' => 'creditCard.expiryMonth',
        'expiryYear' => 'creditCard.expiryYear',
        'billingAddress' => 'creditCard.billingAddress',
        'notes' => 'notes',
        _ => null,
      };
      if (id != null && _fieldIds.contains(id)) {
        _values[id] = _readRawValue();
      } else {
        _skipValue();
      }
    });
  }

  void _readCustomFields() {
    _expect(0x5b);
    _skipWhitespace();
    if (_consume(0x5d)) return;
    while (true) {
      String? id;
      String? kind;
      Uint8List? value;
      _readObject((key) {
        switch (key) {
          case 'id':
            id = _readString();
          case 'kind':
            kind = _readString();
          case 'value':
            value = _readRawValue();
          default:
            _skipValue();
        }
      });
      final fieldId = id == null ? null : 'custom:$id';
      if (fieldId != null && _fieldIds.contains(fieldId)) {
        if (kind == null || value == null) {
          value?.fillRange(0, value!.length, 0);
          throw const FormatException('Malformed custom grant field');
        }
        _customKinds[fieldId] = kind!;
        _values[fieldId] = value!;
      } else {
        value?.fillRange(0, value!.length, 0);
      }
      _skipWhitespace();
      if (_consume(0x5d)) return;
      _expect(0x2c);
    }
  }

  void _readAccessMap() {
    _readObject((key) {
      if (_fieldIds.contains(key)) {
        _access[key] = _readString();
      } else {
        _skipValue();
      }
    });
  }

  String _kind(String id) => switch (id) {
    'key.value' ||
    'credential.password' ||
    'creditCard.cardNumber' => 'concealed',
    'credential.username' ||
    'credential.urlDomain' ||
    'creditCard.cardholderName' ||
    'creditCard.expiryMonth' ||
    'creditCard.expiryYear' ||
    'creditCard.billingAddress' => 'text',
    'credential.url' => 'url',
    'credential.totp' => 'totp',
    'notes' => 'multiline',
    'script.source' => 'script',
    'script.interpreter' => 'interpreter',
    'script.refs' => 'refs',
    _ when id.startsWith('custom:') =>
      _customKinds[id] ??
          (throw FormatException('Unknown custom grant field $id')),
    _ => throw FormatException('Unknown grant field $id'),
  };

  void _readObject(void Function(String key) readValue) {
    _expect(0x7b);
    _skipWhitespace();
    if (_consume(0x7d)) return;
    while (true) {
      final key = _readString();
      _skipWhitespace();
      _expect(0x3a);
      _skipWhitespace();
      readValue(key);
      _skipWhitespace();
      if (_consume(0x7d)) return;
      _expect(0x2c);
      _skipWhitespace();
    }
  }

  Uint8List _readRawValue() {
    _skipWhitespace();
    final start = _offset;
    _skipValue();
    return Uint8List.fromList(_bytes.sublist(start, _offset));
  }

  void _skipValue() {
    _skipWhitespace();
    if (_offset >= _bytes.length) {
      throw const FormatException('Unexpected end of JSON');
    }
    switch (_bytes[_offset]) {
      case 0x22:
        _skipString();
      case 0x7b:
        _expect(0x7b);
        _skipWhitespace();
        if (_consume(0x7d)) return;
        while (true) {
          _skipString();
          _skipWhitespace();
          _expect(0x3a);
          _skipValue();
          _skipWhitespace();
          if (_consume(0x7d)) return;
          _expect(0x2c);
          _skipWhitespace();
        }
      case 0x5b:
        _expect(0x5b);
        _skipWhitespace();
        if (_consume(0x5d)) return;
        while (true) {
          _skipValue();
          _skipWhitespace();
          if (_consume(0x5d)) return;
          _expect(0x2c);
          _skipWhitespace();
        }
      default:
        final start = _offset;
        while (_offset < _bytes.length && !_isDelimiter(_bytes[_offset])) {
          _offset++;
        }
        if (_offset == start) {
          throw const FormatException('Malformed JSON value');
        }
    }
  }

  String _readString() {
    _skipWhitespace();
    final start = _offset;
    _skipString();
    final value = jsonDecode(utf8.decode(_bytes.sublist(start, _offset)));
    if (value is! String) throw const FormatException('Expected JSON string');
    return value;
  }

  void _skipString() {
    _expect(0x22);
    var escaped = false;
    while (_offset < _bytes.length) {
      final byte = _bytes[_offset++];
      if (escaped) {
        escaped = false;
      } else if (byte == 0x5c) {
        escaped = true;
      } else if (byte == 0x22) {
        return;
      }
    }
    throw const FormatException('Unterminated JSON string');
  }

  void _skipWhitespace() {
    while (_offset < _bytes.length &&
        const {0x20, 0x09, 0x0a, 0x0d}.contains(_bytes[_offset])) {
      _offset++;
    }
  }

  void _expect(int byte) {
    if (_offset >= _bytes.length || _bytes[_offset] != byte) {
      throw const FormatException('Malformed canonical JSON');
    }
    _offset++;
  }

  bool _consume(int byte) {
    if (_offset < _bytes.length && _bytes[_offset] == byte) {
      _offset++;
      return true;
    }
    return false;
  }

  bool _isDelimiter(int byte) =>
      byte == 0x2c ||
      byte == 0x5d ||
      byte == 0x7d ||
      byte == 0x20 ||
      byte == 0x09 ||
      byte == 0x0a ||
      byte == 0x0d;
}
