import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../../autofill/data/autofill_mutation_notifier.dart';
import '../../../domain/entities/entry_share.dart';
import '../../../domain/entities/entry_share_copy.dart';
import '../../../domain/entities/entry_share_list.dart';
import '../../../domain/entities/vault_plaintext.dart';
import '../../datasources/entry_share_copy_datasource.dart';
import '../../models/entry_v2_contracts.dart';
import '../entry_v2_crypto_service.dart';
import '../vault_crypto_service.dart';
import 'entry_share_copy_projection_service.dart';
import 'entry_share_copy_vault_authority.dart';

final class PreparedEntryShareCopy {
  PreparedEntryShareCopy._(
    this.vaultId,
    this.entryId,
    this.owner,
    this._encodedBody,
  );
  final String vaultId, entryId;
  final EntrySharingSession owner;
  String? _encodedBody;
  bool get isDisposed => _encodedBody == null;
  void dispose() => _encodedBody = null;
}

class EntryShareCopyService {
  EntryShareCopyService({
    required EntryShareCopyDatasource remote,
    required VaultCryptoService vaultCrypto,
    required EntryV2CryptoService entryCrypto,
    required AutoFillMutationNotifier autoFill,
  }) : _remote = remote,
       _vaultCrypto = vaultCrypto,
       _entryCrypto = entryCrypto,
       _autoFill = autoFill;

  final EntryShareCopyDatasource _remote;
  final VaultCryptoService _vaultCrypto;
  final EntryV2CryptoService _entryCrypto;
  final AutoFillMutationNotifier _autoFill;

  Future<PreparedEntryShareCopy> prepare({
    required EntryShareSnapshot snapshot,
    required String vaultId,
    required EntrySharingSession owner,
    required Uint8List memberPrivateKey,
    required Future<bool> Function() validateOwner,
    required CancelToken cancelToken,
    String? title,
    Map<String, String> completedFields = const {},
  }) async {
    final privateKey = Uint8List.fromList(memberPrivateKey);
    final ownedKeys = <Uint8List>[privateKey];
    void wipe() {
      for (final key in ownedKeys) {
        key.fillRange(0, key.length, 0);
      }
      ownedKeys.clear();
    }

    unawaited(cancelToken.whenCancel.then((_) => wipe()));
    try {
      if (privateKey.length != 32) {
        throw const EntryShareCopyException(
          EntryShareCopyError.invalidAuthority,
        );
      }
      final secret = const EntryShareCopyProjectionService().project(
        snapshot: snapshot,
        title: title,
        completedFields: completedFields,
      );
      await _requireCurrent(validateOwner, cancelToken);
      final vault = await _remote.vault(vaultId, owner, cancelToken);
      await _requireCurrent(validateOwner, cancelToken);
      // Request/session and top-level epoch are independent of encrypted descriptors.
      final authority = EntryShareCopyVaultAuthority.read(
        vault,
        vaultId,
        owner,
      );
      final opened = await _vaultCrypto.openVaultProjection(
        json: vault,
        memberPrivateKey: privateKey,
      );
      ownedKeys.add(opened.vaultKey);
      final vdk = opened.vaultDiscoveryKey;
      if (vdk != null) ownedKeys.add(vdk);
      await _requireCurrent(validateOwner, cancelToken);
      if (vdk == null) {
        throw const EntryShareCopyException(
          EntryShareCopyError.invalidAuthority,
        );
      }
      final entryId = await _remote.challenge(vaultId, owner, cancelToken);
      await _requireCurrent(validateOwner, cancelToken);
      final envelopes = await _entryCrypto.seal(
        organizationId: owner.organizationId,
        vaultId: vaultId,
        entryId: entryId,
        revision: 1,
        vaultKeyVersion: authority.vaultKeyVersion,
        vdkVersion: authority.vdkVersion,
        memberKeyGeneration: authority.memberKeyGeneration,
        operation: 1,
        secret: secret,
        vaultKey: opened.vaultKey,
        vaultDiscoveryKey: vdk,
      );
      await _requireCurrent(validateOwner, cancelToken);
      return PreparedEntryShareCopy._(
        vaultId,
        entryId,
        owner,
        jsonEncode(
          CreateEntryV2Request(
            vaultId: vaultId,
            entryId: entryId,
            envelopes: envelopes,
            deliveryPolicy: switch (secret.entryType) {
              VaultEntryType.script => 'execOnly',
              VaultEntryType.creditCard => 'injectOnly',
              _ => 'standard',
            },
          ).toJson(),
        ),
      );
    } on EntryShareCopyInputException {
      rethrow;
    } on EntryShareCopyException {
      rethrow;
    } catch (_) {
      throw const EntryShareCopyException(EntryShareCopyError.encryption);
    } finally {
      wipe();
    }
  }

  Future<void> commit(
    PreparedEntryShareCopy copy, {
    required Future<bool> Function() validateOwner,
    required CancelToken cancelToken,
  }) async {
    AutoFillMutationLease? lease;
    bool committed = false;
    try {
      await _requireCurrent(validateOwner, cancelToken);
      if (copy.isDisposed) {
        throw const EntryShareCopyException(EntryShareCopyError.cancelled);
      }
      lease = await _autoFill.beginMutation();
      await _requireCurrent(validateOwner, cancelToken);
      final body = copy._encodedBody;
      if (body == null) {
        throw const EntryShareCopyException(EntryShareCopyError.cancelled);
      }
      await _remote.create(copy.vaultId, body, copy.owner, cancelToken);
      committed = true;
      copy.dispose();
      await _requireCurrent(validateOwner, cancelToken);
    } on EntryShareCopyException {
      rethrow;
    } catch (_) {
      throw const EntryShareCopyException(EntryShareCopyError.request);
    } finally {
      try {
        if (committed) {
          await lease?.complete();
        } else {
          await lease?.leaveAmbiguous();
        }
      } catch (_) {
        // A cache rebuild failure cannot undo a confirmed create or authorize a second Entry.
      }
    }
  }

  Future<void> _requireCurrent(
    Future<bool> Function() validateOwner,
    CancelToken token,
  ) async {
    if (token.isCancelled || !await validateOwner() || token.isCancelled) {
      throw const EntryShareCopyException(EntryShareCopyError.cancelled);
    }
  }

  void close() => _remote.close();
}
