import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/secure_clipboard.dart';
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
    await SecureClipboard.copy(key.plaintext);
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
                // The reveal phase can grow taller than the viewport (agent
                // connection helpers), so the phase content scrolls while the
                // drag handle stays pinned above it.
                Flexible(
                  child: SingleChildScrollView(
                    child: _isRevealPhase
                        ? _RevealPhase(
                            newKey: _newKey!,
                            onCopy: _copyKey,
                          )
                        : _NamePhase(
                            controller: _nameController,
                            isSubmitting: _isSubmitting,
                            errorText: _error == null
                                ? null
                                : settingsErrorMessage(l10n, _error!),
                            onChanged: () => setState(() {}),
                            onSubmit: _submit,
                          ),
                  ),
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

// Product URLs shown on the reveal screen. TODO: point at the real URLs
// once palladin.io is live (mirrors the web panel's placeholders).
const String _docsUrl = 'https://palladin.io/docs';
const String _skillDocsUrl = 'https://palladin.io/docs/skill';
const String _marketUrl = 'https://palladin.io/market';
const String _installCommand = 'npm i -g @palladin/agent';

/// Phase 2 — reveals the one-time plaintext secret and the agent-connection
/// helpers (connect command, install hint, docs link, agent message).
///
/// Stateful because the agent name is editable and the `palladin connect`
/// command is rebuilt live from it. The command embeds the plaintext secret;
/// it is only rendered on this one-time screen and is never logged.
class _RevealPhase extends StatefulWidget {
  const _RevealPhase({required this.newKey, required this.onCopy});

  final NewApiKey newKey;
  final VoidCallback onCopy;

  @override
  State<_RevealPhase> createState() => _RevealPhaseState();
}

class _RevealPhaseState extends State<_RevealPhase> {
  late final TextEditingController _agentNameController =
      TextEditingController(text: widget.newKey.name);

  @override
  void dispose() {
    _agentNameController.dispose();
    super.dispose();
  }

  /// The agent identifier used in the connect command and message — the
  /// edited name, falling back to the key name when the field is cleared.
  String get _agentId {
    final trimmed = _agentNameController.text.trim();
    return trimmed.isEmpty ? widget.newKey.name : trimmed;
  }

  String get _connectCommand =>
      'palladin connect ${widget.newKey.plaintext} --id "$_agentId"';

  Future<void> _copy(String text) async {
    await SecureClipboard.copy(text);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.apiKeysCopied)));
  }

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
        _MonospaceBox(text: widget.newKey.plaintext),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          onPressed: widget.onCopy,
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
        const SizedBox(height: AppSpacing.md),
        _CollapsibleSection(
          title: l10n.apiKeysConnectTitle,
          defaultOpen: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OnboardingTextField(
                controller: _agentNameController,
                label: l10n.apiKeysAgentNameLabel,
                hintText: l10n.apiKeysNameHint,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() {}),
                feedbackReserveSpace: false,
              ),
              const SizedBox(height: AppSpacing.md),
              _MonospaceBox(
                text: _connectCommand,
                onCopy: () => _copy(_connectCommand),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                l10n.apiKeysConnectInstall,
                style: TextStyle(
                  color: AppColors.onSurfaceSubtle(brightness),
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: AppSpacing.innerGap),
              _MonospaceBox(
                text: _installCommand,
                onCopy: () => _copy(_installCommand),
              ),
              const SizedBox(height: AppSpacing.md),
              _LinkText(
                label: l10n.apiKeysConnectDocs,
                onTap: () => _copy(_docsUrl),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.innerGap),
        _CollapsibleSection(
          title: l10n.apiKeysAgentMessageTitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _MonospaceBox(
                text: l10n.apiKeysAgentMessageBody(
                  _agentId,
                  _skillDocsUrl,
                  _marketUrl,
                ),
                monospace: false,
                onCopy: () => _copy(
                  l10n.apiKeysAgentMessageBody(
                    _agentId,
                    _skillDocsUrl,
                    _marketUrl,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        PrimaryButton(
          label: l10n.apiKeysDone,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// A bordered, selectable text box (monospace by default) with an optional
/// trailing copy affordance. Reused for the secret, the connect command,
/// the install command, and the agent message.
class _MonospaceBox extends StatelessWidget {
  const _MonospaceBox({
    required this.text,
    this.onCopy,
    this.monospace = true,
  });

  final String text;
  final VoidCallback? onCopy;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.cardPadding,
        AppSpacing.md,
        onCopy == null ? AppSpacing.cardPadding : AppSpacing.sm,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.inputFill(brightness),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.inputBorder(brightness)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SelectableText(
              text,
              style: TextStyle(
                color: AppColors.onSurface(brightness),
                fontSize: monospace ? 13 : 12,
                fontFamily: monospace ? 'monospace' : null,
                height: 1.4,
              ),
            ),
          ),
          if (onCopy != null) ...[
            const SizedBox(width: AppSpacing.innerGap),
            InkResponse(
              onTap: onCopy,
              radius: 18,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xs),
                child: Icon(
                  Icons.copy,
                  size: 16,
                  color: AppColors.onSurfaceSubtle(brightness),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Brand-red tap-to-copy affordance for a URL. This surface intentionally
/// copies the link rather than opening it; the leading copy glyph makes that
/// unambiguous.
class _LinkText extends StatelessWidget {
  const _LinkText({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.copy, size: 13, color: AppColors.brandRed),
            const SizedBox(width: AppSpacing.xs),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.brandRed,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A tap-to-toggle bordered section: header row with a title + chevron and a
/// collapsible body below. Mirrors the web `CollapsibleSection`.
class _CollapsibleSection extends StatefulWidget {
  const _CollapsibleSection({
    required this.title,
    required this.child,
    this.defaultOpen = false,
  });

  final String title;
  final Widget child;
  final bool defaultOpen;

  @override
  State<_CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<_CollapsibleSection> {
  late bool _open = widget.defaultOpen;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder(brightness)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.cardPadding,
                vertical: AppSpacing.md,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: TextStyle(
                        color: AppColors.onSurface(brightness),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    _open ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: AppColors.onSurfaceSubtle(brightness),
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppColors.cardBorder(brightness)),
                ),
              ),
              padding: const EdgeInsets.all(AppSpacing.cardPadding),
              child: widget.child,
            ),
        ],
      ),
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
