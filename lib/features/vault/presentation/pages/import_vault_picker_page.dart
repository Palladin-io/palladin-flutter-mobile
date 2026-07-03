import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/skeleton_box.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/entities/vault_entity.dart';
import '../cubit/vault_list_cubit.dart';
import 'import_wizard_page.dart';

/// Step 0 of the global import flow (launched from the settings drawer):
/// choose which vault the imported entries land in, then hand off to
/// [ImportWizardPage]. For the per-vault entry point this screen is
/// skipped — the vault is already known.
class ImportVaultPickerPage extends StatelessWidget {
  const ImportVaultPickerPage({super.key});

  static Future<void> push(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(builder: (_) => const ImportVaultPickerPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<VaultListCubit>.value(
      value: getIt<VaultListCubit>()..loadIfNeeded(),
      child: const _PickerView(),
    );
  }
}

class _PickerView extends StatelessWidget {
  const _PickerView();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return AppScreen.appBar(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: AppColors.onSurface(brightness)),
        titleSpacing: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.importTitle,
              style: TextStyle(
                color: AppColors.onSurface(brightness),
                fontSize: 16,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.importSelectVaultSubtitle,
              style: TextStyle(
                color: AppColors.onSurfaceSubtle(brightness),
                fontSize: 11,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
      body: BlocBuilder<VaultListCubit, VaultListState>(
        builder: (context, state) {
          return switch (state) {
            VaultListInitial() || VaultListLoading() => const _Skeleton(),
            VaultListError() => _Message(text: l10n.vaultErrorUnknown),
            VaultListLoaded(:final vaults) => vaults.isEmpty
                ? _Message(text: l10n.importNoVaults)
                : _VaultList(vaults: vaults),
          };
        },
      ),
    );
  }
}

class _VaultList extends StatelessWidget {
  const _VaultList({required this.vaults});

  final List<VaultEntity> vaults;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        0,
        AppSpacing.screenH,
        AppSpacing.listBottom,
      ),
      itemCount: vaults.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.cardGap),
      itemBuilder: (_, i) => _VaultRow(vault: vaults[i]),
    );
  }
}

class _VaultRow extends StatelessWidget {
  const _VaultRow({required this.vault});

  final VaultEntity vault;

  Future<void> _onTap(BuildContext context) async {
    final imported = await ImportWizardPage.push(
      context,
      vaultId: vault.id,
      vaultName: vault.name,
      wrappedVK: vault.wrappedVK,
    );
    if (imported == true && context.mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return InkWell(
      onTap: () => _onTap(context),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: AppColors.cardFill(brightness),
          border: Border.all(color: AppColors.cardBorder(brightness)),
        ),
        child: Row(
          children: [
            Icon(Icons.shield_outlined,
                size: 20, color: AppColors.onSurfaceSubtle(brightness)),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    vault.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.onSurface(brightness),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    l10n.vaultEntryCount(vault.entryCount),
                    style: TextStyle(
                      color: AppColors.onSurfaceMuted(brightness),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                size: 20, color: AppColors.onSurfaceSubtle(brightness)),
          ],
        ),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        0,
        AppSpacing.screenH,
        AppSpacing.listBottom,
      ),
      children: [
        for (var i = 0; i < 4; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.cardGap),
            child: SkeletonBox(
              height: 64,
              delay: Duration(milliseconds: i * 80),
            ),
          ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.onSurfaceMuted(brightness),
            fontSize: 14,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}
