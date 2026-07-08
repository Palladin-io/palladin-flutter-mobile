import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/vault/domain/entities/custom_field.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';
import 'package:mobile_palladin/features/vault/data/models/create_entry_request.dart';
import 'package:mobile_palladin/features/vault/data/models/entry_model.dart';
import 'package:mobile_palladin/features/vault/data/models/update_entry_request.dart';
import 'package:mobile_palladin/features/vault/domain/entities/totp_config.dart';
import 'package:mobile_palladin/features/vault/presentation/widgets/entry_form_utils.dart';

void main() {
  group('EntryType.script wire format', () {
    test('script maps to ordinal 2 both ways', () {
      expect(EntryType.script.toWire(), 2);
      expect(EntryTypeExtension.fromWire(2), EntryType.script);
    });

    test('unknown ordinals still default to credential', () {
      expect(EntryTypeExtension.fromWire(99), EntryType.credential);
    });

    test('EntryModel parses the string type "script"', () {
      Map<String, dynamic> base(Object type) => {
            'id': 'e1',
            'vaultId': 'v1',
            'label': 'Deploy',
            'type': type,
            'createdAt': '2026-01-01T00:00:00Z',
            'updatedAt': '2026-01-01T00:00:00Z',
          };
      expect(
        EntryModel.fromJson(base('script')).toEntity().type,
        EntryType.script,
      );
      expect(
        EntryModel.fromJson(base('Script')).toEntity().type,
        EntryType.script,
      );
      // Unknown string types fall back to credential instead of throwing.
      expect(
        EntryModel.fromJson(base('mystery')).toEntity().type,
        EntryType.credential,
      );
    });
  });

  group('CustomField parsing (blob schema v2)', () {
    test('parses text / concealed / totp and preserves unknown', () {
      final payload = {
        'fields': [
          {'id': 'a', 'label': 'Recovery email', 'type': 'text', 'value': 'x@y'},
          {'id': 'b', 'label': 'PIN', 'type': 'concealed', 'value': '1234'},
          {
            'id': 'c',
            'label': '2FA',
            'type': 'totp',
            'value': {'secret': 'JBSWY3DPEHPK3PXP', 'digits': 6, 'period': 30},
          },
          {'id': 'd', 'label': 'When', 'type': 'date', 'value': '2026-01-01'},
        ],
      };
      final fields = CustomField.listFromPayload(payload);
      expect(fields.length, 4);
      expect(fields[0].type, CustomFieldType.text);
      expect(fields[0].textValue, 'x@y');
      expect(fields[1].type, CustomFieldType.concealed);
      expect(fields[2].type, CustomFieldType.totp);
      expect(fields[2].totp?.secret, 'JBSWY3DPEHPK3PXP');
      // Unknown type preserved for round-trip, not dropped.
      expect(fields[3].type, CustomFieldType.unknown);
      expect(fields[3].rawType, 'date');
      expect(fields[3].toJson()['type'], 'date');
      expect(fields[3].toJson()['value'], '2026-01-01');
    });

    test('missing / malformed fields array yields empty list', () {
      expect(CustomField.listFromPayload({}), isEmpty);
      expect(CustomField.listFromPayload({'fields': 'nope'}), isEmpty);
    });

    test('multiline round-trips and agentVisible only for text/multiline',
        () {
      final fields = [
        CustomField.text(
            id: '1', label: 'Account', value: 'acme', agentVisible: true),
        CustomField.multiline(
            id: '2', label: 'Config', value: 'a\nb', agentVisible: true),
        CustomField.concealed(id: '3', label: 'PIN', value: '1234'),
      ];
      final json = CustomField.listToJson(fields);
      expect(json[0]['type'], 'text');
      expect(json[0]['agentVisible'], true);
      expect(json[1]['type'], 'multiline');
      expect(json[1]['agentVisible'], true);
      // concealed can never be agent-visible — the key is absent.
      expect(json[2].containsKey('agentVisible'), isFalse);

      final parsed = CustomField.listFromPayload({'fields': json});
      expect(parsed[1].type, CustomFieldType.multiline);
      expect(parsed[1].textValue, 'a\nb');
      expect(parsed[1].agentVisible, isTrue);
    });

    test('agentFieldsFrom mirrors only agent-visible text/multiline fields',
        () {
      final agentFields = CustomField.agentFieldsFrom([
        CustomField.text(
            id: '1', label: 'Account', value: 'acme', agentVisible: true),
        CustomField.text(id: '2', label: 'Hidden helper', value: 'x'),
        CustomField.multiline(
            id: '3', label: 'Region', value: 'eu', agentVisible: true),
        CustomField.concealed(id: '4', label: 'PIN', value: '1'),
      ]);
      expect(agentFields.map((f) => f.label), ['Account', 'Region']);
      expect(agentFields.map((f) => f.value), ['acme', 'eu']);
    });

    test('a concealed field flagged agent-visible never leaks the flag', () {
      // Even if constructed with agentVisible via copyWith, concealed drops it.
      final field = CustomField.concealed(id: '1', label: 'PIN', value: '1')
          .copyWith(agentVisible: true);
      expect(field.toJson().containsKey('agentVisible'), isFalse);
      expect(CustomField.agentFieldsFrom([field]), isEmpty);
    });
  });

  group('agentFields on request DTOs (CVT-204)', () {
    const content = EntryContentModel(encryptedBlob: 'blob', nonce: 'n');

    test('create request serializes agentFields', () {
      final json = CreateEntryRequest(
        label: 'GitHub',
        type: 1,
        content: content,
        agentFields: const [AgentField(label: 'Account', value: 'acme')],
      ).toJson();
      expect(json['agentFields'], [
        {'label': 'Account', 'value': 'acme'},
      ]);
    });

    test('update request omits agentFields when null (patch unchanged)', () {
      final json = UpdateEntryRequest(
        label: 'GitHub',
        type: 1,
        content: content,
      ).toJson();
      expect(json.containsKey('agentFields'), isFalse);
    });

    test('update request sends an empty list to clear agent fields', () {
      final json = UpdateEntryRequest(
        label: 'GitHub',
        type: 1,
        content: content,
        agentFields: const [],
      ).toJson();
      expect(json['agentFields'], isEmpty);
    });
  });

  group('KeyPayload v2', () {
    test('round-trips value + custom fields with v:2', () {
      final payload = KeyPayload(
        value: 'sk_live_x',
        notes: 'rotate me',
        fields: [
          CustomField.text(id: '1', label: 'Env', value: 'prod'),
        ],
      );
      final json = payload.toJson();
      expect(json['v'], 2);
      expect(json['type'], 'KEY');
      expect((json['fields'] as List).length, 1);

      final parsed = KeyPayload.fromJson(json);
      expect(parsed.value, 'sk_live_x');
      expect(parsed.fields.single.label, 'Env');
      expect(parsed.fields.single.textValue, 'prod');
    });

    test('omits the fields key entirely when there are none', () {
      const payload = KeyPayload(value: 'x');
      expect(payload.toJson().containsKey('fields'), isFalse);
    });
  });

  group('CredentialPayload v2', () {
    test('preserves a legacy flat totp string on round-trip', () {
      const payload = CredentialPayload(
        username: 'u',
        password: 'p',
        totp: 'otpauth://totp/A?secret=JBSWY3DPEHPK3PXP',
      );
      final parsed = CredentialPayload.fromJson(payload.toJson());
      expect(parsed.totp, 'otpauth://totp/A?secret=JBSWY3DPEHPK3PXP');
    });
  });

  group('ScriptPayload v2', () {
    test('round-trips script, interpreter, refs and fields', () {
      final payload = ScriptPayload(
        script: '#!/usr/bin/env bash\necho hi',
        interpreter: ScriptInterpreter.node,
        notes: 'deploy',
        refs: const [
          ScriptRef(
            env: 'GITHUB_TOKEN',
            vaultId: 'v1',
            entryId: 'e1',
            field: 'value',
          ),
        ],
        fields: [CustomField.concealed(id: '1', label: 'PIN', value: '9')],
      );
      final json = payload.toJson();
      expect(json['v'], 2);
      expect(json['type'], 'SCRIPT');
      expect(json['interpreter'], 'node');
      // refs wire shape: {env, vaultId, entryId, field}.
      final refJson = (json['refs'] as List).first as Map<String, dynamic>;
      expect(refJson['env'], 'GITHUB_TOKEN');
      expect(refJson['vaultId'], 'v1');

      final parsed = ScriptPayload.fromJson(json);
      expect(parsed.interpreter, ScriptInterpreter.node);
      expect(parsed.refs.single.env, 'GITHUB_TOKEN');
      expect(parsed.refs.single.vaultId, 'v1');
      expect(parsed.refs.single.entryId, 'e1');
      expect(parsed.refs.single.field, 'value');
      expect(parsed.fields.single.type, CustomFieldType.concealed);
    });

    test('reads the legacy placeholder key and optional vaultId', () {
      final parsed = ScriptPayload.fromJson({
        'script': 'echo',
        'refs': [
          {'placeholder': 'TOKEN', 'entryId': 'e1', 'field': 'value'},
        ],
      });
      expect(parsed.refs.single.env, 'TOKEN');
      expect(parsed.refs.single.vaultId, isNull);
    });

    test('interpreter falls back to bash for unknown tokens', () {
      expect(ScriptInterpreter.fromName('zsh'), ScriptInterpreter.bash);
      expect(ScriptInterpreter.fromName(null), ScriptInterpreter.bash);
    });
  });

  group('EntryFormUtils.buildPayload — script', () {
    test('builds a SCRIPT payload with trimmed body and refs', () {
      final json = EntryFormUtils.buildPayload(
        type: EntryType.script,
        script: '  echo hi  ',
        interpreter: ScriptInterpreter.python,
        notes: 'x',
        refs: const [
          ScriptRef(env: 'TOKEN', entryId: 'e1', field: 'value'),
        ],
      );
      expect(json['type'], 'SCRIPT');
      expect(json['script'], 'echo hi');
      expect(json['interpreter'], 'python');
      expect((json['refs'] as List).length, 1);
    });

    test('canSubmit requires a non-empty script body', () {
      expect(
        EntryFormUtils.canSubmit(
          type: EntryType.script,
          label: 'Deploy',
          script: 'echo',
        ),
        isTrue,
      );
      expect(
        EntryFormUtils.canSubmit(
          type: EntryType.script,
          label: 'Deploy',
          script: '   ',
        ),
        isFalse,
      );
    });

    test('custom fields fold into a KEY payload', () {
      final json = EntryFormUtils.buildPayload(
        type: EntryType.key,
        value: 'x',
        fields: [
          CustomField.totpField(
            id: '1',
            label: '2FA',
            config: const TotpConfig(secret: 'JBSWY3DPEHPK3PXP'),
          ),
        ],
      );
      final fields = (json['fields'] as List).cast<Map<String, dynamic>>();
      expect(fields.single['type'], 'totp');
      expect((fields.single['value'] as Map)['secret'], 'JBSWY3DPEHPK3PXP');
    });
  });
}
