import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../grants/domain/entities/grant_method.dart';

/// Checkbox group choosing which methods a grant permits (CVT-148/149) — the
/// mobile counterpart of the web `GrantMethodsField`. At least one must be
/// selected. `get` carries an explicit warning because it returns the plaintext
/// into the agent's context (and, for a hosted LLM, off the device).
class GrantMethodsSelector extends StatelessWidget {
  const GrantMethodsSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.requested = const [],
    this.enabled = true,
  });

  final List<GrantMethod> value;
  final List<GrantMethod> requested;
  final bool enabled;
  final ValueChanged<List<GrantMethod>> onChanged;

  void _toggle(GrantMethod method) {
    final next = List<GrantMethod>.from(value);
    if (next.contains(method)) {
      next.remove(method);
    } else {
      next.add(method);
    }
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final method in GrantMethod.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _MethodTile(
              method: method,
              label: _label(l10n, method),
              description: _description(l10n, method),
              warning: method == GrantMethod.get ? l10n.approvalMethodGetWarning : null,
              checked: value.contains(method),
              requested: requested.contains(method),
              enabled: enabled,
              brightness: brightness,
              onTap: () => _toggle(method),
            ),
          ),
      ],
    );
  }

  static String _label(AppLocalizations l10n, GrantMethod m) => switch (m) {
        GrantMethod.get => l10n.approvalMethodGetLabel,
        GrantMethod.exec => l10n.approvalMethodExecLabel,
        GrantMethod.inject => l10n.approvalMethodInjectLabel,
      };

  static String _description(AppLocalizations l10n, GrantMethod m) => switch (m) {
        GrantMethod.get => l10n.approvalMethodGetDesc,
        GrantMethod.exec => l10n.approvalMethodExecDesc,
        GrantMethod.inject => l10n.approvalMethodInjectDesc,
      };
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({
    required this.method,
    required this.label,
    required this.description,
    required this.warning,
    required this.checked,
    required this.requested,
    required this.enabled,
    required this.brightness,
    required this.onTap,
  });

  final GrantMethod method;
  final String label;
  final String description;
  final String? warning;
  final bool checked;
  final bool requested;
  final bool enabled;
  final Brightness brightness;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.cardBorder(brightness)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: checked,
              onChanged: enabled ? (_) => onTap() : null,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: AppColors.onSurface(brightness),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (requested) ...[
                        const SizedBox(width: 6),
                        Text(
                          l10n.approvalMethodRequested,
                          style: TextStyle(
                            color: AppColors.onSurfaceSubtle(brightness),
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(
                      color: AppColors.onSurfaceMuted(brightness),
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                  if (warning != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      warning!,
                      style: TextStyle(
                        color: AppColors.premium(brightness),
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
