import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../data/services/totp_service.dart';
import '../../domain/entities/totp_config.dart';
import 'entry_field_row.dart';

/// Live TOTP code using the same typography and copy action as other fields.
///
/// Recomputes once a second from [config] via a stateless [TotpService].
/// The secret never leaves memory — only the ephemeral 6/8-digit code is
/// shown, grouped for readability, and copied on demand.
class TotpDisplay extends StatefulWidget {
  const TotpDisplay({
    super.key,
    required this.config,
    required this.onCopy,
    this.compact = false,
    this.label,
  });

  final TotpConfig config;
  final String? label;

  TotpDisplay labeled(String text) => TotpDisplay(
    config: config,
    onCopy: onCopy,
    compact: compact,
    label: text,
  );

  /// Copies the current code — receives the raw (ungrouped) digits.
  final ValueChanged<String> onCopy;

  /// Denser layout used inside the entries-tab reveal panel.
  final bool compact;

  @override
  State<TotpDisplay> createState() => _TotpDisplayState();
}

class _TotpDisplayState extends State<TotpDisplay> {
  static const _service = TotpService();

  Timer? _timer;
  TotpCode? _code;
  bool _invalid = false;

  @override
  void initState() {
    super.initState();
    _recompute();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _recompute());
  }

  @override
  void didUpdateWidget(TotpDisplay old) {
    super.didUpdateWidget(old);
    if (old.config.secret != widget.config.secret) _recompute();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _recompute() {
    try {
      final code = _service.generate(widget.config);
      if (!mounted) return;
      setState(() {
        _code = code;
        _invalid = false;
      });
    } on FormatException {
      if (!mounted) return;
      setState(() => _invalid = true);
    }
  }

  /// Groups the code into two halves for readability: `287 082`.
  String _grouped(String code) {
    final half = code.length ~/ 2;
    if (half == 0) return code;
    return '${code.substring(0, half)} ${code.substring(half)}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    if (_invalid) {
      return Text(
        l10n.totpInvalidConfigured,
        style: const TextStyle(color: AppColors.brandRed, fontSize: 12),
      );
    }

    final code = _code;
    if (code == null) return const SizedBox.shrink();

    final field = EntryFieldRow(
      icon: Icons.key_outlined,
      value: _grouped(code.code),
      isMasked: false,
      revealed: true,
      onToggleReveal: null,
      onCopy: () => widget.onCopy(code.code),
      valueFontSize: 14,
      actionIconSize: 18,
      beforeActions: _Countdown(code: code),
    );
    if (widget.label != null) return field.labeled(widget.label!);
    return Row(
      children: [
        Expanded(
          child: Text(
            _grouped(code.code),
            style: TextStyle(
              color: AppColors.onSurface(brightness),
              fontSize: 14,
            ),
          ),
        ),
        _Countdown(code: code),
        const SizedBox(width: AppSpacing.xs),
        EntrySmallIconButton(
          icon: Icons.content_copy,
          size: 18,
          tooltip: l10n.vaultCopyValue,
          onPressed: () => widget.onCopy(code.code),
        ),
      ],
    );
  }
}

class _Countdown extends StatelessWidget {
  const _Countdown({required this.code});

  final TotpCode code;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return SizedBox.square(
      dimension: 24,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CircularProgressIndicator(
              value: 1 - code.elapsedFraction,
              strokeWidth: 2,
              backgroundColor: AppColors.cardBorder(brightness),
              color: code.secondsRemaining <= 5
                  ? AppColors.brandRed
                  : AppColors.positiveAccent,
            ),
          ),
          Text(
            '${code.secondsRemaining}',
            style: TextStyle(
              fontSize: 10,
              color: AppColors.onSurfaceSubtle(brightness),
            ),
          ),
        ],
      ),
    );
  }
}
