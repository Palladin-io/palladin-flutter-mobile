import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/app_search_field.dart';
import '../../../../l10n/generated/app_localizations.dart';

/// The shared Entries surface. Owners supply data and permitted actions.
class EntriesListView extends StatelessWidget {
  const EntriesListView({
    super.key,
    required this.count,
    required this.search,
    required this.onSearchChanged,
    required this.slivers,
    this.actions,
    this.leading,
    this.footer,
    this.floatingActionButton,
    this.scrollController,
    this.onRefresh,
    this.showSearch = true,
  });

  final int count;
  final TextEditingController search;
  final ValueChanged<String> onSearchChanged;
  final List<Widget> slivers;
  final List<Widget>? actions;
  final Widget? leading, footer, floatingActionButton;
  final ScrollController? scrollController;
  final Future<void> Function()? onRefresh;
  final bool showSearch;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scroll = CustomScrollView(
      controller: scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showSearch) ...[
                  AppSearchField(
                    controller: search,
                    hint: l10n.entrySearchHint,
                    onChanged: onSearchChanged,
                  ),
                  const SizedBox(height: AppSpacing.fieldGap),
                ],
                ?leading,
              ],
            ),
          ),
        ),
        ...slivers,
      ],
    );
    return AppScreen.titled(
      title: l10n.vaultTabEntries,
      subtitle: l10n.vaultEntryCount(count),
      actions: actions,
      safeAreaBottom: footer == null,
      floatingActionButton: floatingActionButton,
      body: Column(
        children: [
          Expanded(
            child: onRefresh == null
                ? scroll
                : RefreshIndicator(onRefresh: onRefresh!, child: scroll),
          ),
          ?footer,
        ],
      ),
    );
  }
}
