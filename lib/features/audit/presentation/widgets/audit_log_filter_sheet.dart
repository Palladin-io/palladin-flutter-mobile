import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/multi_select_dropdown.dart';
import '../../../../core/widgets/sheet_action_buttons.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/entities/audit_log_entry.dart';
import '../audit_filters.dart';
import '../audit_log_format.dart';

/// Shortened id (first 8 chars) for disambiguating unnamed options — mirrors
/// the `_shortId` fallback used by `AuditLogState.vaultOptions`.
String _shortId(String id) => id.length <= 15
    ? id
    : '${id.substring(0, 8)}…${id.substring(id.length - 6)}';

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
                  MultiSelectDropdown(
                    label: l10n.auditFilterEventTypes,
                    placeholder: l10n.auditFilterAllEventTypes,
                    options: [
                      for (final g in widget.groups)
                        (value: g.name, label: auditGroupLabel(l10n, g)),
                    ],
                    selected: _groups.map((g) => g.name).toSet(),
                    onChanged: (values) => setState(() {
                      _groups = widget.groups
                          .where((g) => values.contains(g.name))
                          .toSet();
                    }),
                  ),
                  if (vaults != null && vaults.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.section),
                    MultiSelectDropdown(
                      label: l10n.auditFilterVault,
                      placeholder: l10n.auditFilterAllVaults,
                      options: [
                        for (final v in vaults) (value: v.id, label: v.name),
                      ],
                      selected: _vaultIds,
                      onChanged: (values) => setState(() => _vaultIds = values),
                    ),
                  ],
                  if (widget.users.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.section),
                    MultiSelectDropdown(
                      label: l10n.auditFilterUser,
                      placeholder: l10n.auditFilterAllUsers,
                      options: [
                        for (final u in widget.users)
                          (
                            value: u.id,
                            // Disambiguate unnamed actors with a short id so
                            // multiple unknown users aren't identical entries.
                            label:
                                u.name ??
                                l10n.auditUserUnknownShort(_shortId(u.id)),
                          ),
                      ],
                      selected: _userIds,
                      onChanged: (values) => setState(() => _userIds = values),
                    ),
                  ],
                  if (widget.agents.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.section),
                    MultiSelectDropdown(
                      label: l10n.auditFilterAgent,
                      placeholder: l10n.auditFilterAllAgents,
                      options: [
                        for (final a in widget.agents)
                          (value: a.id, label: a.name),
                      ],
                      selected: _agentIds,
                      onChanged: (values) => setState(() => _agentIds = values),
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
