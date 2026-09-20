import 'entry_share.dart';

final class EntryShareRecipientSession {
  const EntryShareRecipientSession({
    required this.sessionId,
    required this.sessionToken,
    required this.expiresAt,
    required this.recipientMode,
    required this.protection,
  });

  final String sessionId, sessionToken, expiresAt, recipientMode, protection;
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
