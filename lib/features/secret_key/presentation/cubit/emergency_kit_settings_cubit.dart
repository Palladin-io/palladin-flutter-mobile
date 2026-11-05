import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/crypto/identity/secret_key_codec.dart';
import '../../../../core/storage/account_secret_store.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../unlock/data/models/account_response.dart';
import '../../../unlock/data/services/identity_kdf_service.dart';

sealed class EmergencyKitSettingsState {
  const EmergencyKitSettingsState();
}

final class EmergencyKitSettingsLoading extends EmergencyKitSettingsState {
  const EmergencyKitSettingsLoading();
}

/// This device holds no Secret Key for the account.
final class EmergencyKitSettingsMissing extends EmergencyKitSettingsState {
  const EmergencyKitSettingsMissing();
}

final class EmergencyKitSettingsLoadFailed extends EmergencyKitSettingsState {
  const EmergencyKitSettingsLoadFailed();
}

/// Ready to export; holds only non-secret display data.
final class EmergencyKitSettingsReady extends EmergencyKitSettingsState {
  const EmergencyKitSettingsReady({
    required this.email,
    required this.maskedSecretKey,
    this.busy = false,
    this.wrongPassword = false,
    this.exportFailed = false,
    this.exported = false,
  });

  final String email;
  final String maskedSecretKey;
  final bool busy;
  final bool wrongPassword;
  final bool exportFailed;
  final bool exported;

  EmergencyKitSettingsReady copyWith({
    bool busy = false,
    bool wrongPassword = false,
    bool exportFailed = false,
    bool exported = false,
  }) => EmergencyKitSettingsReady(
    email: email,
    maskedSecretKey: maskedSecretKey,
    busy: busy,
    wrongPassword: wrongPassword,
    exportFailed: exportFailed,
    exported: exported,
  );
}

/// Exports the Emergency Kit again after re-confirming the master password.
///
/// The password is checked locally: the v2 master key derived from it and
/// the stored Secret Key must equal the unlocked session's master key.
class EmergencyKitSettingsCubit extends Cubit<EmergencyKitSettingsState> {
  EmergencyKitSettingsCubit({
    required this.accountId,
    required this.store,
    required this.loadAccount,
    required this.kdfService,
  }) : super(const EmergencyKitSettingsLoading());

  final String accountId;
  final AccountSecretStore store;
  final Future<AccountResponse> Function() loadAccount;
  final IdentityKdfService kdfService;
  IdentityKdfMetadata? _kdf;

  Future<void> load() async {
    emit(const EmergencyKitSettingsLoading());
    try {
      final secret = await store.read(accountId);
      if (secret == null) {
        if (!isClosed) emit(const EmergencyKitSettingsMissing());
        return;
      }
      final String display;
      try {
        display = SecretKeyCodec.format(accountId, secret);
      } finally {
        secret.fillRange(0, secret.length, 0);
      }
      final account = await loadAccount();
      _kdf = account.kdf;
      if (isClosed) return;
      emit(
        EmergencyKitSettingsReady(
          email: account.email,
          maskedSecretKey: maskSecretKey(display),
        ),
      );
    } catch (error) {
      AppLogger.w('EmergencyKit', 'Load failed: ${error.runtimeType}');
      if (!isClosed) emit(const EmergencyKitSettingsLoadFailed());
    }
  }

  /// Verifies [password] and, on success, runs [export] with the Secret Key.
  /// The key is zeroed when [export] completes.
  Future<void> exportKit({
    required String password,
    required Uint8List sessionMasterKey,
    required Future<void> Function(String email, Uint8List secret) export,
  }) async {
    final current = state;
    final kdf = _kdf;
    if (current is! EmergencyKitSettingsReady || current.busy) return;
    emit(current.copyWith(busy: true));
    Uint8List? secret;
    Uint8List? salt;
    IdentityKdfOutputs? outputs;
    try {
      secret = await store.read(accountId);
      if (secret == null) {
        if (!isClosed) emit(const EmergencyKitSettingsMissing());
        return;
      }
      if (kdf == null ||
          kdfService.assertSupported(kdf) !=
              IdentityKdfVersion.accountSecretV2) {
        throw const UnsupportedIdentityKdfException('unsupported-kdf-profile');
      }
      salt = Uint8List.fromList(
        base64Url.decode(base64Url.normalize(kdf.kdfSalt)),
      );
      outputs = await kdfService.deriveV2(
        password: password,
        accountId: accountId,
        kdfSalt: salt,
        accountSecret: secret,
      );
      if (!_constantTimeEqual(outputs.masterKey, sessionMasterKey)) {
        if (!isClosed) emit(current.copyWith(wrongPassword: true));
        return;
      }
      await export(current.email, secret);
      if (!isClosed) emit(current.copyWith(exported: true));
    } catch (error) {
      AppLogger.w('EmergencyKit', 'Export failed: ${error.runtimeType}');
      if (!isClosed) emit(current.copyWith(exportFailed: true));
    } finally {
      secret?.fillRange(0, secret.length, 0);
      salt?.fillRange(0, salt.length, 0);
      outputs?.dispose();
    }
  }
}

/// `PSK2-••••••-••••••-…-••W9TZ`: prefix plus the last four symbols.
String maskSecretKey(String display) =>
    'PSK2-••••••-••••••-…-••${display.substring(display.length - 4)}';

bool _constantTimeEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  var difference = 0;
  for (var i = 0; i < left.length; i++) {
    difference |= left[i] ^ right[i];
  }
  return difference == 0;
}
