import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../../../config/env_config.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../data/services/emergency_kit_pdf_service.dart';

/// Localized labels for the Emergency Kit PDF.
EmergencyKitLabels emergencyKitLabels(AppLocalizations l10n) =>
    EmergencyKitLabels(
      title: l10n.emergencyKitPdfTitle,
      intro: l10n.emergencyKitPdfIntro,
      account: l10n.emergencyKitPdfAccount,
      secretKey: l10n.emergencyKitPdfSecretKey,
      secretKeyQr: l10n.emergencyKitPdfQr,
      masterPassword: l10n.emergencyKitPdfPassword,
      signInAddress: l10n.emergencyKitPdfSignIn,
      generated: l10n.emergencyKitPdfGenerated,
      footer: l10n.emergencyKitPdfFooter,
    );

/// Public web address users open to sign in: the configured web origin, or
/// the API host without its `api.` label.
String emergencyKitSignInAddress(EnvConfig config) {
  if (config.sharingWebOrigin.isNotEmpty) return config.sharingWebOrigin;
  final api = Uri.parse(config.apiBaseUrl);
  final host = api.host.startsWith('api.') ? api.host.substring(4) : api.host;
  return Uri(
    scheme: api.scheme,
    host: host,
    port: api.hasPort ? api.port : null,
  ).toString();
}

/// Builds the kit on the device and hands it to the system share sheet.
Future<void> exportEmergencyKit({
  required BuildContext context,
  required EmergencyKitPdfService service,
  required EnvConfig config,
  required String email,
  required String accountId,
  required Uint8List accountSecret,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final locale = Localizations.localeOf(context).toLanguageTag();
  final bytes = await service.build(
    email: email,
    accountId: accountId,
    accountSecret: accountSecret,
    signInAddress: emergencyKitSignInAddress(config),
    generatedDate: DateFormat.yMMMMd(locale).format(DateTime.now()),
    labels: emergencyKitLabels(l10n),
  );
  try {
    await service.share(bytes);
  } finally {
    bytes.fillRange(0, bytes.length, 0);
  }
}
