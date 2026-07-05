import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/secure_clipboard.dart';
import '../../../../core/widgets/app_menu_sheet.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../data/services/totp_service.dart';
import '../../domain/entities/custom_field.dart';
import '../../domain/entities/totp_config.dart';
import 'entry_form_widgets.dart';
import 'totp_display.dart';
import 'totp_setup_sheet.dart';

/// The dedicated "Two-factor authentication" section (mockup parity).
///
/// Owns the entry's TOTP custom fields. Empty state is a dashed
/// call-to-action; a configured secret renders as a card with the live
/// code, countdown ring, copy, and a "⋯" bottom-sheet menu (copy /
/// replace / remove). The secret itself is never shown. Scanning a QR code
/// happens only inside [TotpSetupSheet]. Data-wise these are ordinary
/// `totp` custom fields — the [CustomFieldsEditor] deliberately excludes
/// them so there is a single home for 2FA.
class TotpSection extends StatefulWidget {
  const TotpSection({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  final List<CustomField> initial;
  final ValueChanged<List<CustomField>> onChanged;

  @override
  State<TotpSection> createState() => _TotpSectionState();
}

class _TotpSectionState extends State<TotpSection> {
  static const _service = TotpService();

  late final List<CustomField> _fields =
      widget.initial.where((f) => f.type == CustomFieldType.totp).toList();

  void _emit() => widget.onChanged(List.unmodifiable(_fields));

  Future<void> _add() async {
    final config = await TotpSetupSheet.show(context);
    if (config == null || !mounted) return;
    setState(() {
      _fields.add(CustomField.totpField(
        id: CustomField.newId(),
        label: _labelFor(config),
        config: config,
      ));
    });
    _emit();
  }

  Future<void> _replace(CustomField field) async {
    final config =
        await TotpSetupSheet.show(context, initial: field.totp);
    if (config == null || !mounted) return;
    setState(() {
      final index = _fields.indexOf(field);
      if (index < 0) return;
      _fields[index] = CustomField.totpField(
        id: field.id,
        label: field.label.isNotEmpty ? field.label : _labelFor(config),
        config: config,
      );
    });
    _emit();
  }

  void _remove(CustomField field) {
    setState(() => _fields.remove(field));
    _emit();
  }

  Future<void> _copyCode(TotpConfig config) async {
    try {
      final code = _service.generate(config).code;
      await SecureClipboard.copy(code);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context)!.totpCodeCopied),
          duration: const Duration(seconds: 1),
        ));
    } on FormatException {
      // Invalid secret — nothing to copy.
    }
  }

  Future<void> _openMenu(CustomField field) async {
    final l10n = AppLocalizations.of(context)!;
    final config = field.totp;
    final action = await showAppMenuSheet<_TotpAction>(
      context: context,
      items: [
        if (config != null)
          AppMenuItem(
            value: _TotpAction.copy,
            icon: Icons.content_copy,
            label: l10n.totpCopyCode,
          ),
        AppMenuItem(
          value: _TotpAction.replace,
          icon: Icons.refresh,
          label: l10n.totpReplaceSecret,
        ),
        AppMenuItem(
          value: _TotpAction.remove,
          icon: Icons.delete_outline,
          label: l10n.totpRemove,
          danger: true,
          dividerBefore: true,
        ),
      ],
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _TotpAction.copy:
        if (config != null) await _copyCode(config);
      case _TotpAction.replace:
        await _replace(field);
      case _TotpAction.remove:
        _remove(field);
    }
  }

  String _labelFor(TotpConfig config) =>
      (config.issuer?.isNotEmpty ?? false)
          ? config.issuer!
          : (config.account?.isNotEmpty ?? false)
              ? config.account!
              : '2FA';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EntrySectionHeader(label: l10n.totpSectionTitle),
        const SizedBox(height: AppSpacing.innerGap),
        if (_fields.isEmpty)
          _TotpEmpty(onAdd: _add, l10n: l10n)
        else
          for (var i = 0; i < _fields.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.cardGap),
            _TotpCard(
              field: _fields[i],
              onCopy: _copyCode,
              onMenu: () => _openMenu(_fields[i]),
              l10n: l10n,
            ),
          ],
      ],
    );
  }
}

enum _TotpAction { copy, replace, remove }

class _TotpEmpty extends StatelessWidget {
  const _TotpEmpty({required this.onAdd, required this.l10n});

  final VoidCallback onAdd;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return InkWell(
      onTap: onAdd,
      borderRadius: BorderRadius.circular(14),
      child: DottedBorderBox(
        brightness: brightness,
        child: Row(
          children: [
            Icon(
              Icons.shield_outlined,
              size: 20,
              color: AppColors.onSurfaceSubtle(brightness),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                l10n.totpEmptyHint,
                style: TextStyle(
                  color: AppColors.onSurfaceSubtle(brightness),
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Text(
              l10n.totpAdd,
              style: const TextStyle(
                color: AppColors.brandRed,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TotpCard extends StatelessWidget {
  const _TotpCard({
    required this.field,
    required this.onCopy,
    required this.onMenu,
    required this.l10n,
  });

  final CustomField field;
  final ValueChanged<TotpConfig> onCopy;
  final VoidCallback onMenu;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final config = field.totp;
    final issuer = (config?.issuer?.isNotEmpty ?? false)
        ? config!.issuer!
        : field.label;
    final account = config?.account;
    final subtitle = (account != null && account.isNotEmpty)
        ? '$account · ${l10n.totpRotates}'
        : l10n.totpRotates;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder(brightness), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.positiveAccent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(9),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.shield,
                  size: 16,
                  color: AppColors.positiveAccent,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      issuer,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.onSurface(brightness),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.onSurfaceSubtle(brightness),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              InkResponse(
                onTap: onMenu,
                radius: 18,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  child: Icon(
                    Icons.more_vert,
                    size: 18,
                    color: AppColors.onSurfaceSubtle(brightness),
                  ),
                ),
              ),
            ],
          ),
          if (config != null) ...[
            const SizedBox(height: AppSpacing.md),
            TotpDisplay(config: config, onCopy: (_) => onCopy(config)),
          ],
        ],
      ),
    );
  }
}

/// A rounded, dashed-border container — the empty-state affordance shared
/// by the 2FA section (and available for other "nothing here yet, tap to
/// add" prompts).
class DottedBorderBox extends StatelessWidget {
  const DottedBorderBox({
    super.key,
    required this.brightness,
    required this.child,
  });

  final Brightness brightness;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedRectPainter(
        color: AppColors.onSurface(brightness).withValues(alpha: 0.18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: child,
      ),
    );
  }
}

class _DashedRectPainter extends CustomPainter {
  _DashedRectPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(12),
    );
    final path = Path()..addRRect(rrect);
    const dash = 5.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, distance + dash),
          paint,
        );
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRectPainter oldDelegate) =>
      oldDelegate.color != color;
}
