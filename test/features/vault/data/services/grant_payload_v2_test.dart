import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/vault/data/services/agent_visibility_projector.dart';
import 'package:mobile_palladin/features/vault/data/services/grant_totp_source.dart';
import 'package:mobile_palladin/features/vault/data/services/totp_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_signature_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/agent_visibility_policy.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';
import 'package:mobile_palladin/features/vault/domain/entities/totp_config.dart';

void main() {
  test(
    'Member labels omitted; URI defaults explicit without algorithm fallback',
    () {
      const secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
      final source = GrantTotpSource.fromMemberValue(
        'otpauth://totp/Example:user?secret=$secret&issuer=Example',
      );
      expect(source, {
        'source': 'totp',
        'secret': secret,
        'algorithm': 'SHA1',
        'digits': 6,
        'period': 30,
      });
      for (final invalid in [
        'otpauth://totp/user?secret=$secret&algorithm=MD5',
        'otpauth://totp/user?secret=$secret&digits=0',
        'otpauth://totp/user?secret=$secret&period=abc',
        'otpauth://totp/user?secret=$secret&secret=$secret',
        {'secret': secret, 'algorithm': 'unknown'},
        {'secret': secret, 'period': 0},
        {'secret': secret, 'digits': 6.5},
      ]) {
        expect(
          () => GrantTotpSource.fromMemberValue(invalid),
          throwsFormatException,
        );
      }
    },
  );
  test('V2 cannot widen a private native or custom TOTP', () {
    const customId = '11111111-2222-4333-8444-555555555555';
    final content = <String, dynamic>{
      'totp': {'secret': 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ'},
      'fields': [
        {
          'id': customId,
          'type': 'totp',
          'value': {'secret': 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ'},
        },
      ],
    };
    for (final id in ['totp', customId]) {
      expect(
        () => AgentVisibilityProjector.grantPayloadV2(
          type: EntryType.credential,
          vaultId: '11112222-3333-4444-8555-666677778888',
          agentLabel: '',
          description: '',
          content: content,
          policy: AgentVisibilityPolicy(
            discoverable: false,
            fields: {id: AgentFieldAccess.never},
          ),
          approvedFieldIds: [id],
        ),
        throwsFormatException,
      );
    }
  });
  final fixtures =
      jsonDecode(
            File(
              'test/fixtures/grant-payload/v2/vectors.json',
            ).readAsStringSync(),
          )
          as Map;
  for (final vector in fixtures['vectors'] as List) {
    test(
      'V2 producer matches published bytes and later codes: ${vector['id']}',
      () {
        final expected = vector['plaintext'] as Map;
        final expectedFields = expected['fields'] as List;
        final source = Map<String, dynamic>.from(
          expectedFields.first['value'] as Map,
        )..remove('source');
        final customId = (expectedFields.last['id'] as String).substring(7);
        final content = <String, dynamic>{
          'totp': source,
          'fields': [
            {'id': customId, 'type': 'totp', 'value': source},
          ],
        };
        final policy = AgentVisibilityPolicy(
          discoverable: true,
          fields: {
            'totp': AgentFieldAccess.onGrantDerived,
            customId: AgentFieldAccess.onGrantDerived,
          },
        );
        final payload = AgentVisibilityProjector.grantPayloadV2(
          type: EntryType.credential,
          vaultId: '11112222-3333-4444-8555-666677778888',
          agentLabel: 'Synthetic',
          description: '',
          content: content,
          policy: policy,
          approvedFieldIds: [customId, 'totp'],
        );
        expect(canonicalizeVaultJson(payload), vector['plaintextCanonical']);
        expect(
          AgentVisibilityProjector.grantPayloadFieldIds(payload),
          expectedFields.map((dynamic f) => f['id']).toList(),
        );
        final value = (payload['fields'] as List).first['value'] as Map;
        GrantTotpSource.validate(value);
        for (final derivation in vector['derivations'] as List) {
          final code = const TotpService().generate(
            TotpConfig.fromJson(Map<String, dynamic>.from(value)),
            at: DateTime.fromMillisecondsSinceEpoch(
              (derivation['unixSeconds'] as int) * 1000,
              isUtc: true,
            ),
          );
          expect(code.code, derivation['code']);
          expect(code.secondsRemaining, derivation['expiresIn']);
        }
      },
    );
  }
  for (final vector in fixtures['invalidSources'] as List) {
    test('reject published invalid source: ${vector['id']}', () {
      final fields = (vector['plaintext'] as Map)['fields'] as List;
      expect(
        () => GrantTotpSource.validate(fields.first['value']),
        throwsFormatException,
      );
    });
  }
}
