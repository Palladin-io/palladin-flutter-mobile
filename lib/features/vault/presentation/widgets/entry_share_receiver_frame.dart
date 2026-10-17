import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_bar_title.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/skeleton_box.dart';
import '../../../../l10n/generated/app_localizations.dart';

class EntryShareReceiverFrame extends StatelessWidget {
  const EntryShareReceiverFrame({super.key, required this.child, this.onClose});
  final Widget child;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => AppScreen.appBar(
    appBar: AppBar(
      titleSpacing: 0,
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: AppColors.transparent,
      surfaceTintColor: AppColors.transparent,
      title: AppBarTitle(
        title: AppLocalizations.of(context)!.sharingReceiveTitle,
      ),
      actions: [
        if (onClose != null)
          IconButton(
            onPressed: onClose,
            tooltip: AppLocalizations.of(context)!.sharingClose,
            icon: const Icon(Icons.close),
          ),
      ],
    ),
    body: child,
  );
}

class EntryShareReceiverPlaceholder extends StatelessWidget {
  const EntryShareReceiverPlaceholder({
    super.key,
    this.waiting = false,
    this.onClose,
  });
  final bool waiting;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => EntryShareReceiverFrame(
    onClose: onClose,
    child: ListView(
      padding: const EdgeInsets.all(AppSpacing.screenH),
      children: [
        if (waiting)
          const SkeletonBox(height: 44)
        else
          Text(AppLocalizations.of(context)!.sharingReceiveUnavailable),
      ],
    ),
  );
}
