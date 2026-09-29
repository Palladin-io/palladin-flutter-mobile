import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Collapsed by default, with the current choice visible in its header.
class AppFormSection extends StatefulWidget {
  const AppFormSection({
    super.key,
    required this.label,
    required this.summary,
    required this.child,
    this.error,
  });

  final String label, summary;
  final String? error;
  final Widget child;

  @override
  State<AppFormSection> createState() => _AppFormSectionState();
}

class _AppFormSectionState extends State<AppFormSection> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant AppFormSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.error != null && widget.error != oldWidget.error) {
      _expanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.cardBorder(brightness)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: _expanded,
            label: '${widget.label}: ${widget.summary}',
            excludeSemantics: true,
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.section,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.onSurface(brightness),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.innerGap),
                    Expanded(
                      child: Text(
                        widget.summary,
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.onSurfaceMuted(brightness),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.innerGap),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: AppColors.onSurfaceSubtle(brightness),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Offstage(
            offstage: !_expanded,
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.section),
              child: widget.child,
            ),
          ),
          if (!_expanded && widget.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.innerGap),
              child: Text(
                widget.error!,
                style: const TextStyle(fontSize: 12, color: AppColors.brandRed),
              ),
            ),
        ],
      ),
    );
  }
}
