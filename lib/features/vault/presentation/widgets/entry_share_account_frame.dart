import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../entry_share_account_continuation.dart';

class EntryShareAccountFrame extends StatefulWidget {
  const EntryShareAccountFrame({
    super.key,
    required this.continuation,
    required this.child,
  });

  final EntryShareAccountContinuation continuation;
  final Widget child;

  @override
  State<EntryShareAccountFrame> createState() => _EntryShareAccountFrameState();
}

class _EntryShareAccountFrameState extends State<EntryShareAccountFrame> {
  int? _confirmingGeneration;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.continuation,
    child: widget.child,
    builder: (context, child) {
      final continuation = widget.continuation;
      final active = continuation.active;
      final confirming = _confirmingGeneration == continuation.generation;
      final l10n = AppLocalizations.of(context)!;
      final brightness = Theme.of(context).brightness;
      return SafeArea(
        top: active,
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            children: [
              if (active)
                Material(
                  color: AppColors.modalBackground(brightness),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight:
                          (constraints.maxHeight -
                                  MediaQuery.viewInsetsOf(context).bottom)
                              .clamp(0, constraints.maxHeight) /
                          2,
                    ),
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.screenH,
                          vertical: AppSpacing.sm,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              confirming
                                  ? l10n.sharingCancelAccountNotice
                                  : l10n.sharingAccountPending,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.onSurfaceMuted(brightness),
                              ),
                            ),
                            Wrap(
                              alignment: WrapAlignment.end,
                              spacing: AppSpacing.innerGap,
                              children: [
                                if (confirming)
                                  TextButton(
                                    onPressed: () => setState(
                                      () => _confirmingGeneration = null,
                                    ),
                                    child: Text(l10n.sharingKeepReception),
                                  ),
                                TextButton(
                                  onPressed: () {
                                    if (confirming) {
                                      continuation.cancel(
                                        _confirmingGeneration!,
                                      );
                                    } else {
                                      setState(() {
                                        _confirmingGeneration =
                                            continuation.generation;
                                      });
                                    }
                                  },
                                  child: Text(
                                    confirming
                                        ? l10n.sharingDiscardReception
                                        : l10n.sharingCancelReception,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              else
                const SizedBox.shrink(),
              Expanded(child: ClipRect(child: child!)),
            ],
          ),
        ),
      );
    },
  );
}
