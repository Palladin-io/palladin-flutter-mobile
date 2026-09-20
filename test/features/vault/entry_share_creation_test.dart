import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/vault/data/datasources/entry_sharing_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/services/canonical_entry_detail_service.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_sharing/entry_share_selection_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_share.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_share_creation.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_share_list.dart';

Map<String, Object?> _totp() => {
  'secret': 'JBSWY3DPEHPK3PXP',
  'algorithm': 'SHA256',
  'digits': 8,
  'period': 45,
  'issuer': '  Issuer/&? 🦉',
  'account': 'a+b@example.test',
};

CanonicalEntrySnapshot _source({int type = 1, Map<String, dynamic>? payload}) =>
    CanonicalEntrySnapshot(
      entry: {'currentRevision': '9007199254740993', 'entryKey': 'source-key'},
      secret: {
        'entryType': type,
        'memberLabel': '  Shared title 🔐  ',
        'description': 'private description',
        'agentVisibilityPolicy': {'fields': 'must-not-be-shared'},
        'agentLabel': 'agent-label-must-not-be-shared',
      },
      payload:
          payload ??
          {
            'username': 'user',
            'password': '  secret\u0000e\u0301  ',
            'url': 'https://example.test',
            'totp': _totp(),
            'notes': 'private notes',
            'fields': [
              {
                'id': 'recovery',
                'label': 'Recovery',
                'type': 'concealed',
                'value': 'recovery-codes',
              },
              {
                'id': 'text',
                'label': 'Public',
                'type': 'text',
                'value': 'custom-text',
                'agentVisible': true,
              },
            ],
            'history': ['history-must-not-be-shared'],
            'refs': ['refs-must-not-be-shared'],
          },
    );

class _Adapter implements HttpClientAdapter {
  String body = '{}';
  int status = 200;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  const projector = EntryShareSelectionService();
  final invalidSnapshot = throwsA(
    isA<EntryShareException>().having(
      (error) => error.kind,
      'kind',
      EntryShareErrorKind.invalidSnapshot,
    ),
  );

