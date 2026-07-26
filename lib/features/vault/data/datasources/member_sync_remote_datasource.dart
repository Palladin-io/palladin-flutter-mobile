import 'package:dio/dio.dart';

import '../models/member_sync_models.dart';

/// Result of a delta request, including the protocol-defined reset outcome.
sealed class MemberDeltaResult {
  const MemberDeltaResult();
}

final class MemberDeltaSuccess extends MemberDeltaResult {
  const MemberDeltaSuccess(this.page);
  final MemberDeltaPage page;
}

final class MemberDeltaResetRequired extends MemberDeltaResult {
  const MemberDeltaResetRequired(this.reset);
  final MemberSyncReset reset;
}

/// Network boundary for protocol-2 Member snapshot and delta sync.
abstract interface class MemberSyncRemote {
  Future<MemberSnapshotPage> snapshot({
    required String vaultId,
    String? cursor,
    int pageSize = 100,
  });

  Future<MemberDeltaResult> delta({
    required String vaultId,
    String? afterSequence,
    String? continuationCursor,
    int pageSize = 100,
  });
}

/// Dio implementation of [MemberSyncRemote].
final class MemberSyncRemoteDatasource implements MemberSyncRemote {
  MemberSyncRemoteDatasource(this._dio);

  static const _headers = <String, String>{
    'X-Palladin-Vault-Protocol': '2',
    'X-Palladin-Sync-Policy': '1',
    'Accept-Encoding': 'identity',
  };

  final Dio _dio;

  @override
  Future<MemberSnapshotPage> snapshot({
    required String vaultId,
    String? cursor,
    int pageSize = 100,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/vaults/$vaultId/sync/snapshot',
      data: {'vaultId': vaultId, 'cursor': ?cursor, 'pageSize': pageSize},
      options: Options(headers: _headers),
    );
    return MemberSnapshotPage.fromJson(_body(response));
  }

  @override
  Future<MemberDeltaResult> delta({
    required String vaultId,
    String? afterSequence,
    String? continuationCursor,
    int pageSize = 100,
  }) async {
    if ((afterSequence == null) == (continuationCursor == null)) {
      throw ArgumentError(
        'Exactly one of afterSequence or continuationCursor is required',
      );
    }
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/vaults/$vaultId/sync/delta',
        data: {
          'vaultId': vaultId,
          'afterSequence': ?afterSequence,
          'continuationCursor': ?continuationCursor,
          'pageSize': pageSize,
        },
        options: Options(headers: _headers),
      );
      return MemberDeltaSuccess(MemberDeltaPage.fromJson(_body(response)));
    } on DioException catch (error) {
      if (error.response?.statusCode != 409) rethrow;
      final data = error.response?.data;
      if (data is! Map) rethrow;
      return MemberDeltaResetRequired(
        MemberSyncReset.fromJson(Map<String, dynamic>.from(data)),
      );
    }
  }

  Map<String, dynamic> _body(Response<Map<String, dynamic>> response) {
    if (response.headers.value('content-encoding') case final encoding?
        when encoding.toLowerCase() != 'identity') {
      throw const FormatException('Compressed Vault sync is not supported');
    }
    final protocol = response.headers.value('x-palladin-vault-protocol');
    final policy = response.headers.value('x-palladin-sync-policy');
    if (protocol != '2' || policy != '1' || response.data == null) {
      throw const FormatException('Unsupported or empty Vault sync response');
    }
    return response.data!;
  }
}
