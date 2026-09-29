import 'entry_share.dart';

enum EntryShareRecipientMode { namedRecipient, anyoneWithLink }

enum EntryShareProtection { none, password, pin }

enum EntryShareFormError { email, password, pin, lifetime, maximumReceipts }

// Sender input feedback, never a substitute for the backend verification gate.
bool obviousSharingPin(String value) {
  if (!RegExp(r'^[0-9]+$').hasMatch(value)) return false;
  for (final width in [1, 2, 3]) {
    if (value.length >= width * 2 &&
        value.length % width == 0 &&
        value ==
            List.filled(
              value.length ~/ width,
              value.substring(0, width),
            ).join()) {
      return true;
    }
  }
  return [1, 9].any((step) {
    for (var index = 1; index < value.length; index++) {
      if ((int.parse(value[index]) - int.parse(value[index - 1]) + 10) % 10 !=
          step) {
        return false;
      }
    }
    return true;
  });
}

final class EntryShareFormException implements Exception {
  const EntryShareFormException(this.kind);
  final EntryShareFormError kind;
}

final class EntryShareCreationOptions {
  const EntryShareCreationOptions._({
    required this.recipientMode,
    required this.recipientEmail,
    required this.protection,
    required this.protectionSecret,
    required this.lifetimeHours,
    required this.maximumReceipts,
    required this.notifyOnFirstReceipt,
  });

  factory EntryShareCreationOptions.fromInput({
    EntryShareRecipientMode recipientMode =
        EntryShareRecipientMode.anyoneWithLink,
    String recipientEmail = '',
    EntryShareProtection protection = EntryShareProtection.none,
    String protectionSecret = '',
    int lifetimeHours = 24,
    String maximumReceipts = '',
    bool notifyOnFirstReceipt = false,
  }) {
    final email = recipientEmail.trim();
    if (recipientMode == EntryShareRecipientMode.namedRecipient &&
        (email.length > 320 ||
            !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email))) {
      throw const EntryShareFormException(EntryShareFormError.email);
    }
    // A protection secret is exact user input, not a label to normalize.
    if (protection == EntryShareProtection.password &&
        (protectionSecret.length < 8 || protectionSecret.length > 128)) {
      throw const EntryShareFormException(EntryShareFormError.password);
    }
    if (protection == EntryShareProtection.pin &&
        (!RegExp(r'^[0-9]{6,128}$').hasMatch(protectionSecret) ||
            obviousSharingPin(protectionSecret))) {
      throw const EntryShareFormException(EntryShareFormError.pin);
    }
    if (!{1, 24, 72, 168}.contains(lifetimeHours)) {
      throw const EntryShareFormException(EntryShareFormError.lifetime);
    }
    final receiptInput = maximumReceipts.trim();
    final receipts = int.tryParse(receiptInput);
    if (receiptInput.isNotEmpty &&
        (!RegExp(r'^[1-9][0-9]{0,2}$').hasMatch(receiptInput) ||
            receipts == null ||
            receipts > 100)) {
      throw const EntryShareFormException(EntryShareFormError.maximumReceipts);
    }
    return EntryShareCreationOptions._(
      recipientMode: recipientMode,
      recipientEmail: recipientMode == EntryShareRecipientMode.namedRecipient
          ? email
          : null,
      protection: protection,
      protectionSecret: protection == EntryShareProtection.none
          ? null
          : protectionSecret,
      lifetimeHours: lifetimeHours,
      maximumReceipts: receipts,
      notifyOnFirstReceipt: notifyOnFirstReceipt,
    );
  }

  final EntryShareRecipientMode recipientMode;
  final String? recipientEmail;
  final EntryShareProtection protection;
  final String? protectionSecret;
  final int lifetimeHours;
  final int? maximumReceipts;
  final bool notifyOnFirstReceipt;
}

final class EntryShareCreationChallenge {
  const EntryShareCreationChallenge({
    required this.shareId,
    required this.sourceRevision,
    required this.expiresAt,
  });
  final String shareId, sourceRevision, expiresAt;
}

final class EntryShareCreationRequest {
  const EntryShareCreationRequest({
    required this.shareId,
    required this.sourceRevision,
    required this.expiresAt,
    required this.options,
    required this.accessToken,
    required this.packet,
  });
  final String shareId, sourceRevision, expiresAt, accessToken;
  final EntryShareCreationOptions options;
  final EntryShareCiphertext packet;

  Map<String, Object?> toJson() => {
    'shareId': shareId,
    'sourceRevision': sourceRevision,
    'expiresAt': expiresAt,
    'maximumReceipts': options.maximumReceipts,
    'recipientMode': options.recipientMode.name,
    'recipientEmail': options.recipientEmail,
    'protection': options.protection.name,
    'protectionSecret': options.protectionSecret,
    'accessToken': accessToken,
    'nonce': packet.nonce,
    'ciphertext': packet.ciphertext,
    'notifyOnFirstReceipt': options.notifyOnFirstReceipt,
  };
}
