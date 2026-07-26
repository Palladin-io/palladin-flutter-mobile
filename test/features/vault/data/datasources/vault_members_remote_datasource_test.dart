import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/vault/data/datasources/vault_members_remote_datasource.dart';

void main() {
  test('reads structural status and starts org-wide staged removal', () async {
    final requests = <RequestOptions>[];
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'))
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            if (options.method == 'DELETE') {
              handler.resolve(Response<void>(requestOptions: options));
              return;
            }
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                data: {
                  'items': [
                    {
                      'memberId': 'member-1',
                      'memberName': 'Patryk',
                      'addedAt': '2026-07-01T10:00:00Z',
                      'deprovisioningStatus': 'WaitingForRotation',
                      'rotationId': 'rotation-opaque',
                    },
                  ],
                  'nextAfterId': null,
                },
              ),
            );
          },
        ),
      );
    final remote = VaultMembersRemoteDatasource(dio);

    final page = await remote.list('vault-1');
    await remote.requestRemoval('member-1');

    expect(page.items.single.memberName, 'Patryk');
    expect(page.items.single.deprovisioningStatus, 'WaitingForRotation');
    expect(requests.first.path, '/api/vaults/vault-1/members');
    expect(requests.first.queryParameters, {'pageSize': 100});
    expect(requests.last.path, '/api/organization/members/member-1');
    expect(requests.last.method, 'DELETE');
  });
}