  group('explicit selected-field projection', () {
    test('sensitive extras are opt-in regardless of Agent visibility', () {
      final selection = projector.project(_source());
      expect(
        selection.choices
            .where((field) => field.selectedByDefault)
            .map((field) => field.id),
        ['credential.username', 'credential.password', 'credential.url'],
      );
      expect(
        selection.choices
            .where((field) => !field.selectedByDefault)
            .map((field) => field.id),
        [
          'credential.totp',
          'description',
          'notes',
          'custom:recovery',
          'custom:text',
        ],
      );
      expect(selection.unsupported, isEmpty);
    });

    test('copies only selected content and preserves exact strings', () {
      final source = _source();
      final selection = projector.project(source);
      source.clear();
      final snapshot = selection.select(['credential.password']);
      expect(snapshot.toJson(), {
        'schema': EntryShareSnapshot.schema,
        'title': '  Shared title 🔐  ',
        'entryType': 'credential',
        'fields': [
          {
            'id': 'credential.password',
            'label': '',
            'type': 'concealed',
            'value': '  secret\u0000e\u0301  ',
          },
        ],
      });
    });

    test('TOTP shares the configuration URI, never a current code', () {
      final selection = projector.project(_source());
      final field = selection.select(['credential.totp']).fields.single;
      final uri = Uri.parse(field.value);
      expect(field.type, 'totp');
      expect(uri.scheme, 'otpauth');
      expect(uri.host, 'totp');
      expect(uri.pathSegments, ['  Issuer/&? 🦉:a+b@example.test']);
      expect(uri.queryParameters, {
        'secret': 'JBSWY3DPEHPK3PXP',
        'algorithm': 'SHA256',
        'digits': '8',
        'period': '45',
        'issuer': '  Issuer/&? 🦉',
      });
    });

    for (final bad in <Object?>[
      'otpauth://totp/legacy?secret=JBSWY3DPEHPK3PXP',
      {..._totp(), 'algorithm': 'md5'},
      {..._totp(), 'secret': 'jbswy3dp'},
      {..._totp(), 'secret': 'JBSW Y3DP'},
      {..._totp(), 'secret': 'JBSWY3DP='},
      {..._totp(), 'period': 14},
      {..._totp(), 'period': 121},
      {..._totp(), 'period': '30'},
      {..._totp(), 'digits': 7},
      {..._totp(), 'digits': 8.0},
      {..._totp(), 'issuer': 3},
      {..._totp(), 'unknown': true},
    ]) {
      test(
        'unsupported TOTP is visible as unavailable, not normalized (${bad is Map ? bad.keys.join(',') : 'legacy'})',
        () {
          final selection = projector.project(
            _source(payload: {'username': 'user', 'totp': bad}),
          );
          expect(selection.unsupported.map((field) => field.id), [
            'credential.totp',
          ]);
          expect(() => selection.select(['credential.totp']), invalidSnapshot);
          expect(
            selection.select(['credential.username']).fields.single.value,
            'user',
          );
        },
      );
    }

    test(
      'custom future types and invalid values cannot silently disappear or be selected',
      () {
        final selection = projector.project(
          _source(
            payload: {
              'username': 'user',
              'fields': [
                {
                  'id': 'future',
                  'label': 'Future',
                  'type': 'url',
                  'value': 'https://example.test',
                },
                {
                  'id': 'bad-value',
                  'label': 'Invalid',
                  'type': 'text',
                  'value': 7,
                },
                {
                  'id': 'totp',
                  'label': '2FA',
                  'type': 'totp',
                  'value': _totp(),
                },
              ],
            },
          ),
        );
        expect(selection.unsupported.map((field) => field.id), [
          'custom:future',
          'custom:bad-value',
        ]);
        expect(selection.unsupported.map((field) => field.label), [
          'Future',
          'Invalid',
        ]);
        expect(selection.choices.last.selectedByDefault, isFalse);
        expect(() => selection.select(['custom:future']), invalidSnapshot);
        expect(selection.select(['custom:totp']).fields.single.type, 'totp');
      },
    );

    test('rejects empty, duplicate, unknown and non-field selections', () {
      final selection = projector.project(_source());
      for (final ids in <List<String>>[
        [],
        ['notes', 'notes'],
        ['history'],
        ['refs'],
        ['entryKey'],
        ['agentVisibilityPolicy'],
        ['custom:missing'],
      ]) {
        expect(() => selection.select(ids), invalidSnapshot);
      }
      expect(() => selection.choices.clear(), throwsUnsupportedError);
      expect(() => selection.unsupported.clear(), throwsUnsupportedError);
    });

    test(
      'malformed or duplicate custom identity fails without inventing IDs',
      () {
        for (final fields in [
          [
            {'label': 'missing', 'type': 'text', 'value': 'secret'},
          ],
          [
            {'id': '', 'label': 'empty', 'type': 'text', 'value': 'secret'},
          ],
          [
            for (var i = 0; i < 2; i++)
              {
                'id': 'same',
                'label': 'duplicate',
                'type': 'text',
                'value': 'secret',
              },
          ],
          ['not-a-field'],
        ]) {
          expect(
            () => projector.project(_source(payload: {'fields': fields})),
            invalidSnapshot,
          );
        }
      },
    );

    test(
      'key, Script and card project only their allowlisted native fields',
      () {
        final key = projector.project(
          _source(
            type: 0,
            payload: {'value': 'key', 'url': 'url', 'notes': 'private'},
          ),
        );
        expect(key.select(['key.value']).entryType, 'key');
        final script = projector.project(
          _source(
            type: 2,
            payload: {
              'source': 'echo hello',
              'interpreter': 'sh',
              'refs': ['excluded'],
              'parameters': ['excluded'],
              'returnResultToAgent': true,
            },
          ),
        );
        expect(
          script.choices
              .where((field) => field.selectedByDefault)
              .map((field) => field.id),
          ['script.source', 'script.interpreter'],
        );
        expect(
          jsonEncode(script.select(['script.source']).toJson()),
          isNot(contains('excluded')),
        );
        final card = projector.project(
          _source(
            type: 3,
            payload: {
              'cardholderName': 'Person',
              'cardNumber': 'synthetic-number',
              'expiryMonth': '01',
              'expiryYear': '2030',
              'billingAddress': 'private',
            },
          ),
        );
        expect(
          card.choices.where((field) => field.selectedByDefault).length,
          4,
        );
        expect(
          card.choices
              .singleWhere((field) => field.id.endsWith('billingAddress'))
              .selectedByDefault,
          isFalse,
        );
        expect(
          card.select(['creditCard.cardNumber']).fields.single.type,
          'concealed',
        );
      },
    );
  });

