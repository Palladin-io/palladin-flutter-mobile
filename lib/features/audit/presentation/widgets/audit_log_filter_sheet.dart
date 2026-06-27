import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/sheet_action_buttons.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/entities/audit_log_entry.dart';
import '../audit_filters.dart';
import '../audit_log_format.dart';

/// The single filter sheet for the vault- and org-scoped Logs surfaces:
/// event-type group selection, an agent dropdown, an optional vault dropdown
/// (org scope) and a date range. Returns an [AuditLogFilter] on apply, an
/// empty one on reset, or `null` on dismiss.
class AuditLogFilterSheet extends StatefulWidget {
  const AuditLogFilterSheet({
    super.key,
    required this.initial,
    required this.groups,
    required this.agents,
    required this.users,
    this.vaults,
  });

  final AuditLogFilter initial;

  /// Event-type groups offered for selection (vault-relevant vs org-wide).
  final List<AuditEventGroup> groups;

  final List<AgentOption> agents;

  /// Human actors (users) present in the feed — for the "performed by" filter.
  final List<UserOption> users;

  /// Vault options for the org-scoped screen; `null` hides the vault dropdown
  /// (vault-scoped tab).
  final List<VaultOption>? vaults;

  static Future<AuditLogFilter?> show(
    BuildContext context, {
    required AuditLogFilter initial,
    required List<AuditEventGroup> groups,
    required List<AgentOption> agents,
    required List<UserOption> users,
    List<VaultOption>? vaults,
  }) {
    return showModalBottomSheet<AuditLogFilter>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AuditLogFilterSheet(
        initial: initial,
        groups: groups,
        agents: agents,
        users: users,
        vaults: vaults,
      ),
    );
  }

  @override
  State<AuditLogFilterSheet> createState() => _AuditLogFilterSheetState();
}

class _AuditLogFilterSheetState extends State<AuditLogFilterSheet> {
  late Set<AuditEventGroup> _groups;
  late Set<String> _agentIds;
  late Set<String> _userIds;
  late Set<String> _vaultIds;
  late DateTime? _from;
  late DateTime? _to;

  @override
  void initState() {
    super.initState();
    _groups = Set.of(widget.initial.groups);
    _agentIds = Set.of(widget.initial.agentIds);
    _userIds = Set.of(widget.initial.userIds);
    _vaultIds = Set.of(widget.initial.vaultIds);
    _from = widget.initial.fromDate;
    _to = widget.initial.toDate;
  }

  void _toggleGroup(AuditEventGroup group) {
    setState(() {
      if (!_groups.remove(group)) _groups.add(group);
    });
  }

  void _toggleId(Set<String> set, String id) {
    setState(() {
      if (!set.remove(id)) set.add(id);
    });
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final firstDate = isFrom
        ? DateTime(now.year - 5)
        : (_from ?? DateTime(now.year - 5));
    final lastDate = isFrom
        ? (_to ?? DateTime(now.year + 1))
        : DateTime(now.year + 1);
    final initial = (isFrom ? _from : _to) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(firstDate)
          ? firstDate
          : (initial.isAfter(lastDate) ? lastDate : initial),
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = DateTime(picked.year, picked.month, picked.day);
      } else {
        _to = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
      }
    });
  }

  void _apply() {
    Navigator.of(context).pop(
      AuditLogFilter(
        groups: _groups,
        agentIds: _agentIds,
        userIds: _userIds,
        vaultIds: _vaultIds,
        fromDate: _from,
        toDate: _to,
      ),
    );
  }

  void _reset() => Navigator.of(context).pop(const AuditLogFilter());

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final vaults = widget.vaults;

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
                        color: AppColors.onSurfaceSubtle(
                          brightness,
                        ).withValues(alpha: 0.4),
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
                  _GroupSelector(
                    groups: widget.groups,
                    selected: _groups,
                    onToggle: _toggleGroup,
                    brightness: brightness,
                  ),
                  if (vaults != null && vaults.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.section),
                    _SectionLabel(text: l10n.auditFilterVault),
                    const SizedBox(height: AppSpacing.innerGap),
                    _OptionChips(
                      options: [
                        for (final v in vaults) (id: v.id, label: v.name),
                      ],
                      selected: _vaultIds,
                      onToggle: (id) => _toggleId(_vaultIds, id),
                      brightness: brightness,
                    ),
                  ],
                  if (widget.users.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.section),
                    _SectionLabel(text: l10n.auditFilterUser),
                    const SizedBox(height: AppSpacing.innerGap),
                    _OptionChips(
                      options: [
                        for (final u in widget.users)
                          (id: u.id, label: u.name ?? l10n.auditUserUnknown),
                      ],
                      selected: _userIds,
                      onToggle: (id) => _toggleId(_userIds, id),
                      brightness: brightness,
                    ),
                  ],
                  if (widget.agents.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.section),
                    _SectionLabel(text: l10n.auditFilterAgent),
                    const SizedBox(height: AppSpacing.innerGap),
                    _OptionChips(
                      options: [
                        for (final a in widget.agents)
                          (id: a.id, label: a.name),
                      ],
                      selected: _agentIds,
                      onToggle: (id) => _toggleId(_agentIds, id),
                      brightness: brightness,
                    ),
                  ],
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

/// Multi-select chips for the event-type [groups]. An empty selection means
/// "all event types".
class _GroupSelector extends StatelessWidget {
  const _GroupSelector({
    required this.groups,
    required this.selected,
    required this.onToggle,
    required this.brightness,
  });

  final List<AuditEventGroup> groups;
  final Set<AuditEventGroup> selected;
  final ValueChanged<AuditEventGroup> onToggle;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Wrap(
      spacing: AppSpacing.chipGap,
      runSpacing: AppSpacing.chipGap,
      children: [
        for (final group in groups)
          _GroupChip(
            label: auditGroupLabel(l10n, group),
            color: auditGroupColor(group),
            selected: selected.contains(group),
            onTap: () => onToggle(group),
            brightness: brightness,
          ),
      ],
    );
  }
}

class _GroupChip extends StatelessWidget {
  const _GroupChip({
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
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.16)
              : AppColors.cardSurface(brightness),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? color : AppColors.cardBorder(brightness),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? Icons.check : Icons.add,
              size: 14,
              color: selected ? color : AppColors.onSurfaceSubtle(brightness),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              label,
              style: TextStyle(
                color: selected ? color : AppColors.onSurface(brightness),
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Multi-select toggle chips for an id+label option list (agents / users /
/// vaults). An empty [selected] set means "all". Mirrors the group selector;
/// a neutral accent keeps it distinct from the colour-coded event groups.
class _OptionChips extends StatelessWidget {
  const _OptionChips({
    required this.options,
    required this.selected,
    required this.onToggle,
    required this.brightness,
  });

  final List<({String id, String label})> options;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.chipGap,
      runSpacing: AppSpacing.chipGap,
      children: [
        for (final o in options)
          _GroupChip(
            label: o.label,
            color: AppColors.vaultBlue,
            selected: selected.contains(o.id),
            onTap: () => onToggle(o.id),
            brightness: brightness,
          ),
      ],
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
        : auditDate(value!, Localizations.localeOf(context).toString());
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
