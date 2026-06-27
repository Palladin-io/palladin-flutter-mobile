import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/sheet_action_buttons.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/entities/audit_log_entry.dart';
import '../audit_log_format.dart';
import '../cubit/entry_logs_state.dart';

/// The selection returned by [EntryLogsFilterSheet] when the user applies
/// (or resets) the filters.
class EntryLogsFilter {
  const EntryLogsFilter({
    required this.eventTypes,
    this.agentId,
    this.fromDate,
    this.toDate,
  });

  final Set<AuditEventType> eventTypes;
  final String? agentId;
  final DateTime? fromDate;
  final DateTime? toDate;
}

/// Filter sheet for the entry Logs tab — the 8 entry-relevant event-type
/// checkboxes, an agent dropdown and a date range. Returns an
/// [EntryLogsFilter] on apply, an empty one on reset, or `null` on
/// dismiss.
class EntryLogsFilterSheet extends StatefulWidget {
  const EntryLogsFilterSheet({
    super.key,
    required this.initial,
    required this.agents,
  });

  final EntryLogsFilter initial;
  final List<AgentOption> agents;

  static Future<EntryLogsFilter?> show(
    BuildContext context, {
    required EntryLogsFilter initial,
    required List<AgentOption> agents,
  }) {
    return showModalBottomSheet<EntryLogsFilter>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EntryLogsFilterSheet(initial: initial, agents: agents),
    );
  }

  @override
  State<EntryLogsFilterSheet> createState() => _EntryLogsFilterSheetState();
}

class _EntryLogsFilterSheetState extends State<EntryLogsFilterSheet> {
  late Set<AuditEventType> _eventTypes;
  late String? _agentId;
  late DateTime? _from;
  late DateTime? _to;

  @override
  void initState() {
    super.initState();
    _eventTypes = Set.of(widget.initial.eventTypes);
    _agentId = widget.initial.agentId;
    _from = widget.initial.fromDate;
    _to = widget.initial.toDate;
  }

  void _toggle(AuditEventType type) {
    setState(() {
      if (!_eventTypes.remove(type)) _eventTypes.add(type);
    });
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _from : _to) ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = DateTime(picked.year, picked.month, picked.day);
      } else {
        // Include the whole selected day for the upper bound.
        _to = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
      }
    });
  }

  void _apply() {
    Navigator.of(context).pop(
      EntryLogsFilter(
        eventTypes: _eventTypes,
        agentId: _agentId,
        fromDate: _from,
        toDate: _to,
      ),
    );
  }

  void _reset() {
    Navigator.of(context).pop(const EntryLogsFilter(eventTypes: {}));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.modalBackground(brightness),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenH,
                AppSpacing.sm,
                AppSpacing.screenH,
                AppSpacing.xl,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.onSurfaceSubtle(brightness)
                            .withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.headerGap),
                  Text(
                    l10n.auditFilterTitle,
                    style: TextStyle(
                      color: AppColors.onSurface(brightness),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.section),
                  _SectionLabel(text: l10n.auditFilterEventTypes),
                  const SizedBox(height: AppSpacing.innerGap),
                  _EventTypeGrid(
                    selected: _eventTypes,
                    onToggle: _toggle,
                    brightness: brightness,
                  ),
                  const SizedBox(height: AppSpacing.section),
                  _SectionLabel(text: l10n.auditFilterAgent),
                  const SizedBox(height: AppSpacing.innerGap),
                  _AgentDropdown(
                    agents: widget.agents,
                    value: _agentId,
                    allLabel: l10n.auditFilterAllAgents,
                    onChanged: (id) => setState(() => _agentId = id),
                    brightness: brightness,
                  ),
                  const SizedBox(height: AppSpacing.section),
                  _SectionLabel(text: l10n.auditFilterDateRange),
                  const SizedBox(height: AppSpacing.innerGap),
                  Row(
                    children: [
                      Expanded(
                        child: _DateField(
                          label: l10n.auditFilterFrom,
                          value: _from,
                          onTap: () => _pickDate(isFrom: true),
                          onClear: _from == null
                              ? null
                              : () => setState(() => _from = null),
                          brightness: brightness,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.fieldGap),
                      Expanded(
                        child: _DateField(
                          label: l10n.auditFilterTo,
                          value: _to,
                          onTap: () => _pickDate(isFrom: false),
                          onClear: _to == null
                              ? null
                              : () => setState(() => _to = null),
                          brightness: brightness,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SheetActionButtons(
            onCancel: _reset,
            onConfirm: _apply,
            cancelLabel: l10n.auditFilterReset,
            confirmLabel: l10n.auditFilterApply,
            confirmColor: AppColors.brandRed,
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: AppColors.onSurfaceSubtle(Theme.of(context).brightness),
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
    );
  }
}

class _EventTypeGrid extends StatelessWidget {
  const _EventTypeGrid({
    required this.selected,
    required this.onToggle,
    required this.brightness,
  });

  final Set<AuditEventType> selected;
  final ValueChanged<AuditEventType> onToggle;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Wrap(
      runSpacing: AppSpacing.chipGap,
      children: [
        for (final type in AuditEventType.entryRelevant)
          FractionallySizedBox(
            widthFactor: 0.5,
            child: Padding(
              padding: const EdgeInsets.only(right: AppSpacing.chipGap),
              child: _EventTypeChip(
                label: auditEventLabel(l10n, type, type.wire),
                color: auditEventColor(type),
                selected: selected.contains(type),
                onTap: () => onToggle(type),
                brightness: brightness,
              ),
            ),
          ),
      ],
    );
  }
}

class _EventTypeChip extends StatelessWidget {
  const _EventTypeChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
    required this.brightness,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.14)
              : AppColors.cardSurface(brightness),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? color : AppColors.cardBorder(brightness),
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_box : Icons.check_box_outline_blank,
              size: 16,
              color: selected ? color : AppColors.onSurfaceSubtle(brightness),
            ),
            const SizedBox(width: AppSpacing.xs),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: AppColors.onSurface(brightness),
                  fontSize: 10,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentDropdown extends StatelessWidget {
  const _AgentDropdown({
    required this.agents,
    required this.value,
    required this.allLabel,
    required this.onChanged,
    required this.brightness,
  });

  final List<AgentOption> agents;
  final String? value;
  final String allLabel;
  final ValueChanged<String?> onChanged;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.cardSurface(brightness),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.inputBorder(brightness)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          isExpanded: true,
          value: value,
          dropdownColor: AppColors.modalBackground(brightness),
          icon: Icon(
            Icons.arrow_drop_down,
            color: AppColors.onSurfaceSubtle(brightness),
          ),
          style: TextStyle(
            color: AppColors.onSurface(brightness),
            fontSize: 12,
          ),
          items: [
            DropdownMenuItem<String?>(value: null, child: Text(allLabel)),
            for (final a in agents)
              DropdownMenuItem<String?>(value: a.id, child: Text(a.name)),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
    required this.onClear,
    required this.brightness,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final display = value == null
        ? label
        : auditTimestamp(value!).split(' ').first;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.cardPadding,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: AppColors.cardSurface(brightness),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.inputBorder(brightness)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 14,
              color: AppColors.onSurfaceSubtle(brightness),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                display,
                style: TextStyle(
                  color: value == null
                      ? AppColors.onSurfaceSubtle(brightness)
                      : AppColors.onSurface(brightness),
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onClear != null)
              GestureDetector(
                onTap: onClear,
                child: Icon(
                  Icons.close,
                  size: 14,
                  color: AppColors.onSurfaceSubtle(brightness),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
