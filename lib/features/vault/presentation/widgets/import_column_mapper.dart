import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_dropdown_field.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../data/import/import_models.dart';

/// Fallback for CSVs that match no known profile: the user maps each
/// Palladin field to a source column. A password column is required; the
/// rest are optional. `-1` is the sentinel for "not mapped".
class ImportColumnMapper extends StatefulWidget {
  const ImportColumnMapper({
    super.key,
    required this.table,
    required this.onSubmit,
  });

  final CsvTable table;
  final ValueChanged<ColumnMapping> onSubmit;

  @override
  State<ImportColumnMapper> createState() => _ImportColumnMapperState();
}

class _ImportColumnMapperState extends State<ImportColumnMapper> {
  static const int _none = -1;

  late int _name = _guess(['name', 'title', 'account']);
  late int _username = _guess(['username', 'user', 'login', 'email']);
  late int _password = _guess(['password', 'pass', 'pwd', 'secret']);
  late int _url = _guess(['url', 'uri', 'website', 'site']);
  late int _notes = _guess(['note', 'notes', 'comment', 'extra']);
  late int _totp = _guess(['totp', 'otp', 'otpauth', '2fa']);

  /// Best-effort column guess from header substrings, or [_none].
  int _guess(List<String> needles) {
    final headers = widget.table.normalizedHeaders;
    for (var i = 0; i < headers.length; i++) {
      if (needles.any((n) => headers[i].contains(n))) return i;
    }
    return _none;
  }

  ColumnMapping get _mapping => ColumnMapping(
    nameIndex: _name == _none ? null : _name,
    usernameIndex: _username == _none ? null : _username,
    passwordIndex: _password == _none ? null : _password,
    urlIndex: _url == _none ? null : _url,
    notesIndex: _notes == _none ? null : _notes,
    totpIndex: _totp == _none ? null : _totp,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenH,
              0,
              AppSpacing.screenH,
              AppSpacing.section,
            ),
            children: [
              Text(
                l10n.importColumnMapTitle,
                style: TextStyle(
                  color: AppColors.onSurface(brightness),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.innerGap),
              Text(
                l10n.importColumnMapSubtitle,
                style: TextStyle(
                  color: AppColors.onSurfaceMuted(brightness),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: AppSpacing.section),
              _field(
                l10n.importColumnPassword,
                _password,
                (v) => setState(() => _password = v),
              ),
              const SizedBox(height: AppSpacing.fieldGap),
              _field(
                l10n.importColumnName,
                _name,
                (v) => setState(() => _name = v),
              ),
              const SizedBox(height: AppSpacing.fieldGap),
              _field(
                l10n.importColumnUsername,
                _username,
                (v) => setState(() => _username = v),
              ),
              const SizedBox(height: AppSpacing.fieldGap),
              _field(
                l10n.importColumnUrl,
                _url,
                (v) => setState(() => _url = v),
              ),
              const SizedBox(height: AppSpacing.fieldGap),
              _field(
                l10n.importColumnNotes,
                _notes,
                (v) => setState(() => _notes = v),
              ),
              const SizedBox(height: AppSpacing.fieldGap),
              _field(
                l10n.importColumnTotp,
                _totp,
                (v) => setState(() => _totp = v),
              ),
              if (_password == _none) ...[
                const SizedBox(height: AppSpacing.fieldGap),
                Text(
                  l10n.importColumnMapNeedPassword,
                  style: const TextStyle(
                    color: AppColors.brandRed,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH,
            AppSpacing.fieldGap,
            AppSpacing.screenH,
            AppSpacing.screenBottom,
          ),
          child: PrimaryButton(
            label: l10n.importColumnMapContinue,
            onPressed: _mapping.isUsable
                ? () => widget.onSubmit(_mapping)
                : null,
          ),
        ),
      ],
    );
  }

  Widget _field(String label, int value, ValueChanged<int> onChanged) {
    final l10n = AppLocalizations.of(context)!;
    return AppDropdownField<int>(
      label: label,
      value: value,
      onChanged: (v) => onChanged(v ?? _none),
      items: [
        DropdownMenuItem(value: _none, child: Text(l10n.importColumnNone)),
        for (var i = 0; i < widget.table.headers.length; i++)
          DropdownMenuItem(
            value: i,
            child: Text(
              _columnLabel(i, l10n),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }

  /// Column label — header only. We deliberately never sample a cell
  /// value here: one of these columns holds a plaintext password, so a
  /// preview would leak a secret into the picker.
  String _columnLabel(int index, AppLocalizations l10n) {
    final header = widget.table.headers[index].trim();
    return header.isEmpty ? l10n.importColumnFallback(index + 1) : header;
  }
}
