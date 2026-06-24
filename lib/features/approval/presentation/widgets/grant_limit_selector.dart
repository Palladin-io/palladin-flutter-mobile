import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
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

/// Quick-pick durations offered for a time-limited grant — mirrors the web
/// approve dialog (minutes then hours), laid out 4-per-row.
const List<int> _quickMinutes = [5, 15, 30];
const List<int> _quickHours = [1, 2, 6, 12, 24];

class _GrantLimitSelectorState extends State<GrantLimitSelector> {
  late _Mode _mode;
  late DateTime _expiresOn;

  /// Currently selected quick-pick duration in minutes, or `null` when the
  /// expiry was set via the custom date/time picker.
  int? _quickMinutesSelected;
  final TextEditingController _usesController = TextEditingController(
    text: '1',
  );
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
    // The sheet's default expiry is 24h → pre-highlight that quick chip.
    _quickMinutesSelected = 24 * 60;
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

  /// Quick-pick: set the expiry to `now + minutes` and highlight that chip.
  void _setQuick(int minutes) {
    setState(() {
      _quickMinutesSelected = minutes;
      _expiresOn = DateTime.now().add(Duration(minutes: minutes));
    });
    _syncDateText();
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
        // Fully theme the time picker — without this the dial face and the
        // hour/minute fields inherit dark colours (navy-on-navy, unreadable).
        timePickerTheme: TimePickerThemeData(
          backgroundColor: white,
          dialBackgroundColor: AppColors.pickerDialFill,
          dialHandColor: AppColors.brandRed,
          dialTextColor: WidgetStateColor.resolveWith(
            (s) => s.contains(WidgetState.selected) ? white : dark,
          ),
          hourMinuteColor: WidgetStateColor.resolveWith(
            (s) => s.contains(WidgetState.selected)
                ? AppColors.brandRed.withValues(alpha: 0.15)
                : AppColors.pickerDialFill,
          ),
          hourMinuteTextColor: WidgetStateColor.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AppColors.brandRed : dark,
          ),
          dayPeriodColor: WidgetStateColor.resolveWith(
            (s) => s.contains(WidgetState.selected)
                ? AppColors.brandRed.withValues(alpha: 0.15)
                : AppColors.pickerDialFill,
          ),
          dayPeriodTextColor: WidgetStateColor.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AppColors.brandRed : dark,
          ),
          entryModeIconColor: dark,
          helpTextStyle: const TextStyle(color: dark),
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
    // A custom pick clears any quick-chip highlight.
    setState(() {
      _expiresOn = picked;
      _quickMinutesSelected = null;
    });
    _syncDateText();
    _emit();
  }

  /// Time-mode body — quick-pick duration chips (4 per row) + a full-width
  /// Custom chip that opens the date/time picker + the chosen-expiry summary.
  /// Mirrors the web approve dialog's quick intervals.
  Widget _buildExpiryFields(AppLocalizations l10n, Brightness brightness) {
    final quick = <({int minutes, String label})>[
      for (final m in _quickMinutes) (minutes: m, label: l10n.approvalQuickMinutes(m)),
      for (final h in _quickHours) (minutes: h * 60, label: l10n.approvalQuickHours(h)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < quick.length; i += 4) ...[
          if (i > 0) const SizedBox(height: AppSpacing.innerGap),
          Row(
            children: [
              for (var j = i; j < i + 4; j++) ...[
                if (j > i) const SizedBox(width: AppSpacing.innerGap),
                Expanded(
                  child: j < quick.length
                      ? _QuickChip(
                          label: quick[j].label,
                          selected: _quickMinutesSelected == quick[j].minutes,
                          onTap: widget.enabled
                              ? () => _setQuick(quick[j].minutes)
                              : null,
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.innerGap),
        _QuickChip(
          label: l10n.approvalQuickCustom,
          icon: Icons.event_outlined,
          selected: _quickMinutesSelected == null,
          onTap: widget.enabled ? _pickDateTime : null,
        ),
        const SizedBox(height: AppSpacing.fieldGap),
        _ExpirySummary(
          relative: _expiresInLabel(l10n, _expiresOn),
          absolute: _dateController.text,
        ),
      ],
    );
  }

  /// Relative "Expires in Xm/h/d/mo" for the summary — mirrors the web
  /// `formatExpiresInLong` (rounds, so now+24h reads "24h", not "23h").
  String _expiresInLabel(AppLocalizations l10n, DateTime expiresOn) {
    final minutes = (expiresOn.difference(DateTime.now()).inSeconds / 60).round();
    if (minutes <= 0) return l10n.approvalExpiredAlready;
    if (minutes < 60) return l10n.approvalExpiresInMinutes(minutes);
    final hours = (minutes / 60).round();
    if (hours < 24) return l10n.approvalExpiresInHours(hours);
    final days = (hours / 24).round();
    if (days < 30) return l10n.approvalExpiresInDays(days);
    return l10n.approvalExpiresInMonths((days / 30).round());
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
            const SizedBox(width: AppSpacing.innerGap),
            Expanded(
              child: _SegmentButton(
                label: l10n.approvalPolicyUses,
                selected: _mode == _Mode.uses,
                onTap: widget.enabled ? () => _setMode(_Mode.uses) : null,
              ),
            ),
            const SizedBox(width: AppSpacing.innerGap),
            Expanded(
              child: _SegmentButton(
                label: l10n.approvalPolicyLifetime,
                selected: _mode == _Mode.lifetime,
                onTap: widget.enabled ? () => _setMode(_Mode.lifetime) : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.fieldGap),
        // The field below sizes naturally — no fixed-height slot (which caused an
        // 8px overflow). Time / Uses are the same label+field height; Lifetime has
        // no field and instead shows the "never expires" caveat in the shared
        // Warning Zone (consistent with the `get` method warning). AnimatedSize
        // smooths the height change (and the sheet around it) when switching to
        // / from the taller lifetime warning instead of snapping.
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: switch (_mode) {
            _Mode.expiry => _buildExpiryFields(l10n, brightness),
            _Mode.uses => OnboardingTextField(
              controller: _usesController,
              label: l10n.approvalLimitUsesLabel,
              enabled: widget.enabled,
              feedbackReserveSpace: false,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => _emit(),
            ),
            _Mode.lifetime => WarningZone(
              title: l10n.approvalMethodWarningZone,
              message: l10n.approvalLifetimeHint,
            ),
          },
        ),
      ],
    );
  }
}

/// Quick-pick duration chip (and the Custom chip) for the Time policy. Selected
/// chips get the brand-red tinted fill; an optional leading [icon] marks the
/// Custom chip.
class _QuickChip extends StatelessWidget {
  const _QuickChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final fg = selected
        ? AppColors.brandRed
        : AppColors.onSurfaceMuted(brightness);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.innerGap),
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: fg),
                const SizedBox(width: AppSpacing.xs),
              ],
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chosen-expiry summary box — relative distance ("Expires in 24h", teal) on
/// the left, the absolute timestamp muted on the right, so the owner sees both
/// how long and exactly when access ends. Mirrors the web approve summary.
class _ExpirySummary extends StatelessWidget {
  const _ExpirySummary({required this.relative, required this.absolute});

  final String relative;
  final String absolute;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.innerGap,
      ),
      decoration: BoxDecoration(
        color: AppColors.inputFill(brightness),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.inputBorder(brightness)),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule, size: 14, color: AppColors.tealAccent),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              relative,
              style: TextStyle(
                color: AppColors.onSurface(brightness),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.innerGap),
          Text(
            absolute,
            style: TextStyle(
              color: AppColors.onSurfaceSubtle(brightness),
              fontSize: 11,
            ),
          ),
        ],
      ),
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
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.innerGap),
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
