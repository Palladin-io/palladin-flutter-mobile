import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_screen.dart';
import '../../../core/widgets/app_bar_title.dart';
import '../../onboarding/presentation/widgets/onboarding_text_field.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../data/autofill_credential_source.dart';
import '../data/autofill_request_controller.dart';
import '../data/autofill_request_session.dart';
import '../data/autofill_source_access_service.dart';

class AutoFillRequestPage extends StatefulWidget {
  const AutoFillRequestPage({
    super.key,
    required this.controller,
    required this.credentials,
    required this.access,
    required this.prepare,
    required this.authorizePassword,
    required this.biometricAvailable,
  });
  final AutoFillRequestController controller;
  final AutoFillCredentialSource credentials;
  final AutoFillSourceAccessService access;
  final Future<AutoFillRequestSession> Function() prepare;
  final Future<void> Function(String) authorizePassword;
  final Future<bool> Function() biometricAvailable;
  @override
  State<AutoFillRequestPage> createState() => _AutoFillRequestPageState();
}

class _AutoFillRequestPageState extends State<AutoFillRequestPage> {
  final _password = TextEditingController();
  List<AutoFillCandidate> _candidates = const [];
  AutoFillRequestSession? _session;
  int _viewGeneration = 0;
  late int _selectionRevision;
  bool _busy = false, _failed = false, _biometric = false, _closing = false;
  @override
  void initState() {
    super.initState();
    _selectionRevision = widget.controller.selectionRevision;
    widget.controller.addListener(_requestChanged);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    if (widget.controller.isAuthorized) {
      await _load();
      return;
    }
    try {
      final available = await widget.biometricAvailable();
      if (mounted) setState(() => _biometric = available);
    } catch (_) {
      /* Password authorization remains available. */
    }
  }

  void _requestChanged() {
    if (!mounted || _closing) return;
    final ended = widget.controller.request == null;
    final changed = _selectionRevision != widget.controller.selectionRevision;
    _selectionRevision = widget.controller.selectionRevision;
    if (ended || changed || !widget.controller.isAuthorized) {
      _viewGeneration++;
      _password.clear();
      setState(() {
        _session = null;
        _candidates = const [];
        _busy = false;
        _failed = changed;
        _closing = ended;
      });
      if (ended) Navigator.of(context).maybePop();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_requestChanged);
    _password.clear();
    _password.dispose();
    super.dispose();
  }

  Future<void> _authorize({bool biometric = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      if (biometric) {
        await widget.controller.authenticatePresence();
      } else {
        await widget.authorizePassword(_password.text);
      }
      _password.clear();
      await _load();
    } catch (_) {
      if (mounted && !_closing) setState(() => _failed = true);
    } finally {
      _password.clear();
      if (mounted && !_closing) setState(() => _busy = false);
    }
  }

