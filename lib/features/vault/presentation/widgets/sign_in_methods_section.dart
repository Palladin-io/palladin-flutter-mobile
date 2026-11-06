import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/entities/custom_field.dart';
import '../../domain/entities/entry_entity.dart';
import '../../domain/entities/sign_in_method.dart';
import 'sign_in_method_sheet.dart';

/// Compact, account-distinct methods. Opaque fields have no edit affordance.
class SignInMethodsSection extends StatelessWidget {
  const SignInMethodsSection({
    super.key,
    required this.fields,
    required this.onEdit,
  });

  final List<CustomField> fields;
  final ValueChanged<SignInMethodRecognized?> onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final methods = SignInMethodField.methods(
      entryType: EntryType.credential,
      fields: fields,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.entrySignInMethodsLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurfaceMuted(brightness),
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('sign-in-method-add'),
              tooltip: l10n.entrySignInMethodAdd,
              onPressed: () => onEdit(null),
              icon: const Icon(Icons.add, size: 20),
            ),
          ],
        ),
        for (final method in methods)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.innerGap),
            child: Row(
              children: [
                Image.asset(
                  'assets/images/signin_${method.binding.provider.wireName}.png',
                  width: 20,
                  height: 20,
                  excludeFromSemantics: true,
                ),
                const SizedBox(width: AppSpacing.innerGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        signInProviderName(l10n, method.binding.provider),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.onSurface(brightness),
                        ),
                      ),
                      if (method.binding.account case final account?)
                        Text(
                          account,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.onSurfaceMuted(brightness),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  key: ValueKey('sign-in-method-edit-${method.fieldId}'),
                  tooltip: l10n.entrySignInMethodEdit,
                  onPressed: () => onEdit(method),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
