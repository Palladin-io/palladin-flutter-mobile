import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../config/contact_config.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_dropdown_field.dart';
import '../../../../core/widgets/app_toggle.dart';
import '../../../../core/widgets/sheet_action_buttons.dart';
import '../../../../core/widgets/sheet_drag_handle.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../onboarding/presentation/widgets/onboarding_text_field.dart';
import '../../data/services/sign_in_candidate_service.dart';
import '../../domain/entities/sign_in_method.dart';

/// The user's explicit choice from [SignInMethodSheet]. A null [binding]
/// removes the selected saved sign-in method.
final class SignInMethodChoice {
  const SignInMethodChoice(this.binding, {this.discovery = false});

  final bool discovery;

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

/// Loads the discoverable Palladin Credentials of one provider.
typedef SignInCandidateLoader =
    Future<List<SignInProviderCandidate>> Function(SignInProvider provider);

/// Bottom sheet that sets, replaces or removes a Credential's remembered
/// external sign-in provider and provider account. An existing Palladin
/// Credential of the provider can be linked explicitly. Returns null on
/// cancel.
class SignInMethodSheet {
  const SignInMethodSheet._();

  static Future<SignInMethodChoice?> show(
    BuildContext context, {
    SignInMethodBinding? initial,
    bool discovery = false,
    required bool canRemove,
    SignInCandidateLoader? loadCandidates,
  }) => showModalBottomSheet<SignInMethodChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.transparent,
    builder: (_) => _SignInMethodBody(
      initial: initial,
      discovery: discovery,
      canRemove: canRemove,
      loadCandidates: loadCandidates,
    ),
  );
}

class _SignInMethodBody extends StatefulWidget {
  const _SignInMethodBody({
    required this.initial,
    required this.discovery,
    required this.canRemove,
    required this.loadCandidates,
  });

  final SignInMethodBinding? initial;
  final bool discovery;
  final bool canRemove;
  final SignInCandidateLoader? loadCandidates;

  @override
  State<_SignInMethodBody> createState() => _SignInMethodBodyState();
}

class _SignInMethodBodyState extends State<_SignInMethodBody> {
  late SignInProvider? _provider = widget.initial?.provider;
  late final TextEditingController _accountController = TextEditingController(
    text: widget.initial?.account ?? '',
  );
  final _providerScroll = ScrollController();
  final _initialProvider = GlobalKey();
  bool _accountTooLong = false;
  late bool _discovery = widget.discovery;
  late SignInEntryReference? _entry = widget.initial?.entry;
  List<SignInProviderCandidate>? _candidates;
  int _candidateGeneration = 0;

