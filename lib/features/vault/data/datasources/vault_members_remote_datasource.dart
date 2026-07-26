import 'package:dio/dio.dart';

import '../models/vault_member_model.dart';

/// One cursor page from the structural Vault Member directory.
final class VaultMemberPage {
  const VaultMemberPage({required this.items, this.nextAfterId});

  final List<VaultMemberModel> items;
  final String? nextAfterId;
}

/// REST boundary for Vault Member status and staged removal requests.
abstract interface class VaultMembersRemote {
  Future<VaultMemberPage> list(String vaultId, {String? afterId});

  Future<void> requestRemoval(String memberId);
}

final class VaultMembersRemoteDatasource implements VaultMembersRemote {
  VaultMembersRemoteDatasource(this._dio);

  final Dio _dio;

  @override
  Future<VaultMemberPage> list(String vaultId, {String? afterId}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/vaults/$vaultId/members',
      queryParameters: {'pageSize': 100, 'afterId': ?afterId},
    );
    final body = response.data;
    final rawItems = body?['items'];
    if (body == null || rawItems is! List || rawItems.length > 100) {
      throw const FormatException('Malformed Vault Member page');
    }
    return VaultMemberPage(
      items: rawItems
          .map(
            (item) => VaultMemberModel.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false),
      nextAfterId: body['nextAfterId'] as String?,
    );
  }

  @override
  Future<void> requestRemoval(String memberId) =>
      _dio.delete<void>('/api/organization/members/$memberId');
}