  group('sender choices', () {
    test(
      'safe defaults, trimmed email, and explicitly optional protection',
      () {
        final options = EntryShareCreationOptions.fromInput(
          recipientEmail: ' person@example.test ',
          protectionSecret: 'stale-hidden-secret',
        );
        expect(options.recipientMode, EntryShareRecipientMode.namedRecipient);
        expect(options.recipientEmail, 'person@example.test');
        expect(options.protection, EntryShareProtection.none);
        expect(options.protectionSecret, isNull);
        expect(options.lifetimeHours, 24);
        expect(options.maximumReceipts, 1);
        expect(options.notifyOnFirstReceipt, isFalse);
      },
    );

    test(
      'anyone mode drops stale email; additional secret combines with OTP',
      () {
        final anyone = EntryShareCreationOptions.fromInput(
          recipientMode: EntryShareRecipientMode.anyoneWithLink,
          recipientEmail: 'stale-email',
        );
        expect(anyone.recipientEmail, isNull);
        final named = EntryShareCreationOptions.fromInput(
          recipientEmail: 'person@example.test',
          protection: EntryShareProtection.pin,
          protectionSecret: '012345',
          notifyOnFirstReceipt: true,
        );
        expect(named.recipientMode, EntryShareRecipientMode.namedRecipient);
        expect(named.protectionSecret, '012345');
        expect(named.notifyOnFirstReceipt, isTrue);
      },
    );

    test('password whitespace is significant and preserved', () {
      final options = EntryShareCreationOptions.fromInput(
        recipientEmail: 'person@example.test',
        protection: EntryShareProtection.password,
        protectionSecret: ' exact password ',
      );
      expect(options.protectionSecret, ' exact password ');
    });

    test('invalid PINs fail with typed value-free errors', () {
      for (final value in [
        '12345',
        '１２３４５６',
        '١٢٣٤٥٦',
        ' 123456',
        '123456\n',
        '123456 ',
        'a12345',
        '1' * 129,
      ]) {
        expect(
          () => EntryShareCreationOptions.fromInput(
            recipientEmail: 'person@example.test',
            protection: EntryShareProtection.pin,
            protectionSecret: value,
          ),
          throwsA(
            isA<EntryShareFormException>().having(
              (error) => error.kind,
              'kind',
              EntryShareFormError.pin,
            ),
          ),
        );
      }
    });

    test('finite supported expiry and canonical bounded receipt count', () {
      for (final lifetime in [0, -1, 2, 169]) {
        expect(
          () => EntryShareCreationOptions.fromInput(
            recipientEmail: 'person@example.test',
            lifetimeHours: lifetime,
          ),
          throwsA(isA<EntryShareFormException>()),
        );
      }
      for (final count in ['0', '-1', '01', '+1', '1e2', '1.0', '101', '']) {
        expect(
          () => EntryShareCreationOptions.fromInput(
            recipientEmail: 'person@example.test',
            maximumReceipts: count,
          ),
          throwsA(isA<EntryShareFormException>()),
        );
      }
      for (final lifetime in [1, 24, 72, 168]) {
        expect(
          EntryShareCreationOptions.fromInput(
            recipientEmail: 'person@example.test',
            lifetimeHours: lifetime,
            maximumReceipts: '100',
          ).lifetimeHours,
          lifetime,
        );
      }
    });
  });

