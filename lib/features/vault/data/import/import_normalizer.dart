import 'import_models.dart';

/// Pure, dependency-free normalisation shared by every import parser.
///
/// The parsers hand raw source strings here and get back a fully-formed
/// [ParsedEntry]: trimmed fields, a wrapped `otpauth://` TOTP URI, a host
/// pulled out of the URL, and a name synthesised from the host when the
/// source has no title (Firefox).
///
/// Nothing in this file logs — the values passing through include
/// passwords and TOTP seeds.
class ImportNormalizer {
  ImportNormalizer._();

  /// Builds a normalised [ParsedEntry] from raw source fields, or `null`
  /// when the row is not a login (no secret and no username) and should
  /// be counted as skipped.
  ///
  /// [rawTotp] may be a full `otpauth://` URI or a bare Base32 secret;
  /// bare secrets are wrapped. [isBareTotpSecret] forces the wrap path
  /// for sources (Dashlane) that always export a bare secret.
  static ParsedEntry? build({
    String? name,
    String? username,
    String? password,
    String? url,
    String? notes,
    String? rawTotp,
    String? folder,
    bool isBareTotpSecret = false,
  }) {
    final trimmedUser = _clean(username);
    final trimmedPass = _clean(password);
    final trimmedUrl = _clean(url);
    final host = hostFrom(trimmedUrl);

    // A login must carry at least a password or a username — rows with
    // neither (secure notes, blank lines) are dropped by the caller.
    if (trimmedPass == null && trimmedUser == null) return null;

    final resolvedName =
        _clean(name) ??
        (host != null ? nameFromHost(host) : null) ??
        trimmedUser;

    return ParsedEntry(
      name: resolvedName,
      username: trimmedUser,
      password: trimmedPass,
      url: trimmedUrl,
      urlDomain: host,
      notes: _clean(notes),
      totp: normalizeTotp(
        rawTotp,
        issuer: host,
        accountName: trimmedUser ?? resolvedName,
        isBareSecret: isBareTotpSecret,
      ),
      folder: _clean(folder),
    );
  }

  /// Normalises a TOTP value to an `otpauth://` URI, or returns `null`
  /// when there is no usable secret.
  ///
  /// A value that already starts with `otpauth://` is passed through
  /// untouched. A bare Base32 secret (or any value when [isBareSecret] is
  /// set) is wrapped into a canonical `otpauth://totp/...` URI.
  static String? normalizeTotp(
    String? raw, {
    String? issuer,
    String? accountName,
    bool isBareSecret = false,
  }) {
    final value = _clean(raw);
    if (value == null) return null;

    if (value.toLowerCase().startsWith('otpauth://')) return value;

    // Strip spaces some managers put in the Base32 secret for display.
    final secret = value.replaceAll(RegExp(r'\s+'), '');
    if (secret.isEmpty) return null;
    // Only wrap things that plausibly are a Base32 secret — avoids
    // turning a stray URL or note into a bogus otpauth URI.
    if (!isBareSecret && !_looksLikeBase32(secret)) return null;

    final account = _clean(accountName) ?? 'account';
    final label = issuer != null && issuer.isNotEmpty
        ? '$issuer:$account'
        : account;
    final query = StringBuffer('secret=${Uri.encodeComponent(secret)}');
    if (issuer != null && issuer.isNotEmpty) {
      query.write('&issuer=${Uri.encodeComponent(issuer)}');
    }
    return 'otpauth://totp/${Uri.encodeComponent(label)}?$query';
  }

  /// Google Password Manager app-credential URI:
  /// `android://<signing-cert hash>@<package>/`.
  static final RegExp _androidCredentialUri = RegExp(
    r'^android://[^@]+@([a-zA-Z0-9_.]+)/?$',
  );

  /// Package ids are reverse-DNS — `com.facebook.katana` → `facebook.com`.
  static String? _domainFromAndroidPackage(String packageId) {
    final labels = packageId.toLowerCase().split('.');
    if (labels.length < 2) return null;
    final tld = labels[0];
    final name = labels[1];
    if (name.isEmpty || !RegExp(r'^[a-z]{2,6}$').hasMatch(tld)) return null;
    return '$name.$tld';
  }

  /// Extracts the bare host from a URL string (no scheme, no path).
  /// Returns `null` when [raw] is blank or yields no host.
  static String? hostFrom(String? raw) {
    final text = _clean(raw);
    if (text == null) return null;
    final androidMatch = _androidCredentialUri.firstMatch(text);
    if (androidMatch != null) {
      return _domainFromAndroidPackage(androidMatch.group(1)!);
    }
    final toParse = text.contains('://') ? text : 'https://$text';
    final uri = Uri.tryParse(toParse);
    // A dotless "host" (stray scheme, app id) is useless as a urlDomain.
    if (uri != null && uri.host.contains('.')) return uri.host;
    final withoutScheme = text.replaceFirst(
      RegExp(r'^[a-zA-Z][a-zA-Z0-9+\-.]*://'),
      '',
    );
    final firstSegment = withoutScheme.split('/').first.split('?').first;
    return firstSegment.contains('.') ? firstSegment : null;
  }

  /// Derives a display name from a host — drops a leading `www.` and
  /// title-cases the registrable label (`www.github.com` → `Github`).
  static String nameFromHost(String host) {
    var h = host.toLowerCase();
    if (h.startsWith('www.')) h = h.substring(4);
    final firstLabel = h.split('.').first;
    if (firstLabel.isEmpty) return host;
    return firstLabel[0].toUpperCase() + firstLabel.substring(1);
  }

  static String? _clean(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static bool _looksLikeBase32(String value) {
    if (value.length < 8) return false;
    return RegExp(r'^[A-Za-z2-7]+=*$').hasMatch(value);
  }
}
