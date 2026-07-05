import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../data/services/totp_service.dart';
import '../../domain/entities/totp_config.dart';
import 'entry_field_row.dart';

/// Live TOTP code with a countdown ring and copy action.
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
  });

  final TotpConfig config;

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

    final fontSize = widget.compact ? 13.0 : 16.0;
    return Row(
      children: [
        Icon(
          Icons.timer_outlined,
          size: 12,
          color: AppColors.onSurfaceSubtle(brightness),
        ),
        const SizedBox(width: AppSpacing.innerGap),
        Expanded(
          child: Text(
            _grouped(code.code),
            style: TextStyle(
              color: AppColors.onSurface(brightness),
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
              letterSpacing: 2,
            ),
          ),
        ),
        _CountdownRing(
          fraction: code.secondsRemaining / code.period,
          secondsRemaining: code.secondsRemaining,
          brightness: brightness,
        ),
        const SizedBox(width: AppSpacing.sm),
        EntrySmallIconButton(
          icon: Icons.content_copy,
          size: widget.compact ? 12 : 14,
          tooltip: l10n.vaultCopyValue,
          onPressed: () => widget.onCopy(code.code),
        ),
      ],
    );
  }
}

/// Small ring that depletes over the current time-step, with the seconds
/// remaining in the centre.
class _CountdownRing extends StatelessWidget {
  const _CountdownRing({
    required this.fraction,
    required this.secondsRemaining,
    required this.brightness,
  });

  final double fraction;
  final int secondsRemaining;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    // Turn red in the final stretch to hint the code is about to roll.
    final color = secondsRemaining <= 5
        ? AppColors.brandRed
        : AppColors.positiveAccent;
    return SizedBox(
      width: 22,
      height: 22,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              value: fraction.clamp(0.0, 1.0),
              strokeWidth: 2,
              backgroundColor: AppColors.onSurface(brightness)
                  .withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          Text(
            '$secondsRemaining',
            style: TextStyle(
              color: AppColors.onSurfaceSubtle(brightness),
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
