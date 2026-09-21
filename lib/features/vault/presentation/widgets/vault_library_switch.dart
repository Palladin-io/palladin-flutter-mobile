import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/widgets/app_segmented_control.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../shell/presentation/cubit/library_view_cubit.dart';
import '../../../shell/presentation/pages/app_shell.dart';

class VaultLibrarySwitch extends StatelessWidget {
  const VaultLibrarySwitch({super.key, required this.entries});
  final bool entries;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.md),
      child: SizedBox(
        width: AppSpacing.controlHeight * 2,
        child: AppSegmentedControl<bool>(
          value: entries,
          options: [
            AppSegment(
              value: true,
              label: l10n.vaultTabEntries,
              icon: Icons.key_outlined,
            ),
            AppSegment(
              value: false,
              label: l10n.navVaults,
              icon: Icons.shield_outlined,
            ),
          ],
          onChanged: (value) {
            if (entries == value) return;
            unawaited(context.read<LibraryViewCubit>().select(value));
            AppShellScope.of(context).showFabToast?.call(
              value ? l10n.libraryEntriesHint : l10n.libraryVaultsHint,
            );
            context.go(value ? '/entries' : '/vaults');
          },
        ),
      ),
    );
  }
}
