import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/core/identity/organization_member_directory_service.dart';
import 'package:mobile_palladin/core/storage/secure_token_storage.dart';

class _TokenStorage extends Mock implements SecureTokenStorage {}

class _DirectoryAdapter implements HttpClientAdapter {
  int calls = 0;
  List<Map<String, Object?>> items = const [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls += 1;
    expect(options.path, '/api/organization/member-directory');
    return ResponseBody.fromString(
      jsonEncode({'items': items}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _TokenStorage tokenStorage;
  late _DirectoryAdapter adapter;
  late OrganizationMemberDirectoryService service;
  var token = _token('org-a');

  setUp(() {
    tokenStorage = _TokenStorage();
    when(() => tokenStorage.accessToken).thenAnswer((_) async => token);
    adapter = _DirectoryAdapter();
    service = OrganizationMemberDirectoryService(
      dio: Dio()..httpClientAdapter = adapter,
      tokenStorage: tokenStorage,
    );
  });

  test(
    'resolves names and attempts one whole-directory missing-id repair',
    () async {
      adapter.items = const [
        {'userId': 'user-a', 'displayName': ' Patryk Roguszewski '},
      ];

      final resolved = await service.resolve({'user-a', 'former-user'});
      final repeated = await service.resolve({'former-user'});

      expect(resolved, {'user-a': 'Patryk Roguszewski'});
      expect(repeated, isEmpty);
      expect(adapter.calls, 2);
    },
  );

  test(
    'changing organization drops the previous in-memory directory',
    () async {
      adapter.items = const [
        {'userId': 'shared-id', 'displayName': 'Organization A'},
      ];
      expect(await service.resolve({'shared-id'}), {
        'shared-id': 'Organization A',
      });

      token = _token('org-b');
      adapter.items = const [
        {'userId': 'shared-id', 'displayName': 'Organization B'},
      ];

      expect(await service.resolve({'shared-id'}), {
        'shared-id': 'Organization B',
      });
      expect(adapter.calls, 2);
    },
  );
}

String _token(String organizationId) {
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${encode({'alg': 'none'})}.${encode({'org_id': organizationId})}.sig';
}
