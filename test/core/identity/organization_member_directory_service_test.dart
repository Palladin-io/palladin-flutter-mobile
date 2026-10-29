import 'dart:async';
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
  Future<List<Map<String, Object?>>> Function()? read;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls += 1;
    expect(options.path, '/api/organization/member-directory');
    return ResponseBody.fromString(
      jsonEncode({'items': await (read?.call() ?? Future.value(items))}),
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
    token = _token('org-a');
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
  test(
    'same-organization account replacement cannot reuse former cache',
    () async {
      adapter.items = const [
        {'userId': 'actor', 'displayName': 'Old account'},
      ];
      expect(await service.resolve({'actor'}), {'actor': 'Old account'});
      token = _token('org-a', accountId: 'replacement');
      adapter.items = const [
        {'userId': 'actor', 'displayName': 'New account'},
      ];
      expect(await service.resolve({'actor'}), {'actor': 'New account'});
      expect(adapter.calls, 2);
    },
  );

  test(
    'old pending resolution cannot return a replacement organization name',
    () async {
      final old = Completer<List<Map<String, Object?>>>();
      adapter.read = () => old.future;
      final pending = service.resolve({'actor'});
      await Future<void>.delayed(Duration.zero);
      token = _token('org-b');
      adapter.read = () async => [
        {'userId': 'actor', 'displayName': 'New organization'},
      ];
      expect(await service.resolve({'actor'}), {'actor': 'New organization'});
      old.complete([
        {'userId': 'actor', 'displayName': 'Old organization'},
      ]);
      expect(await pending, isEmpty);
      expect(adapter.calls, 2);
    },
  );
  test('available lookups share HTTP and group missing-id repair', () async {
    adapter.items = const [
      {'userId': 'former', 'displayName': 'Former Member'},
    ];
    final first = await Future.wait([
      for (var i = 0; i < 8; i++)
        service.availableSnapshot(
          expectedAccountId: 'account',
          expectedOrganizationId: 'org-a',
        ),
    ]);
    expect(
      first.map((snapshot) => snapshot.names),
      everyElement({'former': 'Former Member'}),
    );
    expect(first.every((snapshot) => snapshot.canRepair), true);
    expect(adapter.calls, 1);
    final missing = {for (var i = 0; i < 8; i++) 'missing-$i'};
    await service.resolve(
      missing,
      expectedAccountId: 'account',
      expectedOrganizationId: 'org-a',
    );
    await service.resolve(
      missing,
      expectedAccountId: 'account',
      expectedOrganizationId: 'org-a',
    );
    expect(adapter.calls, 2);
  });

  test(
    'warm snapshot survives token refresh within the same identity',
    () async {
      adapter.items = const [
        {'userId': 'actor', 'displayName': 'Member'},
      ];
      await service.resolve({'actor'});
      token = '${_token('org-a')}-refreshed';
      expect(
        (await service.availableSnapshot(
          expectedAccountId: 'account',
          expectedOrganizationId: 'org-a',
        )).names,
        {'actor': 'Member'},
      );
      expect(adapter.calls, 1);
    },
  );

  test(
    'expected caller identity rejects another account or organization',
    () async {
      adapter.items = const [
        {'userId': 'actor', 'displayName': 'Member'},
      ];
      expect(
        (await service.availableSnapshot(
          expectedAccountId: 'other',
          expectedOrganizationId: 'org-a',
        )).names,
        isEmpty,
      );
      expect(
        await service.resolve(
          {'actor'},
          expectedAccountId: 'account',
          expectedOrganizationId: 'other',
        ),
        isEmpty,
      );
      expect(adapter.calls, 0);
    },
  );

  for (final boundary in ['clear', 'account', 'organization', 'logout']) {
    test(
      'pending HTTP cannot return names after $boundary without another lookup',
      () async {
        final pending = Completer<List<Map<String, Object?>>>();
        adapter.read = () => pending.future;
        final result = service.resolve({'actor'});
        await Future<void>.delayed(Duration.zero);
        switch (boundary) {
          case 'clear':
            service.clear();
          case 'account':
            token = _token('org-a', accountId: 'other');
          case 'organization':
            token = _token('org-b');
          case 'logout':
            token = '';
        }
        pending.complete([
          {'userId': 'actor', 'displayName': 'Old Member'},
        ]);
        expect(await result, isEmpty);
        expect(adapter.calls, 1);
      },
    );
  }
  test(
    'failed stale refresh keeps warm names but forbids immediate repair',
    () async {
      service = OrganizationMemberDirectoryService(
        dio: Dio()..httpClientAdapter = adapter,
        tokenStorage: tokenStorage,
        staleTime: Duration.zero,
      );
      adapter.items = [
        {'userId': 'actor', 'displayName': 'Former Member'},
      ];
      await service.resolve({'actor'});
      adapter.read = () async => throw DioException(
        requestOptions: RequestOptions(
          path: '/api/organization/member-directory',
        ),
      );
      final snapshot = await service.availableSnapshot(
        expectedAccountId: 'account',
        expectedOrganizationId: 'org-a',
      );
      expect(snapshot.names, {'actor': 'Former Member'});
      expect(snapshot.canRepair, false);
      expect(adapter.calls, 2);
    },
  );

  test('successful empty directory permits one batched repair', () async {
    final snapshot = await service.availableSnapshot(
      expectedAccountId: 'account',
      expectedOrganizationId: 'org-a',
    );
    expect(snapshot.names, isEmpty);
    expect(snapshot.canRepair, true);
    await service.resolve({'missing-a', 'missing-b'});
    expect(adapter.calls, 2);
  });

  test('failed directory HTTP does not trigger a missing-id repair', () async {
    adapter.read = () async => throw DioException(
      requestOptions: RequestOptions(
        path: '/api/organization/member-directory',
      ),
    );
    expect(await service.resolve({'actor'}), isEmpty);
    expect(adapter.calls, 1);
  });
}

String _token(String organizationId, {String accountId = 'account'}) {
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${encode({'alg': 'none'})}.${encode({'org_id': organizationId, 'sub': accountId})}.sig';
}
