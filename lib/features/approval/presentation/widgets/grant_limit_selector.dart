import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/warning_zone.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../onboarding/presentation/widgets/onboarding_text_field.dart';
import '../cubit/grant_approval_cubit.dart';

/// Access-policy picker for an approval — the owner chooses a TTL (expiry), a
/// use-count limit, or lifetime (unlimited), mirroring the web approve dialog.
/// Emits a [GrantLimit] via [onChanged].
///
/// TTL is offered as preset durations (1h / 24h / 7d / 30d). Use-count is a
/// free numeric field. Lifetime takes no field (a short hint instead).
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

enum _Mode { expiry, uses, lifetime }

class _GrantLimitSelectorState extends State<GrantLimitSelector> {
  late _Mode _mode;
  late DateTime _expiresOn;
  final TextEditingController _usesController =
      TextEditingController(text: '1');
  final TextEditingController _dateController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final value = widget.value;
    _mode = switch (value) {
      GrantUseLimit() => _Mode.uses,
      GrantLifetime() => _Mode.lifetime,
      GrantExpiry() => _Mode.expiry,
    };
    _expiresOn = value is GrantExpiry
        ? value.expiresAt
        : DateTime.now().add(const Duration(days: 1));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Set the initial label here (not in initState) so MaterialLocalizations
    // is available, and refresh on locale change.
    _syncDateText();
  }

  @override
  void dispose() {
    _usesController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  /// Renders the picked instant into the read-only expiry field. Called from
  /// [didChangeDependencies] (initial / locale change) and after each pick —
  /// never from `build()`, which would notify the controller's listeners
  /// mid-build (`setState during build`).
  void _syncDateText() {
    final ml = MaterialLocalizations.of(context);
    _dateController.text =
        '${ml.formatMediumDate(_expiresOn)}, '
        '${ml.formatTimeOfDay(TimeOfDay.fromDateTime(_expiresOn))}';
  }

  void _emit() {
    switch (_mode) {
      case _Mode.expiry:
        widget.onChanged(GrantExpiry(_expiresOn));
      case _Mode.uses:
        final uses = int.tryParse(_usesController.text.trim()) ?? 1;
        widget.onChanged(GrantUseLimit(uses));
      case _Mode.lifetime:
        widget.onChanged(const GrantLifetime());
    }
  }

  void _setMode(_Mode mode) {
    if (_mode == mode) return;
    setState(() => _mode = mode);
    _emit();
  }

  /// Themes the date/time picker as a clean white surface with a red (brand)
  /// selected date — instead of the app's cream/yellow surface and primary,
  /// which looked beige inside the picker. `onBrandRed` is the white constant.
  Widget _pickerTheme(BuildContext context, Widget? child) {
    final base = Theme.of(context);
    const white = AppColors.onBrandRed;
    const dark = AppColors.darkBackground;
    return Theme(
      data: base.copyWith(
        colorScheme: base.colorScheme.copyWith(
          primary: AppColors.brandRed,
          onPrimary: white,
          surface: white,
          onSurface: dark,
        ),
        datePickerTheme: const DatePickerThemeData(
          backgroundColor: white,
          headerBackgroundColor: white,
          headerForegroundColor: dark,
        ),
        timePickerTheme: const TimePickerThemeData(
          backgroundColor: white,
        ),
      ),
      child: child!,
    );
  }

  /// Picks the expiry day, then the time-of-day, combining both into the exact
  /// expiry instant.
  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _expiresOn,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5, now.month, now.day),
      builder: _pickerTheme,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_expiresOn),
      builder: _pickerTheme,
    );
    if (!mounted) return;
    final picked = DateTime(
      date.year,
      date.month,
      date.day,
      time?.hour ?? _expiresOn.hour,
      time?.minute ?? _expiresOn.minute,
    );
    setState(() => _expiresOn = picked);
    _syncDateText();
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Segmented toggle — Time / Uses / Lifetime (web approve options).
        Row(
          children: [
            Expanded(
              child: _SegmentButton(
                label: l10n.approvalPolicyTime,
                selected: _mode == _Mode.expiry,
                onTap: widget.enabled ? () => _setMode(_Mode.expiry) : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SegmentButton(
                label: l10n.approvalPolicyUses,
                selected: _mode == _Mode.uses,
                onTap: widget.enabled ? () => _setMode(_Mode.uses) : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SegmentButton(
                label: l10n.approvalPolicyLifetime,
                selected: _mode == _Mode.lifetime,
                onTap: widget.enabled ? () => _setMode(_Mode.lifetime) : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Lifetime has no field — show the "never expires" caveat in the shared Warning Zone
        // (consistent with the `get` method warning). Time / Uses keep the fixed-height field slot.
        if (_mode == _Mode.lifetime)
          WarningZone(
            title: l10n.approvalMethodWarningZone,
            message: l10n.approvalLifetimeHint,
          )
        else
        SizedBox(
          height: 72,
          child: switch (_mode) {
            _Mode.expiry => OnboardingTextField(
                controller: _dateController,
                label: l10n.approvalExpiresOnLabel,
                readOnly: true,
                enabled: widget.enabled,
                onTap: widget.enabled ? _pickDateTime : null,
                suffixIcon: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(
                    Icons.calendar_today_outlined,
                    size: 18,
                    color: AppColors.onSurfaceSubtle(brightness),
                  ),
                ),
              ),
            _Mode.uses => OnboardingTextField(
                controller: _usesController,
                label: l10n.approvalLimitUsesLabel,
                enabled: widget.enabled,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => _emit(),
              ),
            // Handled above by the Warning Zone; unreachable here.
            _Mode.lifetime => const SizedBox.shrink(),
          },
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
