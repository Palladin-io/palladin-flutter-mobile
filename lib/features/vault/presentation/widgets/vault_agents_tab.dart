import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import 'grant_card.dart';

/// Agents tab on the vault detail page.
///
/// Shows a search bar (with separate filter button), then a vertical
/// list of [GrantCard]s. Mock data lives at the top of the file —
/// real wiring lands when the grants API is finalised.
class VaultAgentsTab extends StatefulWidget {
  const VaultAgentsTab({super.key, required this.grants});

  final List<MockGrant> grants;

  @override
  State<VaultAgentsTab> createState() => _VaultAgentsTabState();
}

class _VaultAgentsTabState extends State<VaultAgentsTab> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<MockGrant> get _filtered {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return widget.grants;
    return widget.grants
        .where((g) => g.agent.name.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _SearchBar(
                controller: _searchController,
                hint: l10n.vaultSearchAgents,
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            const _FilterButton(),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _filtered.isEmpty
              ? _EmptyAgents(l10n: l10n)
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: _filtered.length,
                  itemBuilder: (_, index) => GrantCard(grant: _filtered[index]),
                ),
        ),
      ],
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.mobileSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, size: 18, color: AppColors.textTertiaryMobile),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle: const TextStyle(
                  color: AppColors.textTertiaryMobile,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.mobileSurface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          // Filter sheet lands in a follow-up ticket.
        },
        child: const SizedBox(
          width: 36,
          height: 36,
          child: Icon(
            Icons.filter_list,
            size: 18,
            color: AppColors.textTertiaryMobile,
          ),
        ),
      ),
    );
  }
}

class _EmptyAgents extends StatelessWidget {
  const _EmptyAgents({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.smart_toy_outlined,
              size: 36,
              color: AppColors.textTertiaryMobile,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.vaultAgentsEmpty,
              style: const TextStyle(
                color: AppColors.textTertiaryMobile,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
