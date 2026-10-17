import 'entry_share.dart';

final class EntryShareRecipientSession {
  const EntryShareRecipientSession({
    required this.sessionId,
    required this.sessionToken,
    required this.expiresAt,
    required this.recipientMode,
    required this.protection,
    this.shareExpiresAt,
    this.maximumReceipts,
    this.otpRetryAfterSeconds = 0,
  });

  final String sessionId, sessionToken, expiresAt, recipientMode, protection;
  final String? shareExpiresAt;
  final int? maximumReceipts;
  final int otpRetryAfterSeconds;
}

final class EntryShareDelivery {
  const EntryShareDelivery({required this.authority, required this.packet});
  final EntryShareScope authority;
  final EntryShareCiphertext packet;
}

final class EntryShareRecipientRequestException implements Exception {
  const EntryShareRecipientRequestException();

  @override
  String toString() => 'EntryShareRecipientRequestException';
}

typedef EntryShareRecipientOwner = ({
  String? principalId,
  String? organizationId,
  String? authorizationGeneration,
  int keyGeneration,
});
