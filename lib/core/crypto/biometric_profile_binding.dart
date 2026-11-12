import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../config/env_config.dart';

String biometricProfileBinding({
  required AppFlavor flavor,
  required String apiBaseUrl,
  required String principalId,
}) {
  final uri = Uri.parse(apiBaseUrl);
  if (principalId.isEmpty ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.scheme != 'https' &&
          !(flavor == AppFlavor.local && uri.scheme == 'http'))) {
    throw const FormatException('Invalid biometric profile scope');
  }
  var path = uri.normalizePath().path;
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  final endpoint = Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: path,
  ).toString();
  return sha256
      .convert(
        utf8.encode(
          jsonEncode([
            'palladin-biometric-profile-v1',
            flavor.name,
            endpoint,
            principalId,
          ]),
        ),
      )
      .toString();
}
