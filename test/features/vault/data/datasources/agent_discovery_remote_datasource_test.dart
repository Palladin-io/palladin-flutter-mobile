import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/vault/data/datasources/agent_discovery_remote_datasource.dart';

void main() {
  test(
    'paginates bounded structural status without retaining public keys',
    () async {
      final requests = <Map<String, dynamic>>[];
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'))
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              if (options.path == '/api/vaults/vault-1') {
                handler.resolve(
                  Response<Map<String, dynamic>>(
                    requestOptions: options,
                    data: {
                      'currentKeyEpoch': {'vdkVersion': 6},
                    },
                  ),
                );
                return;
              }
              requests.add(Map<String, dynamic>.from(options.queryParameters));
              final after = options.queryParameters['afterId'];
              handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'items': [
                      {
                        'agentId': after == null
                            ? 'agent-current'
                            : 'agent-stale',
                        'agentName': after == null ? 'Builder' : null,
                        'x25519PublicKey': 'must-not-enter-ui-state',
                        'ed25519PublicKey': 'must-not-enter-ui-state',
                        'recipientKeyVersion': after == null ? 4 : 7,
                        'status': after == null ? 'current' : 'pending',
                        'manifestRevision': after == null ? '12' : '9',
                      },
                    ],
                    'nextAfterId': after == null ? 'cursor-1' : null,
                  },
                ),
              );
            },
          ),
        );

      final result = await AgentDiscoveryRemoteDatasource(dio).list('vault-1');

      expect(result, hasLength(2));
      expect(result.first.isCurrent, isTrue);
      expect(result.last.isCurrent, isFalse);
      expect(result.last.agentName, isNull);
      expect(
        await AgentDiscoveryRemoteDatasource(dio).currentVdkVersion('vault-1'),
        6,
      );
      expect(requests, [
        {'pageSize': 100},
        {'pageSize': 100, 'afterId': 'cursor-1'},
      ]);
      expect(
        result.first.toString(),
        isNot(contains('must-not-enter-ui-state')),
      );
    },
  );

  test('fails closed for an unknown provisioning status', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'))
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              data: {
                'items': [
                  {
                    'agentId': 'agent-1',
                    'recipientKeyVersion': 1,
                    'status': 'ready-ish',
                  },
                ],
                'nextAfterId': null,
              },
            ),
          ),
        ),
      );

    await expectLater(
      AgentDiscoveryRemoteDatasource(dio).list('vault-1'),
      throwsFormatException,
    );
  });
}