  group('creation transport', () {
    late _Adapter adapter;
    late EntrySharingRemoteDatasource remote;
    setUp(() {
      adapter = _Adapter();
      remote = EntrySharingRemoteDatasource(Dio()..httpClientAdapter = adapter);
    });

    test(
      'challenge uses scoped POST without body, redirect or numeric revision loss',
      () async {
        adapter.body = jsonEncode({
          'shareId': 'share',
          'sourceRevision': '9007199254740993',
          'expiresAt': '2026-09-22T12:00:00.123456789Z',
          'future': true,
        });
        final token = CancelToken();
        final challenge = await remote.challenge(
          'vault',
          'entry',
          cancelToken: token,
        );
        expect(challenge.sourceRevision, '9007199254740993');
        expect(challenge.expiresAt, '2026-09-22T12:00:00.123456789Z');
        final request = adapter.requests.single;
        expect(request.method, 'POST');
        expect(
          request.path,
          '/api/vaults/vault/entries/entry/sharing/creation-challenge',
        );
        expect(request.data, isNull);
        expect(request.queryParameters, isEmpty);
        expect(request.followRedirects, isFalse);
        expect(request.headers['Cache-Control'], 'no-store');
        expect(request.cancelToken, same(token));
      },
    );

    test(
      'create serializes only explicit contract and retries same bytes',
      () async {
        final body = EntryShareCreationRequest(
          shareId: 'share',
          sourceRevision: '9007199254740993',
          expiresAt: '2026-09-22T12:00:00Z',
          options: EntryShareCreationOptions.fromInput(
            recipientEmail: 'person@example.test',
            protection: EntryShareProtection.pin,
            protectionSecret: '012345',
            notifyOnFirstReceipt: true,
          ),
          accessToken: 'synthetic-bearer',
          packet: const EntryShareCiphertext(
            nonce: 'synthetic-nonce',
            ciphertext: 'synthetic-ciphertext',
          ),
        );
        adapter.status = 503;
        await expectLater(
          remote.create('vault', 'entry', body, cancelToken: CancelToken()),
          throwsA(isA<EntrySharingRequestException>()),
        );
        adapter.status = 201;
        await remote.create('vault', 'entry', body, cancelToken: CancelToken());
        expect(adapter.requests.length, 2);
        expect(
          jsonEncode(adapter.requests.first.data),
          jsonEncode(adapter.requests.last.data),
        );
        final request = adapter.requests.last;
        expect(request.path, '/api/vaults/vault/entries/entry/sharing');
        expect(request.data, {
          'shareId': 'share',
          'sourceRevision': '9007199254740993',
          'expiresAt': '2026-09-22T12:00:00Z',
          'maximumReceipts': 1,
          'recipientMode': 'namedRecipient',
          'recipientEmail': 'person@example.test',
          'protection': 'pin',
          'protectionSecret': '012345',
          'accessToken': 'synthetic-bearer',
          'nonce': 'synthetic-nonce',
          'ciphertext': 'synthetic-ciphertext',
          'notifyOnFirstReceipt': true,
        });
        expect(request.queryParameters, isEmpty);
        expect(request.followRedirects, isFalse);
        expect(request.headers['Cache-Control'], 'no-store');
      },
    );

    test(
      'malformed response and error body never escape the feature boundary',
      () async {
        adapter.body = '{"plaintext":"do-not-log"';
        try {
          await remote.challenge('vault', 'entry', cancelToken: CancelToken());
          fail('Expected redacted exception');
        } catch (error) {
          expect(error, isA<EntrySharingRequestException>());
          expect(error.toString(), isNot(contains('do-not-log')));
        }
      },
    );
  });
}
