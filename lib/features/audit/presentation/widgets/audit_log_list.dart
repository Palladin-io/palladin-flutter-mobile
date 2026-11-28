import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/audit_log_entry.dart';
import 'audit_log_row.dart';

/// One list surface; the sliver variant keeps long audit feeds lazy.
class AuditLogList extends StatelessWidget {
  const AuditLogList({
    super.key,
    required this.entries,
    required this.agentNames,
  }) : _sliver = false;
  const AuditLogList.sliver({
    super.key,
    required this.entries,
    required this.agentNames,
  }) : _sliver = true;

  final List<AuditLogEntry> entries;
  final Map<String, String> agentNames;
  final bool _sliver;

  Widget _row(int index) => AuditLogRow(
    entry: entries[index],
    agentNames: agentNames,
    showDivider: index < entries.length - 1,
  );

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final decoration = BoxDecoration(
      color: AppColors.cardFill(brightness),
      border: Border.all(color: AppColors.cardBorder(brightness)),
      borderRadius: BorderRadius.circular(12),
    );
    if (_sliver) {
      return DecoratedSliver(
        decoration: decoration,
        sliver: SliverList.builder(
          itemCount: entries.length,
          itemBuilder: (_, index) => _row(index),
        ),
      );
    }
    return Container(
      decoration: decoration,
      child: Column(
        children: [for (var i = 0; i < entries.length; i++) _row(i)],
      ),
    );
  }
}
