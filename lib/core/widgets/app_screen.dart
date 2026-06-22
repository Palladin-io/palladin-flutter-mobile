import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Shared skeleton for every top-level screen.
///
/// Enforces the one spacing contract the prototype defines for a screen:
/// the gradient background, a transparent [Scaffold], a [header] slot, and a
/// single [AppSpacing.headerGap] between the header and the first content
/// element. Horizontal padding is owned by the screen body — chrome that must
/// reach the screen edges (search field shadows, hairline separators) stays
/// flush, while content opts into [screenPadding] explicitly.
///
/// Two construction styles map to the two header conventions already in the
/// app:
///   * [AppScreen.appBar] — for screens with a transparent [AppBar] over the
///     gradient (Inbox, Agents, Settings). The AppBar is the header.
///   * [AppScreen] (default) — for screens with a custom header widget
///     rendered in the body (Vault list). Pass the header via [header].
///
/// In both cases [body] receives the content area; it is responsible for its
/// own horizontal padding (use [AppSpacing.screenH], or the [screenPadding]
/// helper for the common symmetric case).
class AppScreen extends StatelessWidget {
  /// Custom-header variant — [header] renders inside the body, above [body],
  /// separated by [AppSpacing.headerGap].
  const AppScreen({
    super.key,
    required this.body,
    this.header,
    this.floatingActionButton,
    this.endDrawer,
    this.gapAfterHeader = true,
  }) : appBar = null;

  /// AppBar variant — [appBar] is the header; [body] fills the remaining area.
  const AppScreen.appBar({
    super.key,
    required PreferredSizeWidget this.appBar,
    required this.body,
    this.floatingActionButton,
    this.endDrawer,
    this.gapAfterHeader = true,
  }) : header = null;

  /// Content area. Owns its own horizontal padding (see [screenPadding]).
  final Widget body;

  /// Custom header widget rendered above [body] (non-AppBar variant).
  final Widget? header;

  /// Transparent AppBar over the gradient (AppBar variant).
  final PreferredSizeWidget? appBar;

  /// Optional shell/page FAB. Pass `const FabRegistrar(fab: null)` to suppress
  /// a covered page's FAB on a pushed screen.
  final Widget? floatingActionButton;

  /// Optional end drawer.
  final Widget? endDrawer;

  /// Whether to insert [AppSpacing.headerGap] between the title (header widget
  /// or AppBar) and [body]. Defaults to `true` in both variants so every
  /// screen has the same title→content rhythm. Set `false` only when [body]
  /// must own the leading gap itself (rare).
  final bool gapAfterHeader;

  /// Symmetric horizontal screen padding helper, for the common case where a
  /// content section spans the full screen width minus the gutters.
  static const EdgeInsets screenPadding = EdgeInsets.symmetric(
    horizontal: AppSpacing.screenH,
  );

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.backgroundGradient(brightness),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: appBar,
        endDrawer: endDrawer,
        floatingActionButton: floatingActionButton,
        body: SafeArea(
          top: appBar == null,
          child: appBar != null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (gapAfterHeader)
                      const SizedBox(height: AppSpacing.headerGap),
                    Expanded(child: body),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ?header,
                    if (header != null && gapAfterHeader)
                      const SizedBox(height: AppSpacing.headerGap),
                    Expanded(child: body),
                  ],
                ),
        ),
      ),
    );
  }
}
