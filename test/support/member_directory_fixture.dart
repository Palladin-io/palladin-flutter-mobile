import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/core/identity/organization_member_directory_service.dart';
import 'package:mobile_palladin/core/storage/secure_token_storage.dart';

class _Tokens extends Mock implements SecureTokenStorage {}

/// Real shared directory service with an in-memory HTTP adapter.
class MemberDirectoryFixture implements HttpClientAdapter {
  MemberDirectoryFixture({
    String organizationId = 'org',
    String accountId = 'account',
  }) {
    final tokens = _Tokens();
    final payload = base64Url
        .encode(
          utf8.encode(jsonEncode({'org_id': organizationId, 'sub': accountId})),
        )
        .replaceAll('=', '');
    when(() => tokens.accessToken).thenAnswer((_) async => 'e30.$payload.sig');
    service = OrganizationMemberDirectoryService(
      dio: Dio()..httpClientAdapter = this,
      tokenStorage: tokens,
    );
  }

  late final OrganizationMemberDirectoryService service;
  Future<List<Map<String, Object?>>> Function() read = () async => [];
  int calls = 0;
  final started = Completer<void>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    expect(options.method, 'GET');
    expect(options.path, '/api/organization/member-directory');
    calls++;
    if (!started.isCompleted) started.complete();
    return ResponseBody.fromString(
      jsonEncode({'items': await read()}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
