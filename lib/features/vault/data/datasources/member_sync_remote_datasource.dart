import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/member_sync_models.dart';
import '../../domain/entities/vault_performance_budget.dart';

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
    int pageSize = VaultPerformanceBudget.memberSyncPageItems,
  });

  Future<MemberDeltaResult> delta({
    required String vaultId,
    String? afterSequence,
    String? continuationCursor,
    int pageSize = VaultPerformanceBudget.memberSyncPageItems,
  });
}

/// Dio implementation of [MemberSyncRemote].
final class MemberSyncRemoteDatasource implements MemberSyncRemote {
  MemberSyncRemoteDatasource(this._dio);

  static const _headers = <String, String>{
    'X-Palladin-Vault-Protocol': '2',
    'X-Palladin-Sync-Policy': '2',
    'Accept-Encoding': 'identity',
  };

  final Dio _dio;

  @override
  Future<MemberSnapshotPage> snapshot({
    required String vaultId,
    String? cursor,
    int pageSize = VaultPerformanceBudget.memberSyncPageItems,
  }) async {
    final response = await _dio.post<List<int>>(
      '/api/vaults/$vaultId/current-entries/sync/snapshot',
      data: {'vaultId': vaultId, 'cursor': cursor, 'pageSize': pageSize},
      options: Options(headers: _headers, responseType: ResponseType.bytes),
    );
    return MemberSnapshotPage.fromJson(_body(response));
  }

  @override
  Future<MemberDeltaResult> delta({
    required String vaultId,
    String? afterSequence,
    String? continuationCursor,
    int pageSize = VaultPerformanceBudget.memberSyncPageItems,
  }) async {
    if ((afterSequence == null) == (continuationCursor == null)) {
      throw ArgumentError(
        'Exactly one of afterSequence or continuationCursor is required',
      );
    }
    try {
      final response = await _dio.post<List<int>>(
        '/api/vaults/$vaultId/current-entries/sync/delta',
        data: {
          'vaultId': vaultId,
          'afterSequence': ?afterSequence,
          'continuationCursor': ?continuationCursor,
          'pageSize': pageSize,
        },
        options: Options(headers: _headers, responseType: ResponseType.bytes),
      );
      return MemberDeltaSuccess(MemberDeltaPage.fromJson(_body(response)));
    } on DioException catch (error) {
      if (error.response?.statusCode != 409) rethrow;
      return MemberDeltaResetRequired(
        MemberSyncReset.fromJson(_body(error.response!)),
      );
    }
  }

  Map<String, dynamic> _body(Response<dynamic> response) {
    if (response.headers.value('content-encoding')?.toLowerCase() !=
        'identity') {
      throw const FormatException('Compressed Vault sync is not supported');
    }
    final protocol = response.headers.value('x-palladin-vault-protocol');
    final policy = response.headers.value('x-palladin-sync-policy');
    final declaredLength = int.tryParse(
      response.headers.value(Headers.contentLengthHeader) ?? '',
    );
    if (protocol != '2' ||
        policy != '2' ||
        (declaredLength != null &&
            (declaredLength < 0 ||
                declaredLength >
                    VaultPerformanceBudget.maximumMemberSyncResponseBytes))) {
      throw const FormatException('Unsupported or empty Vault sync response');
    }
    final data = response.data;
    if (data is! List<int> ||
        data.length > VaultPerformanceBudget.maximumMemberSyncResponseBytes) {
      throw const FormatException('Vault sync response exceeds byte limit');
    }
    final decoded = jsonDecode(utf8.decode(data, allowMalformed: false));
    if (decoded is! Map) {
      throw const FormatException('Vault sync response must be an object');
    }
    return Map<String, dynamic>.from(decoded);
  }
}
