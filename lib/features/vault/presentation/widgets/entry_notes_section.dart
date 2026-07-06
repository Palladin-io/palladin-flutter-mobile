import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/generated/app_localizations.dart';
import 'entry_form_widgets.dart';
import 'totp_section.dart' show DottedBorderBox;

/// Add-on-demand Notes field. Hidden by default behind a discreet dashed
/// "+ Add notes" ghost row (mirroring the empty 2FA affordance); tapping it
/// reveals the textarea. When the entry already has notes it renders the
/// field immediately. Purely presentational — the controller is the source
/// of truth, so hiding the field never changes the payload.
class EntryNotesSection extends StatefulWidget {
  const EntryNotesSection({
    super.key,
    required this.controller,
    required this.initiallyVisible,
  });

  final TextEditingController controller;
  final bool initiallyVisible;

  @override
  State<EntryNotesSection> createState() => _EntryNotesSectionState();
}

class _EntryNotesSectionState extends State<EntryNotesSection> {
  late bool _visible = widget.initiallyVisible;
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _reveal() {
    setState(() => _visible = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (_visible) {
      return EntryNotesField(
        controller: widget.controller,
        label: l10n.entryNotesLabel,
        focusNode: _focusNode,
      );
    }

    final brightness = Theme.of(context).brightness;
    return InkWell(
      onTap: _reveal,
      borderRadius: BorderRadius.circular(12),
      child: DottedBorderBox(
        brightness: brightness,
        child: Row(
          children: [
            Icon(
              Icons.sticky_note_2_outlined,
              size: 18,
              color: AppColors.onSurfaceSubtle(brightness),
            ),
            const SizedBox(width: AppSpacing.md),
            Text(
              l10n.entryAddNotes,
              style: TextStyle(
                color: AppColors.onSurfaceSubtle(brightness),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