  @override
  void initState() {
    super.initState();
    final provider = _provider;
    if (provider != null) {
      _loadCandidates(provider);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_providerScroll.hasClients) return;
        final target = _initialProvider.currentContext?.findRenderObject();
        if (target != null) {
          _providerScroll.position.ensureVisible(
            target,
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          );
        }
      });
    }
  }

  Future<void> _loadCandidates(SignInProvider provider) async {
    final loader = widget.loadCandidates;
    final generation = ++_candidateGeneration;
    if (loader == null) return;
    List<SignInProviderCandidate> loaded;
    try {
      loaded = await loader(provider);
    } catch (_) {
      loaded = const [];
    }
    if (!mounted || generation != _candidateGeneration) return;
    setState(() {
      _candidates = loaded;
      // A link is kept only while it still names an offered Credential.
      if (!loaded.any((candidate) => candidate.reference == _entry)) {
        _entry = null;
      }
    });
  }

  void _selectProvider(SignInProvider? next) {
    if (next == null || next == _provider) return;
    setState(() {
      _provider = next;
      _entry = null;
      _candidates = null;
    });
    _loadCandidates(next);
  }

  void _selectCandidate(SignInEntryReference? reference) {
    final candidate = _candidates?.where(
      (value) => value.reference == reference,
    );
    setState(() {
      _entry = reference;
      _accountTooLong = false;
      if (candidate != null && candidate.isNotEmpty) {
        _accountController.text = candidate.first.account;
      }
    });
  }

  @override
  void dispose() {
    _providerScroll.dispose();
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
          SignInMethodBinding(
            provider: provider,
            account: account,
            entry: _entry,
          ),
          discovery: _discovery,
        ),
      );
    } on SignInAccountException {
      setState(() => _accountTooLong = true);
    }
  }

  Widget _linkedEntryField(AppLocalizations l10n) {
    final candidates = _candidates;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppDropdownField<SignInEntryReference?>(
          key: const ValueKey('sign-in-method-linked-entry'),
          label: l10n.entrySignInMethodLinkedEntry,
          value:
              candidates != null &&
                  candidates.any((value) => value.reference == _entry)
              ? _entry
              : null,
          filled: false,
          enabled: candidates != null && candidates.isNotEmpty,
          hint: Text(switch (candidates) {
            null => l10n.entrySignInMethodLinkedEntryLoading,
            [] => l10n.entrySignInMethodLinkedEntryEmpty,
            _ => l10n.entrySignInMethodLinkedEntryNone,
          }),
          items: [
            if (candidates != null && candidates.isNotEmpty)
              DropdownMenuItem<SignInEntryReference?>(
                value: null,
                child: Text(l10n.entrySignInMethodLinkedEntryNone),
              ),
            for (final candidate in candidates ?? const [])
              DropdownMenuItem<SignInEntryReference?>(
                value: candidate.reference,
                child: Text(
                  l10n.entrySignInMethodWithAccount(
                    candidate.label,
                    candidate.account,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: _selectCandidate,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          l10n.entrySignInMethodAgentHint,
          style: TextStyle(
            color: AppColors.onSurfaceMuted(Theme.of(context).brightness),
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  void _scrollProviders(double direction) {
    if (!_providerScroll.hasClients) return;
    final target =
        (_providerScroll.offset +
                direction * _providerScroll.position.viewportDimension * 0.75)
            .clamp(0.0, _providerScroll.position.maxScrollExtent);
    if (MediaQuery.disableAnimationsOf(context)) {
      _providerScroll.jumpTo(target);
    } else {
      _providerScroll.animateTo(
        target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  Widget _providerChoices(AppLocalizations l10n, Brightness brightness) {
    const providers = [
      SignInProvider.google,
      SignInProvider.github,
      SignInProvider.apple,
      SignInProvider.microsoft,
      SignInProvider.facebook,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.entrySignInMethodProvider,
                style: TextStyle(
                  color: AppColors.onSurfaceMuted(brightness),
                  fontSize: 12,
                ),
              ),
            ),
            IconButton(
              tooltip: l10n.entrySignInMethodPreviousProviders,
              onPressed: () => _scrollProviders(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              tooltip: l10n.entrySignInMethodNextProviders,
              onPressed: () => _scrollProviders(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        SingleChildScrollView(
          key: const ValueKey('sign-in-method-provider'),
          controller: _providerScroll,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final provider in providers) ...[
                  if (provider != providers.first)
                    const SizedBox(width: AppSpacing.innerGap),
                  SizedBox(
                    width: 104,
                    child: Semantics(
                      key: provider == widget.initial?.provider
                          ? _initialProvider
                          : null,
                      selected: _provider == provider,
                      child: OutlinedButton(
                        key: ValueKey(
                          'sign-in-provider-${signInProviderName(l10n, provider)}',
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.onSurface(brightness),
                          side: BorderSide(
                            color: _provider == provider
                                ? AppColors.onSurface(brightness)
                                : AppColors.inputBorder(brightness),
                          ),
                          padding: const EdgeInsets.all(AppSpacing.md),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () => _selectProvider(provider),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.asset(
                              'assets/images/signin_${provider.wireName}.png',
                              width: 24,
                              height: 24,
                              excludeFromSemantics: true,
                            ),
                            const SizedBox(height: AppSpacing.innerGap),
                            Text(
                              signInProviderName(l10n, provider),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
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
          // The fields scroll in the height left above the footer band, which
          // alone absorbs the keyboard inset, so small screens with large
          // text never overflow the sheet.
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenH,
                AppSpacing.sm,
                AppSpacing.screenH,
                AppSpacing.section,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
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
                  _providerChoices(l10n, brightness),
                  if (ContactConfig.email.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => launchUrl(
                          ContactConfig.providerSuggestionUri(
                            l10n.entrySignInMethodMissingProviderSubject,
                          ),
                          mode: LaunchMode.externalApplication,
                        ),
                        child: Text(l10n.entrySignInMethodMissingProvider),
                      ),
                    ),
                  if (widget.loadCandidates != null && _provider != null) ...[
                    const SizedBox(height: AppSpacing.fieldGap),
                    AnimatedSize(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 200),
                      alignment: Alignment.topCenter,
                      child: _linkedEntryField(l10n),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.fieldGap),
                  OnboardingTextField(
                    key: const ValueKey('sign-in-method-account'),
                    label: l10n.entrySignInMethodAccount,
                    hintText: l10n.entrySignInMethodAccountHint,
                    controller: _accountController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    borderColor: _accountTooLong ? AppColors.brandRed : null,
                    focusBorderColor: _accountTooLong
                        ? AppColors.brandRed
                        : null,
                    // A typed account is no longer the linked Credential's.
                    onChanged: (_) {
                      if (_accountTooLong || _entry != null) {
                        setState(() {
                          _accountTooLong = false;
                          _entry = null;
                        });
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
                  const SizedBox(height: AppSpacing.fieldGap),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.entrySignInMethodVisibility,
                          style: TextStyle(
                            color: AppColors.onSurface(brightness),
                            fontSize: 12,
                          ),
                        ),
                      ),
                      AppToggle(
                        value: _discovery,
                        onChanged: (value) =>
                            setState(() => _discovery = value),
                      ),
                    ],
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
