import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../onboarding/presentation/widgets/onboarding_text_field.dart';
import '../../../onboarding/presentation/widgets/primary_button.dart';
import '../../../settings/domain/entities/api_key.dart';
import '../../../settings/domain/exceptions/settings_exceptions.dart';
import '../../../settings/presentation/widgets/settings_error_text.dart';
import '../bloc/api_keys_cubit.dart';

/// Two-phase bottom sheet for creating an API key.
///
/// Phase 1 — a name input + Generate button.
/// Phase 2 — the one-time plaintext secret, a copy-to-clipboard button
/// and a "save this now" warning.
///
/// SECURITY: the plaintext secret returned by the backend is held only
/// in this widget's transient [State] ([_newKey]). It is never written
/// to SharedPreferences, secure storage, logs, or analytics, and is
/// discarded when the sheet is dismissed.
class GenerateApiKeySheet extends StatefulWidget {
  const GenerateApiKeySheet({super.key});

  /// Shows the sheet on the root navigator. The hosting [ApiKeysCubit]
  /// is passed via [BlocProvider.value] so the sheet can create the key
  /// and trigger a list refresh on the same cubit instance.
  static Future<void> show(BuildContext context) {
    final cubit = context.read<ApiKeysCubit>();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BlocProvider<ApiKeysCubit>.value(
        value: cubit,
        child: const GenerateApiKeySheet(),
      ),
    );
  }

  @override
  State<GenerateApiKeySheet> createState() => _GenerateApiKeySheetState();
}

class _GenerateApiKeySheetState extends State<GenerateApiKeySheet> {
  final TextEditingController _nameController = TextEditingController();

  bool _isSubmitting = false;
  SettingsErrorKind? _error;

  /// The freshly created key, including its one-time plaintext secret.
  /// Held only in memory — see the class-level security note.
  NewApiKey? _newKey;

  bool get _isRevealPhase => _newKey != null;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _isSubmitting) return;
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      final created = await context.read<ApiKeysCubit>().createApiKey(name);
      if (!mounted) return;
      setState(() {
        _newKey = created;
        _isSubmitting = false;
      });
    } on SettingsException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.kind;
        _isSubmitting = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = SettingsErrorKind.unknown;
        _isSubmitting = false;
      });
    }
  }

  Future<void> _copyKey() async {
    final key = _newKey;
    if (key == null) return;
    await Clipboard.setData(ClipboardData(text: key.plaintext));
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.apiKeysKeyCopied)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final viewInsets = MediaQuery.of(context).viewInsets;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.modalBackground(brightness),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewPaddingOf(context).bottom,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenH,
              AppSpacing.fieldGap,
              AppSpacing.screenH,
              AppSpacing.screenH,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SheetHandle(),
                const SizedBox(height: AppSpacing.xxl),
                if (_isRevealPhase)
                  _RevealPhase(
                    newKey: _newKey!,
                    onCopy: _copyKey,
                  )
                else
                  _NamePhase(
                    controller: _nameController,
                    isSubmitting: _isSubmitting,
                    errorText: _error == null
                        ? null
                        : settingsErrorMessage(l10n, _error!),
                    onChanged: () => setState(() {}),
                    onSubmit: _submit,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Phase 1 — collects the key name and triggers creation.
class _NamePhase extends StatelessWidget {
  const _NamePhase({
    required this.controller,
    required this.isSubmitting,
    required this.errorText,
    required this.onChanged,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool isSubmitting;
  final String? errorText;
  final VoidCallback onChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final canSubmit = !isSubmitting && controller.text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.apiKeysGenerate,
          style: TextStyle(
            color: AppColors.onSurface(brightness),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        OnboardingTextField(
          controller: controller,
          label: l10n.apiKeysNameLabel,
          hintText: l10n.apiKeysNameHint,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          onChanged: (_) => onChanged(),
          onSubmitted: (_) {
            if (canSubmit) onSubmit();
          },
          borderColor: errorText != null ? AppColors.brandRed : null,
          focusBorderColor: errorText != null ? AppColors.brandRed : null,
          feedbackChild: Text(
            errorText ?? '',
            style: const TextStyle(fontSize: 12, color: AppColors.brandRed),
          ),
          feedbackVisible: errorText != null,
          feedbackReserveSpace: false,
        ),
        const SizedBox(height: AppSpacing.lg),
        PrimaryButton(
          label: isSubmitting
              ? l10n.apiKeysGenerating
              : l10n.apiKeysGenerateAction,
          isLoading: isSubmitting,
          onPressed: canSubmit ? onSubmit : null,
        ),
      ],
    );
  }
}

/// Phase 2 — reveals the one-time plaintext secret.
class _RevealPhase extends StatelessWidget {
  const _RevealPhase({required this.newKey, required this.onCopy});

  final NewApiKey newKey;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.apiKeysSecretTitle,
          style: TextStyle(
            color: AppColors.onSurface(brightness),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        // One-time secret warning — brand-red tinted banner so the
        // "save it now" instruction is impossible to miss.
        Container(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          decoration: BoxDecoration(
            color: AppColors.brandRed.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppColors.brandRed.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: AppColors.brandRed,
                size: 18,
              ),
              const SizedBox(width: AppSpacing.innerGap),
              Expanded(
                child: Text(
                  l10n.apiKeysSecretWarning,
                  style: const TextStyle(
                    color: AppColors.brandRed,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        // The plaintext secret in a monospace, selectable highlighted box.
        Container(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          decoration: BoxDecoration(
            color: AppColors.inputFill(brightness),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.inputBorder(brightness)),
          ),
          child: SelectableText(
            newKey.plaintext,
            style: TextStyle(
              color: AppColors.onSurface(brightness),
              fontSize: 13,
              fontFamily: 'monospace',
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          onPressed: onCopy,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.onSurface(brightness),
            side: BorderSide(color: AppColors.onSurface(brightness)),
            minimumSize: const Size(double.infinity, 44),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          icon: const Icon(Icons.copy, size: 16),
          label: Text(
            l10n.apiKeysCopyKey,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: AppSpacing.innerGap),
        PrimaryButton(
          label: l10n.apiKeysDone,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _SheetHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Center(
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.onSurfaceSubtle(brightness).withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
