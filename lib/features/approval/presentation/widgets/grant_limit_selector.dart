import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../cubit/grant_approval_cubit.dart';

/// XOR limit picker for an approval — the owner chooses **either** a TTL
/// (expiry) **or** a use-count limit, never both. Emits a [GrantLimit] via
/// [onChanged].
///
/// TTL is offered as preset durations (1h / 24h / 7d / 30d). Use-count is
/// a free numeric field.
class GrantLimitSelector extends StatefulWidget {
  const GrantLimitSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final GrantLimit value;
  final ValueChanged<GrantLimit> onChanged;
  final bool enabled;

  @override
  State<GrantLimitSelector> createState() => _GrantLimitSelectorState();
}

enum _Mode { expiry, uses }

/// TTL preset durations offered for an expiry-limited grant.
const _ttlPresets = <(int, String)>[
  (1, '1h'),
  (24, '24h'),
  (24 * 7, '7d'),
  (24 * 30, '30d'),
];

class _GrantLimitSelectorState extends State<GrantLimitSelector> {
  late _Mode _mode;
  int _ttlHours = 24;
  final TextEditingController _usesController =
      TextEditingController(text: '10');

  @override
  void initState() {
    super.initState();
    _mode = widget.value is GrantUseLimit ? _Mode.uses : _Mode.expiry;
  }

  @override
  void dispose() {
    _usesController.dispose();
    super.dispose();
  }

  void _emit() {
    if (_mode == _Mode.expiry) {
      widget.onChanged(
        GrantExpiry(DateTime.now().add(Duration(hours: _ttlHours))),
      );
    } else {
      final uses = int.tryParse(_usesController.text.trim()) ?? 0;
      widget.onChanged(GrantUseLimit(uses));
    }
  }

  void _setMode(_Mode mode) {
    if (_mode == mode) return;
    setState(() => _mode = mode);
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Segmented toggle — expiry XOR uses.
        Row(
          children: [
            Expanded(
              child: _SegmentButton(
                label: l10n.approvalLimitExpiry,
                selected: _mode == _Mode.expiry,
                onTap: widget.enabled ? () => _setMode(_Mode.expiry) : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SegmentButton(
                label: l10n.approvalLimitUses,
                selected: _mode == _Mode.uses,
                onTap: widget.enabled ? () => _setMode(_Mode.uses) : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_mode == _Mode.expiry)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (hours, label) in _ttlPresets)
                _PresetChip(
                  label: label,
                  selected: _ttlHours == hours,
                  onTap: widget.enabled
                      ? () {
                          setState(() => _ttlHours = hours);
                          _emit();
                        }
                      : null,
                ),
            ],
          )
        else
          TextField(
            controller: _usesController,
            enabled: widget.enabled,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => _emit(),
            style: TextStyle(color: AppColors.onSurface(brightness)),
            decoration: InputDecoration(
              labelText: l10n.approvalLimitUsesLabel,
              labelStyle:
                  TextStyle(color: AppColors.onSurfaceSubtle(brightness)),
              filled: true,
              fillColor: AppColors.cardFill(brightness),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    BorderSide(color: AppColors.cardBorder(brightness)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.brandRed),
              ),
            ),
          ),
      ],
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? AppColors.brandRed.withValues(alpha: 0.15)
                : AppColors.cardFill(brightness),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? AppColors.brandRed
                  : AppColors.cardBorder(brightness),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? AppColors.brandRed
                  : AppColors.onSurfaceMuted(brightness),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.brandRed.withValues(alpha: 0.15)
                : AppColors.cardFill(brightness),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? AppColors.brandRed
                  : AppColors.cardBorder(brightness),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? AppColors.brandRed
                  : AppColors.onSurfaceMuted(brightness),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
