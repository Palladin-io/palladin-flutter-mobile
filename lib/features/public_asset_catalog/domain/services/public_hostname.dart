import 'dart:io';

/// Normalizes only public DNS hostnames suitable for catalog resolution.
abstract final class PublicHostname {
  static String? normalize(String? input) {
    final raw = input?.trim();
    if (raw == null || raw.isEmpty) return null;
    final parsed = Uri.tryParse(raw.contains('://') ? raw : 'https://$raw');
    final host = parsed?.host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
    if (host == null || host.isEmpty || host.length > 253) return null;
    if (host == 'localhost' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local') ||
        host.endsWith('.internal')) {
      return null;
    }
    final address = InternetAddress.tryParse(host);
    if (address != null) return null;
    final labels = host.split('.');
    if (labels.length < 2 ||
        labels.any(
          (label) =>
              label.isEmpty ||
              label.length > 63 ||
              !RegExp(r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$').hasMatch(label),
        )) {
      return null;
    }
    return host;
  }

  static List<String> unique(Iterable<String?> inputs, {int limit = 100}) {
    final result = <String>[];
    final seen = <String>{};
    for (final input in inputs) {
      final host = normalize(input);
      if (host != null && seen.add(host)) result.add(host);
      if (result.length == limit) break;
    }
    return result;
  }
}