  Future<void> _load() async {
    if (!mounted || _closing || !widget.controller.isAuthorized) return;
    final generation = ++_viewGeneration;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final request = widget.controller.request!;
      final authGuard = widget.controller.captureGuard();
      void guard() {
        authGuard();
        if (generation != _viewGeneration) {
          throw const AutoFillRequestInvalidated();
        }
      }

      final session = await widget.prepare();
      guard();
      session.validateCurrent();
      final candidates = request.mode == AutoFillRequestMode.manualNative
          ? await widget.credentials.manualCandidates(
              vaultIds: session.vaultIds,
              validateRequest: guard,
            )
          : await widget.credentials.candidates(
              vaultIds: session.vaultIds,
              verifiedHosts: request.verifiedHosts,
              validateRequest: guard,
            );
      guard();
      session.validateCurrent();
      if (mounted && !_closing && generation == _viewGeneration) {
        setState(() {
          _session = session;
          _candidates = candidates;
        });
      }
    } catch (_) {
      if (mounted && !_closing && generation == _viewGeneration) {
        setState(() => _failed = true);
      }
    } finally {
      if (mounted && !_closing && generation == _viewGeneration) {
        setState(() => _busy = false);
      }
    }
  }

  List<String> _hosts(AutoFillCandidate candidate) {
    final request = widget.controller.request;
    if (request == null) return const [];
    return candidate.domains
        .where(
          (host) =>
              request.mode == AutoFillRequestMode.manualNative ||
              request.verifiedHosts.contains(host),
        )
        .toList();
  }

  Future<void> _fill(AutoFillCandidate candidate, String host) async {
    final session = _session;
    final request = widget.controller.request;
    if (_busy || session == null || request == null) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final guard = widget.controller.captureGuard();
      final selectedSource = await widget.access.ticket();
      void validate() {
        guard();
        session.validateCurrent();
        widget.access.validateTicket(selectedSource);
      }

      validate();
      String? consent;
      if (request.usernameOnly ||
          request.mode == AutoFillRequestMode.manualNative) {
        if (!mounted) return;
        final l10n = AppLocalizations.of(context)!;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.autofillRequestConfirm),
            content: Text(
              '${candidate.label}\n$host\n\n${request.mode == AutoFillRequestMode.manualNative ? l10n.autofillRequestManualWarning : l10n.autofillRequestUsernameOnly}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.vaultCancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n.autofillRequestConfirm),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        validate();
        consent = await widget.controller.confirmSelection(
          candidate: candidate,
          selectedHost: host,
          source: selectedSource,
        );
      }
      await widget.credentials.withCredential(
        candidate: candidate,
        selectedHost: host,
        memberPrivateKey: session.privateKey,
        validateRequest: validate,
        complete: (credential) => widget.controller.completeCredential(
          credential,
          source: selectedSource,
          consentToken: consent,
        ),
      );
    } catch (_) {
      if (mounted && !_closing) setState(() => _failed = true);
    } finally {
      if (mounted && !_closing) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AppScreen.appBar(
      appBar: AppBar(
        titleSpacing: 0,
        centerTitle: false,
        title: AppBarTitle(title: l10n.autofillRequestTitle),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_failed) ...[
              Text(l10n.autofillRequestFailed),
              TextButton(
                onPressed: _busy || !widget.controller.isAuthorized
                    ? null
                    : _load,
                child: Text(l10n.vaultRetry),
              ),
            ],
            if (!widget.controller.isAuthorized) ...[
              Text(l10n.autofillRequestAuthorize),
              OnboardingTextField(
                controller: _password,
                obscureText: true,
                label: l10n.unlockPasswordLabel,
                onSubmitted: (_) => _authorize(),
              ),
              const SizedBox(height: AppSpacing.section),
              PrimaryButton(
                label: l10n.unlockButton,
                onPressed: _busy ? null : () => _authorize(),
              ),
              if (_biometric)
                TextButton(
                  onPressed: _busy ? null : () => _authorize(biometric: true),
                  child: Text(l10n.unlockBiometricHint),
                ),
            ] else
              Expanded(
                child: _candidates.isEmpty && !_busy && !_failed
                    ? Center(child: Text(l10n.autofillRequestEmpty))
                    : ListView(
                        children: [
                          for (final candidate in _candidates)
                            for (final host in _hosts(candidate))
                              Card(
                                margin: const EdgeInsets.only(
                                  bottom: AppSpacing.cardGap,
                                ),
                                color: AppColors.cardFill(
                                  Theme.of(context).brightness,
                                ),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                    color: AppColors.cardBorder(
                                      Theme.of(context).brightness,
                                    ),
                                  ),
                                ),
                                child: ListTile(
                                  leading: const Icon(Icons.shield_outlined),
                                  title: Text(
                                    candidate.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    host,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: _busy
                                      ? null
                                      : () => _fill(candidate, host),
                                ),
                              ),
                        ],
                      ),
              ),
          ],
        ),
      ),
    );
  }
}
