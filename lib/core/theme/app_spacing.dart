/// Single source of truth for spacing. Mirror of [AppColors]: never write a
/// bare numeric gap/padding in the app — always reference `AppSpacing.*`.
///
/// Semantic tokens map the "HTML Prototype Spacing Standard" (Mobile defaults)
/// from the root CLAUDE.md. Prefer a semantic token (e.g. [section], [cardGap])
/// when one fits the context; fall back to a raw scale step ([xs]…[xxxl]) only
/// for spacing the semantic set does not name.
abstract final class AppSpacing {
  // Base 4-pt scale — the only allowed raw step values.
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  // Semantic tokens — prefer these over raw steps.
  /// Screen horizontal padding.
  static const double screenH = 20;

  /// Header row → first content element.
  static const double headerGap = 16;

  /// Vertical gap between sections.
  static const double section = 16;

  /// Input↔input and search-bar → content.
  static const double fieldGap = 12;

  /// Vertical gap between cards / list separators.
  static const double cardGap = 10;

  /// Card internal padding.
  static const double cardPadding = 14;

  /// Gap between elements inside a card.
  static const double innerGap = 8;

  /// Gap between filter chips.
  static const double chipGap = 6;

  /// Last element → bottom on a non-scrolling screen.
  static const double screenBottom = 32;

  /// Bottom padding for a scrollable list — clears the FAB + bottom nav.
  static const double listBottom = 96;
}
