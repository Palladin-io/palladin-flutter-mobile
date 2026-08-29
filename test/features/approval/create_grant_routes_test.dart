import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/approval/data/datasources/approval_remote_datasource.dart';

void main() {
  test(
    'grant variants use distinct routes and request shapes',
    () async {
      final requests = <RequestOptions>[];
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'))
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              requests.add(options);
              handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 201,
                  data: const {'id': 'created'},
                ),
              );
            },
          ),
        );
      final datasource = ApprovalRemoteDatasource(dio);

      await datasource.createGranularGrant(
        vaultId: 'vault',
        entryId: 'entry',
        grantId: 'granular',
        agentId: 'agent',
        grantEntry: const {'descriptor': <String, Object?>{}},
      );
      await datasource.createFullGrant(
        vaultId: 'vault',
        grantId: 'full',
        agentId: 'agent',
        agentWrappedVaultKey: const {'wrappedVaultKey': <String, Object?>{}},
      );
      await datasource.createScriptExecutionGrant(
        vaultId: 'vault',
        scriptEntryId: 'script',
        grantId: 'script-grant',
        agentId: 'agent',
        scriptPackage: const {'contractVersion': 1},
      );

      expect(requests[0].path, '/api/vaults/vault/entries/entry/grants');
      expect(requests[0].data, contains('grantEntry'));
      expect(requests[0].data, isNot(contains('agentWrappedVaultKey')));
      expect(requests[1].path, '/api/vaults/vault/full-grants');
      expect(requests[1].data, contains('agentWrappedVaultKey'));
      expect(requests[1].data, isNot(contains('grantEntry')));
      expect(requests[2].path, '/api/vaults/vault/scripts/script/grants');
      expect(requests[2].data, contains('scriptPackage'));
      expect(requests[2].data, isNot(contains('grantEntry')));
      expect(requests[2].data, isNot(contains('agentWrappedVaultKey')));
    },
  );
}
