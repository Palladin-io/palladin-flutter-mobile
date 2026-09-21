import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_search_field.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/sheet_drag_handle.dart';
import '../../../../core/widgets/skeleton_box.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../cubit/vault_list_cubit.dart';
import 'vault_card.dart';

class ChooseEntryVaultSheet extends StatefulWidget {
  const ChooseEntryVaultSheet({super.key, required this.onCreateFirstVault});
  final VoidCallback onCreateFirstVault;
  @override
  State<ChooseEntryVaultSheet> createState() => _ChooseEntryVaultSheetState();
}

class _ChooseEntryVaultSheetState extends State<ChooseEntryVaultSheet> {
  final _search = TextEditingController();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is! AuthAuthenticated || state.isVaultLocked) {
          _search.clear();
          final route = ModalRoute.of(context);
          if (route?.isCurrent ?? false) Navigator.of(context).pop();
        }
      },
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .7,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
            child: Column(
              children: [
                const SheetDragHandle(),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l10n.globalEntriesChooseVault,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.fieldGap),
                AppSearchField(
                  controller: _search,
                  hint: l10n.vaultSearchHint,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: AppSpacing.fieldGap),
                Expanded(
                  child: BlocBuilder<VaultListCubit, VaultListState>(
                    builder: (context, state) {
                      if (state is VaultListError ||
                          state is VaultListResetRequired) {
                        return Center(child: Text(l10n.vaultErrorUnknown));
                      }
                      if (state is VaultListLocked) {
                        return const SizedBox.shrink();
                      }
                      if (state is! VaultListLoaded) {
                        return const SkeletonBox(height: 80);
                      }
                      if (state.vaults.isEmpty) {
                        return Center(
                          child: PrimaryButton(
                            label: l10n.vaultNewVault,
                            onPressed: widget.onCreateFirstVault,
                          ),
                        );
                      }
                      final vaults = state.vaults
                          .where(
                            (vault) => vault.name.toLowerCase().contains(
                              _search.text.trim().toLowerCase(),
                            ),
                          )
                          .toList();
                      if (vaults.isEmpty) {
                        return Center(child: Text(l10n.vaultSearchEmpty));
                      }
                      return ListView.separated(
                        itemCount: vaults.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.cardGap),
                        itemBuilder: (_, index) => VaultCard(
                          vault: vaults[index],
                          onTap: () => Navigator.of(context).pop(vaults[index]),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
