import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../grants/domain/entities/grant_method.dart';

/// Compact multi-select for grant methods (CVT-148/149) — the mobile counterpart of the web
/// methods dropdown. Replaces the tall checkbox-tile stack with toggleable chips in a [Wrap]
/// (same visual language as the access-policy segmented control), so the sheet stays small and
/// scales by wrapping as more methods are added. The `get` warning is surfaced compactly — only
/// when `get` is selected.
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
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final method in GrantMethod.values)
              _MethodChip(
                label: _label(l10n, method),
                selected: value.contains(method),
                requested: requested.contains(method),
                enabled: enabled,
                brightness: brightness,
                onTap: () => _toggle(method),
              ),
          ],
        ),
        // Warning Zone — framed like the Danger Zone but in amber. Animates open/closed (height +
        // fade) when the plaintext `get` method is toggled.
        _WarningZone(
          show: value.contains(GrantMethod.get),
          title: l10n.approvalMethodWarningZone,
          message: l10n.approvalMethodGetWarning,
          brightness: brightness,
        ),
      ],
    );
  }

  static String _label(AppLocalizations l10n, GrantMethod m) => switch (m) {
        GrantMethod.get => l10n.approvalMethodGetLabel,
        GrantMethod.exec => l10n.approvalMethodExecLabel,
        GrantMethod.inject => l10n.approvalMethodInjectLabel,
      };
}

/// Amber "Warning Zone" box, styled like the app's Danger Zone (rounded border + uppercase title)
/// but in the premium-amber tone. Animates its height and opacity open/closed via [AnimatedSize] +
/// [AnimatedOpacity] so it slides in when `get` is selected instead of popping.
class _WarningZone extends StatelessWidget {
  const _WarningZone({
    required this.show,
    required this.title,
    required this.message,
    required this.brightness,
  });

  final bool show;
  final String title;
  final String message;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.premium(brightness);
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: show ? 1 : 0,
        child: show
            ? Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: amber.withValues(alpha: 0.3)),
                    color: amber.withValues(alpha: 0.06),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: amber,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        message,
                        style: TextStyle(
                          color: AppColors.onSurfaceMuted(brightness),
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : const SizedBox(width: double.infinity),
      ),
    );
  }
}

/// A single toggleable method chip — selected state mirrors the segmented policy buttons (brand
/// fill when on). A small dot marks a method the agent requested.
class _MethodChip extends StatelessWidget {
  const _MethodChip({
    required this.label,
    required this.selected,
    required this.requested,
    required this.enabled,
    required this.brightness,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool requested;
  final bool enabled;
  final Brightness brightness;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.tealAccent.withValues(alpha: 0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.tealAccent : AppColors.cardBorder(brightness),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Icon(Icons.check, size: 14, color: AppColors.onSurface(brightness)),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: AppColors.onSurface(brightness),
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            if (requested) ...[
              const SizedBox(width: 6),
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.onSurfaceSubtle(brightness),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
