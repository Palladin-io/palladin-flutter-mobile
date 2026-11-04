import 'dart:typed_data';

import '../../unlock/data/models/account_response.dart';
import '../data/security_upgrade_service.dart';

/// How the non-dismissable upgrade screen starts. Held in memory only.
sealed class SecurityUpgradeStart {
  const SecurityUpgradeStart();

  /// Wipes every key buffer the start owns.
  void dispose();
}

/// First unlock of a security-version-1 account.
final class FreshSecurityUpgrade extends SecurityUpgradeStart {
  FreshSecurityUpgrade({
    required this.password,
    required this.account,
    required this.legacyPrivateKey,
  });

  final String password;
  final AccountResponse account;
  final Uint8List legacyPrivateKey;

  @override
  void dispose() => legacyPrivateKey.fillRange(0, legacyPrivateKey.length, 0);
}

/// The upgrade committed earlier but envelopes still address the old key.
final class ResumedSecurityUpgrade extends SecurityUpgradeStart {
  ResumedSecurityUpgrade(this.keys);

  final UpgradedAccountKeys keys;

  @override
  void dispose() => keys.dispose();
}
