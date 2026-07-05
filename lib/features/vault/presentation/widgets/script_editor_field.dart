import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_menu_sheet.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/entities/entry_entity.dart';

/// Fixed-height code editor for a Script entry (mockup parity): a line-
/// number gutter, an inline interpreter picker in the field label, and a
/// footer showing the interpreter + line count. The body scrolls inside a
/// fixed box so long scripts never push the surrounding form. The
/// exec-only note is a calm annotation below (script accent), not a
/// [WarningZone].
class ScriptEditorField extends StatefulWidget {
  const ScriptEditorField({
    super.key,
    required this.controller,
    required this.interpreter,
    required this.onInterpreterChanged,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ScriptInterpreter interpreter;
  final ValueChanged<ScriptInterpreter> onInterpreterChanged;
  final VoidCallback onChanged;

  @override
  State<ScriptEditorField> createState() => _ScriptEditorFieldState();
}

class _ScriptEditorFieldState extends State<ScriptEditorField> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    _scroll.dispose();
    super.dispose();
  }

  void _onText() {
    widget.onChanged();
    setState(() {}); // refresh gutter + line count
  }

  int get _lineCount => '\n'.allMatches(widget.controller.text).length + 1;

  Future<void> _pickInterpreter() async {
    final selected = await showAppMenuSheet<ScriptInterpreter>(
      context: context,
      title: AppLocalizations.of(context)!.entryInterpreterLabel,
      items: [
        for (final i in ScriptInterpreter.values)
          AppMenuItem(
            value: i,
            icon: Icons.terminal,
            label: i.wireName,
            trailing: i == widget.interpreter ? '✓' : null,
            trailingColor: AppColors.brandRed,
          ),
      ],
    );
    if (selected != null) widget.onInterpreterChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final lines = _lineCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l10n.entryScriptLabel,
              style: TextStyle(
                color: AppColors.onSurfaceMuted(brightness),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            InkWell(
              onTap: _pickInterpreter,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: AppSpacing.xxs,
                ),
                child: Row(
                  children: [
                    Text(
                      widget.interpreter.wireName,
                      style: TextStyle(
                        color: AppColors.onSurfaceMuted(brightness),
                        fontSize: 11.5,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    Icon(
                      Icons.expand_more,
                      size: 14,
                      color: AppColors.onSurfaceSubtle(brightness),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.innerGap),
        Container(
          decoration: BoxDecoration(
            color: AppColors.inputFill(brightness),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.cardBorder(brightness)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 150,
                child: SingleChildScrollView(
                  controller: _scroll,
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Gutter(lines: lines, brightness: brightness),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical: AppSpacing.innerGap,
                            ),
                            child: TextField(
                              controller: widget.controller,
                              maxLines: null,
                              expands: false,
                              keyboardType: TextInputType.multiline,
                              // The outer scroll view owns vertical scroll so
                              // the gutter tracks the code in lockstep.
                              scrollPhysics:
                                  const NeverScrollableScrollPhysics(),
                              style: TextStyle(
                                color: AppColors.onSurface(brightness),
                                fontSize: 12,
                                height: 1.5,
                                fontFamily: 'monospace',
                              ),
                              decoration: InputDecoration.collapsed(
                                hintText: l10n.entryScriptHint,
                                hintStyle: TextStyle(
                                  color: AppColors.onSurfaceSubtle(brightness),
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: AppColors.cardBorder(brightness)),
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.circle,
                        size: 8, color: AppColors.vaultViolet),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      l10n.entryScriptFooter(widget.interpreter.wireName, lines),
                      style: TextStyle(
                        color: AppColors.onSurfaceSubtle(brightness),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.innerGap),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.xxs),
              child: Icon(Icons.terminal, size: 12, color: AppColors.vaultViolet),
            ),
            const SizedBox(width: AppSpacing.innerGap),
            Expanded(
              child: Text(
                l10n.entryScriptExecOnlyNotice,
                style: TextStyle(
                  color: AppColors.onSurfaceSubtle(brightness),
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Gutter extends StatelessWidget {
  const _Gutter({required this.lines, required this.brightness});

  final int lines;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.innerGap),
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: AppColors.cardBorder(brightness)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 1; i <= lines; i++)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: Text(
                '$i',
                style: TextStyle(
                  color: AppColors.onSurfaceSubtle(brightness)
                      .withValues(alpha: 0.6),
                  fontSize: 12,
                  height: 1.5,
                  fontFamily: 'monospace',
                ),
              ),
            ),
        ],
      ),
    );
  }
}
