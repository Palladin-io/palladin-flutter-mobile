const maximumAutoFillRecords = 2000;

String? normalizeAutoFillDomain(String? raw) {
  if (raw == null) return null;
  final value = raw.trim();
  if (value.isEmpty) return null;
  try {
    if (value.codeUnits.any((unit) => unit > 0x7f)) return null;
    if (RegExp(
      r'^[a-z][a-z0-9+.-]*://[^/?#]+:[0-9]+(?:[/?#]|$)',
      caseSensitive: false,
    ).hasMatch(value)) {
      return null;
    }
    final uri = Uri.parse(value.contains('://') ? value : 'https://$value');
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    if (uri.userInfo.isNotEmpty || uri.hasPort || uri.authority.contains(':')) {
      return null;
    }
    var host = uri.host.toLowerCase();
    while (host.endsWith('.')) {
      host = host.substring(0, host.length - 1);
    }
    if (host.isEmpty ||
        !host.contains('.') ||
        host.contains('..') ||
        host.startsWith('.') ||
        host
            .split('.')
            .any(
              (label) =>
                  label.isEmpty ||
                  label.length > 63 ||
                  label.startsWith('-') ||
                  label.endsWith('-') ||
                  !RegExp(r'^[a-z0-9-]+$').hasMatch(label),
            )) {
      return null;
    }
    return host;
  } on FormatException {
    return null;
  }
}
