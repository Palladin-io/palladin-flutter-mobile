import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_dropdown_field.dart';
import '../../../../core/widgets/sheet_action_buttons.dart';
import '../../../../core/widgets/sheet_drag_handle.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../onboarding/presentation/widgets/onboarding_text_field.dart';
import '../../domain/entities/sign_in_method.dart';

/// The user's explicit choice from [SignInMethodSheet]. A null [binding]
/// removes every saved sign-in method.
final class SignInMethodChoice {
  const SignInMethodChoice(this.binding);

  final SignInMethodBinding? binding;
}

/// Localized display name of an external sign-in provider.
String signInProviderName(AppLocalizations l10n, SignInProvider provider) =>
    switch (provider) {
      SignInProvider.google => l10n.signInProviderGoogle,
      SignInProvider.apple => l10n.signInProviderApple,
      SignInProvider.microsoft => l10n.signInProviderMicrosoft,
      SignInProvider.github => l10n.signInProviderGithub,
      SignInProvider.facebook => l10n.signInProviderFacebook,
    };

/// Bottom sheet that sets, replaces or removes a Credential's remembered
/// external sign-in provider and provider account. Returns null on cancel.
class SignInMethodSheet {
  const SignInMethodSheet._();

  static Future<SignInMethodChoice?> show(
    BuildContext context, {
    SignInMethodBinding? initial,
    required bool canRemove,
  }) => showModalBottomSheet<SignInMethodChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.transparent,
    builder: (_) => _SignInMethodBody(initial: initial, canRemove: canRemove),
  );
}

class _SignInMethodBody extends StatefulWidget {
  const _SignInMethodBody({required this.initial, required this.canRemove});

  final SignInMethodBinding? initial;
  final bool canRemove;

  @override
  State<_SignInMethodBody> createState() => _SignInMethodBodyState();
}

class _SignInMethodBodyState extends State<_SignInMethodBody> {
  late SignInProvider? _provider = widget.initial?.provider;
  late final TextEditingController _accountController = TextEditingController(
    text: widget.initial?.account ?? '',
  );
  bool _accountTooLong = false;

  @override
  void dispose() {
    _accountController.dispose();
    super.dispose();
  }

  void _submit() {
    final provider = _provider;
    if (provider == null) return;
    try {
      final account = SignInMethodField.normalizeAccount(
        _accountController.text,
      );
      Navigator.of(context).pop(
        SignInMethodChoice(
          SignInMethodBinding(provider: provider, account: account),
        ),
      );
    } on SignInAccountException {
      setState(() => _accountTooLong = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.modalBackground(brightness),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Center(child: SheetDragHandle()),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenH,
              AppSpacing.sm,
              AppSpacing.screenH,
              AppSpacing.section,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.entrySignInMethodLabel,
                  style: TextStyle(
                    color: AppColors.onSurface(brightness),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.innerGap),
                Text(
                  l10n.entrySignInMethodHint,
                  style: TextStyle(
                    color: AppColors.onSurfaceMuted(brightness),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: AppSpacing.section),
                AppDropdownField<SignInProvider>(
                  key: const ValueKey('sign-in-method-provider'),
                  label: l10n.entrySignInMethodProvider,
                  value: _provider,
                  filled: false,
                  hint: Text(l10n.entrySignInMethodChooseProvider),
                  items: [
                    for (final provider in SignInProvider.values)
                      DropdownMenuItem(
                        value: provider,
                        child: Text(signInProviderName(l10n, provider)),
                      ),
                  ],
                  onChanged: (next) => setState(() => _provider = next),
                ),
                const SizedBox(height: AppSpacing.fieldGap),
                OnboardingTextField(
                  key: const ValueKey('sign-in-method-account'),
                  label: l10n.entrySignInMethodAccount,
                  hintText: l10n.entrySignInMethodAccountHint,
                  controller: _accountController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  borderColor: _accountTooLong ? AppColors.brandRed : null,
                  focusBorderColor: _accountTooLong ? AppColors.brandRed : null,
                  onChanged: (_) {
                    if (_accountTooLong) {
                      setState(() => _accountTooLong = false);
                    }
                  },
                  onSubmitted: (_) => _submit(),
                  feedbackChild: Text(
                    l10n.entrySignInMethodAccountTooLong,
                    style: const TextStyle(
                      color: AppColors.brandRed,
                      fontSize: 11,
                    ),
                  ),
                  feedbackVisible: _accountTooLong,
                  feedbackReserveSpace: false,
                ),
                if (widget.canRemove) ...[
                  const SizedBox(height: AppSpacing.fieldGap),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: const ValueKey('sign-in-method-remove'),
                      onPressed: () => Navigator.of(
                        context,
                      ).pop(const SignInMethodChoice(null)),
                      child: Text(
                        l10n.entrySignInMethodRemove,
                        style: const TextStyle(color: AppColors.brandRed),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SheetActionButtons(
            onCancel: () => Navigator.of(context).pop(),
            onConfirm: _provider == null ? null : _submit,
            confirmLabel: l10n.entrySaveAction,
            confirmColor: AppColors.brandRed,
          ),
        ],
      ),
    );
  }
}
