import 'dart:io';

import 'package:dio/dio.dart';

import '../../domain/entities/vault_member.dart';
import '../../domain/repositories/vault_members_repository.dart';
import '../datasources/vault_members_remote_datasource.dart';

/// Bounded repository for the Vault Member management surface.
final class VaultMembersRepositoryImpl implements VaultMembersRepository {
  VaultMembersRepositoryImpl(this._remote, {this.maximumMembers = 2000});

  final VaultMembersRemote _remote;
  final int maximumMembers;

  @override
  Future<List<VaultMember>> list(String vaultId) async {
    try {
      final result = <VaultMember>[];
      final seenCursors = <String>{};
      String? afterId;
      do {
        final page = await _remote.list(vaultId, afterId: afterId);
        if (result.length + page.items.length > maximumMembers) {
          throw const FormatException('Vault Member directory exceeds limit');
        }
        result.addAll(page.items.map((item) => item.toEntity()));
        final next = page.nextAfterId;
        if (next != null && !seenCursors.add(next)) {
          throw const FormatException('Vault Member cursor did not advance');
        }
        afterId = next;
      } while (afterId != null);
      return List.unmodifiable(result);
    } on DioException catch (error) {
      throw VaultMembersException(_classify(error));
    }
  }

  @override
  Future<void> requestRemoval(String memberId) async {
    try {
      await _remote.requestRemoval(memberId);
    } on DioException catch (error) {
      throw VaultMembersException(_classify(error));
    }
  }

  VaultMembersErrorKind _classify(DioException error) {
    if (error.error is SocketException ||
        error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return VaultMembersErrorKind.network;
    }
    if (error.response?.statusCode == 403) {
      return VaultMembersErrorKind.forbidden;
    }
    if (error.response?.statusCode == 409) {
      return VaultMembersErrorKind.protectedMember;
    }
    return VaultMembersErrorKind.unknown;
  }
}
