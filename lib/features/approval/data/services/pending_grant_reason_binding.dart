import '../../../grants/domain/entities/grant_method.dart';
import '../../domain/entities/encrypted_reason.dart';
import '../../domain/entities/pending_grant.dart';

/// Checks the envelope against the independently returned request metadata.
/// Called before review and submission, never while merely listing requests.
EncryptedReason requireBoundGrantReason(PendingGrant grant) {
  final reason = grant.encryptedReason;
  var requestedMethods = 0;
  for (final method in grant.requestedMethods) {
    requestedMethods |= switch (method) {
      GrantMethod.get => 1,
      GrantMethod.exec => 2,
      GrantMethod.inject => 4,
    };
  }
  if (reason == null ||
      reason.vaultId != grant.vaultId ||
      reason.entryId != grant.entryId ||
      reason.grantRequestId != grant.grantId ||
      reason.agentId != grant.agentId ||
      reason.descriptor['protocolVersion'] != 2 ||
      reason.descriptor['cryptoSuiteId'] != 'palladin-vault-xchacha-v1' ||
      !const {'encryptedReason', 9}.contains(reason.descriptor['purpose']) ||
      reason.scope['memberId'] != null ||
      reason.binding['wrapperSuiteId'] != 'palladin-x25519-sealed-box-v1' ||
      reason.requestedMethods != requestedMethods) {
    throw const FormatException('Encrypted reason scope mismatch');
  }
  return reason;
}
