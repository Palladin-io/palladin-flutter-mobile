/// How an agent's CLI may use a credential:
///   - [get]    returns the plaintext into the agent's context (LLM exposure)
///   - [exec]   injects the secret into a subprocess environment
///   - [inject] fills a browser login form
///
/// The backend `Grant.Methods` is a `[Flags]` enum serialized as a combined
/// comma-separated string ("get, exec"). [parseGrantMethods] /
/// [serializeGrantMethods] convert between that wire form and this list form.
enum GrantMethod {
  get,
  exec,
  inject;

  /// PascalCase name the backend's flags converter accepts.
  String get wireName => switch (this) {
    GrantMethod.get => 'Get',
    GrantMethod.exec => 'Exec',
    GrantMethod.inject => 'Inject',
  };
}

/// Default for a proactive grant: the privacy-preserving methods; `get` is opt-in.
const List<GrantMethod> kDefaultGrantMethods = [
  GrantMethod.exec,
  GrantMethod.inject,
];

/// Parse the backend's combined-flags string ("get, exec") into a canonically
/// ordered, de-duplicated list. Tolerates casing/spacing; skips unknown tokens.
/// Returns `[]` for null/empty so callers can fall back to a default.
List<GrantMethod> parseGrantMethods(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  final tokens = raw
      .split(',')
      .map((s) => s.trim().toLowerCase())
      .where((s) => s.isNotEmpty)
      .toSet();
  // Canonical order (get, exec, inject) regardless of input order.
  return GrantMethod.values.where((m) => tokens.contains(m.name)).toList();
}

/// Serialize to the backend wire form: PascalCase joined by ", " in canonical
/// order (e.g. "Get, Exec").
String serializeGrantMethods(List<GrantMethod> methods) {
  return GrantMethod.values
      .where(methods.contains)
      .map((m) => m.wireName)
      .join(', ');
}
