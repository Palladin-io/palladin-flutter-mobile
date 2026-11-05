/// Font families available without bundled font assets.
abstract final class AppFonts {
  /// Android resolves the generic `monospace` family; iOS has no family by
  /// that name, so [monospaceFallback] supplies its system monospace fonts.
  static const String monospace = 'monospace';
  static const List<String> monospaceFallback = ['Menlo', 'Courier'];
}
