import 'dart:convert';

import 'package:dio/dio.dart';

import '../../domain/entities/entry_share_list.dart';

class EntrySharingRemoteDatasource {
  EntrySharingRemoteDatasource(this._dio);
  final Dio _dio;

  String _path(String vaultId, String entryId) =>
      '/api/vaults/${Uri.encodeComponent(vaultId)}/entries/${Uri.encodeComponent(entryId)}/sharing';

  Options get _options => Options(
    responseType: ResponseType.plain,
    followRedirects: false,
    headers: {'Cache-Control': 'no-store'},
  );

  Future<EntrySharesPage> list(
    String vaultId,
    String entryId, {
    String? cursor,
    required CancelToken cancelToken,
  }) async {
    try {
      final response = await _dio.get<String>(
        _path(vaultId, entryId),
        queryParameters: {'cursor': ?cursor},
        options: _options,
        cancelToken: cancelToken,
      );
      // Decode here so parser diagnostics cannot enter the shared HTTP logger.
      final data = jsonDecode(response.data!) as Map<String, dynamic>;
      return EntrySharesPage(
        items: (data['items'] as List).map((raw) {
          final item = raw as Map<String, dynamic>;
          DateTime? date(String key) => item[key] is String
              ? DateTime.tryParse(item[key] as String)?.toLocal()
              : null;
          return EntryShareListItem(
            shareId: item['shareId'] as String,
            status: item['status'] as String,
            expiresAt: date('expiresAt'),
            maximumReceipts: item['maximumReceipts'] as int,
            deliveryCount: item['deliveryCount'] as int,
            firstDeliveredAt: date('firstDeliveredAt'),
            lastDeliveredAt: date('lastDeliveredAt'),
            firstConfirmedAt: date('firstConfirmedAt'),
            notifyOnFirstReceipt: item['notifyOnFirstReceipt'] as bool,
            recipientMode: item['recipientMode'] as String,
            recipientEmail: item['recipientEmail'] as String?,
            protection: item['protection'] as String,
            sourceChanged: item['sourceChanged'] as bool,
          );
        }).toList(),
        nextCursor: data['nextCursor'] as String?,
      );
    } catch (_) {
      throw const EntrySharingRequestException();
    }
  }

  Future<void> revoke(
    String vaultId,
    String entryId,
    String shareId, {
    required CancelToken cancelToken,
  }) async {
    try {
      await _dio.delete<void>(
        '${_path(vaultId, entryId)}/${Uri.encodeComponent(shareId)}',
        options: _options,
        cancelToken: cancelToken,
      );
    } catch (_) {
      throw const EntrySharingRequestException();
    }
  }
}
