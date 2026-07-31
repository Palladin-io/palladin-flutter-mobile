import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/agents/data/datasources/agents_remote_data_source.dart';

void main() {
  test(
    'uses canonical presign and complete contracts for agent icons',
    () async {
      final requests = <RequestOptions>[];
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'))
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              requests.add(options);
              if (options.path.endsWith('/presign')) {
                handler.resolve(
                  Response<Map<String, dynamic>>(
                    requestOptions: options,
                    data: {
                      'assetId': 'asset-1',
                      'uploadSessionId': 'session-1',
                      'uploadUrl': 'https://upload.example.test/icon',
                      'maximumBytes': 1048576,
                    },
                  ),
                );
                return;
              }
              handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  data: {
                    'assetId': 'asset-1',
                    'publicUrl': 'https://cdn.example.test/icon',
                    'revision': 1,
                  },
                ),
              );
            },
          ),
        );
      final remote = AgentsRemoteDataSource(dio);

      final presign = await remote.presignAgentIcon(
        'agent-1',
        mediaType: 'image/png',
        byteLength: 128,
        sha256: 'a' * 64,
      );
      final completed = await remote.completeAgentIcon(
        'agent-1',
        presign.uploadSessionId,
      );

      expect(presign.maximumBytes, 1048576);
      expect(completed.assetId, 'asset-1');
      expect(requests[0].path, '/api/agents/agent-1/icon/presign');
      expect(requests[0].data, {
        'agentId': 'agent-1',
        'mediaType': 'image/png',
        'byteLength': 128,
        'sha256': 'a' * 64,
      });
      expect(requests[1].path, '/api/agents/agent-1/icon/complete');
      expect(requests[1].data, {
        'agentId': 'agent-1',
        'uploadSessionId': 'session-1',
      });
    },
  );
}
