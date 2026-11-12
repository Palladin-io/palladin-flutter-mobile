import 'dart:async';
import 'autofill_username_previews.dart';
import '../../../core/widgets/warning_zone.dart';
import '../../../core/widgets/fab_registrar.dart';
import '../../shell/presentation/pages/app_shell.dart';
import '../../vault/presentation/widgets/entries_list_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../vault/domain/entities/entry_entity.dart';
import '../../vault/presentation/widgets/entry_list_card.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/skeleton_box.dart';
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
  final _usernamePreviews = AutoFillUsernamePreviews();
  late final _search = TextEditingController(
    text: widget.controller.request?.matchingHosts.length == 1
        ? widget.controller.request!.matchingHosts.single
        : '',
  );
  List<AutoFillCandidate> _candidates = const [];
  AutoFillRequestSession? _session;
  int _viewGeneration = 0;
  int? _preparingGeneration;
  int? _loadingGeneration;
  bool _automaticReloadAvailable = true, _reloadQueued = false;
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
    if (kDebugMode && changed) debugPrint('AUTOFILL_PICKER SOURCE_CHANGED');
    _selectionRevision = widget.controller.selectionRevision;
    // Preparation may commit ciphertext before candidates have been read.
    // Keep request authorization, then fence the settled candidate read below.
    if (!ended &&
        changed &&
        widget.controller.isAuthorized &&
        _preparingGeneration == _viewGeneration) {
      return;
    }
    if (ended || changed || !widget.controller.isAuthorized) {
      final recover =
          !ended &&
          changed &&
          widget.controller.isAuthorized &&
          (_automaticReloadAvailable || _reloadQueued);
      if (recover) _automaticReloadAvailable = false;
      _reloadQueued = recover;
      _viewGeneration++;
      _usernamePreviews.clear();
      _password.clear();
      setState(() {
        _session = null;
        _candidates = const [];
        _busy = recover;
        // Sync before authorization has no selection; active reads get one
        // coalesced metadata recovery, never an unbounded preparation loop.
        _failed = changed && widget.controller.isAuthorized && !recover;
        _closing = ended;
      });
      if (ended) Navigator.of(context).maybePop();
      _drainReload();
    }
  }

  void _drainReload() {
    if (!_reloadQueued || _loadingGeneration != null) return;
    _reloadQueued = false;
    if (mounted && !_closing && widget.controller.isAuthorized) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_requestChanged);
    _viewGeneration++;
    _usernamePreviews.clear();
    _session = null;
    _candidates = const [];
    _password.clear();
    _password.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _authorize({bool biometric = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      if (kDebugMode) debugPrint('AUTOFILL_PICKER AUTH_START');
      if (biometric) {
        await widget.controller.authenticatePresence();
      } else {
        await widget.authorizePassword(_password.text);
      }
      if (kDebugMode) debugPrint('AUTOFILL_PICKER AUTH_DONE');
      _password.clear();
      await _load();
    } catch (error) {
      if (kDebugMode) {
        final kind = error is AutoFillCredentialException
            ? error.kind.name
            : error.runtimeType.toString();
        debugPrint('AUTOFILL_PICKER OPERATION_FAILED $kind');
      }
      if (mounted && !_closing) setState(() => _failed = true);
    } finally {
      _password.clear();
      if (mounted && !_closing) setState(() => _busy = false);
    }
  }

  Future<void> _load() async {
    if (!mounted || _closing || !widget.controller.isAuthorized) return;
    final generation = ++_viewGeneration;
    _usernamePreviews.clear();
    _preparingGeneration = generation;
    _loadingGeneration = generation;
    setState(() {
      _session = null;
      _candidates = const [];
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

      if (kDebugMode) debugPrint('AUTOFILL_PICKER PREPARE_START');
      final session = await widget.prepare();
      if (kDebugMode) debugPrint('AUTOFILL_PICKER PREPARE_DONE');
      if (_preparingGeneration == generation) _preparingGeneration = null;
      guard();
      session.validateCurrent();
      if (kDebugMode) debugPrint('AUTOFILL_PICKER READ_START');
      final candidates = request.mode == AutoFillRequestMode.manualNative
          ? await widget.credentials.manualCandidates(
              vaultIds: session.vaultIds,
              validateRequest: guard,
            )
          : await widget.credentials.candidates(
              vaultIds: session.vaultIds,
              verifiedHosts: request.matchingHosts,
              validateRequest: guard,
            );
      guard();
      session.validateCurrent();
      if (kDebugMode) debugPrint('AUTOFILL_PICKER READ_DONE');
      if (mounted && !_closing && generation == _viewGeneration) {
        setState(() {
          _session = session;
          _candidates = candidates;
        });
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('AUTOFILL_PICKER LOAD_FAILED ${error.runtimeType}');
      }
      if (mounted && !_closing && generation == _viewGeneration) {
        setState(() => _failed = true);
      }
    } finally {
      if (_preparingGeneration == generation) _preparingGeneration = null;
      if (_loadingGeneration == generation) _loadingGeneration = null;
      if (mounted && !_closing && generation == _viewGeneration) {
        setState(() => _busy = false);
      }
      _drainReload();
    }
  }

  List<String> _hosts(AutoFillCandidate candidate) {
    final request = widget.controller.request;
    if (request == null) return const [];
    return candidate.domains
        .where(
          (host) =>
              request.mode == AutoFillRequestMode.manualNative ||
              request.matchingHosts.contains(host),
        )
        .toList();
  }

  Future<AutoFillUsernamePreview> _readUsernamePreview(
    AutoFillCandidate candidate,
    String host,
  ) async {
    final generation = _viewGeneration;
    final guard = widget.controller.captureGuard();
    final source = await widget.access.ticket();
    final validate = _usernamePreviewGuard(generation, guard, source);
    validate();
    return widget.credentials.readUsernamePreview(
      candidate: candidate,
      selectedHost: host,
      memberPrivateKey: _session!.privateKey,
      validateRequest: validate,
    );
  }

  void Function() _usernamePreviewGuard(
    int generation,
    void Function() guard,
    AutoFillSourceTicket source,
  ) => () {
    if (!mounted ||
        _closing ||
        generation != _viewGeneration ||
        _session == null) {
      throw const AutoFillRequestInvalidated();
    }
    guard();
    _session!.validateCurrent();
    widget.access.validateTicket(source);
  };

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
      if (request.requiresConfirmation) {
        if (!mounted) return;
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
    } catch (error) {
      if (kDebugMode) {
        final kind = error is AutoFillCredentialException
            ? error.kind.name
            : error.runtimeType.toString();
        debugPrint('AUTOFILL_PICKER OPERATION_FAILED $kind');
      }
      if (mounted && !_closing) setState(() => _failed = true);
    } finally {
      if (mounted && !_closing) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final query = _search.text.trim().toLowerCase();
    final rows = [
      for (final candidate in _candidates)
        for (final host in _hosts(candidate))
          if (candidate.label.toLowerCase().contains(query) ||
              (candidate.username?.toLowerCase().contains(query) ?? false) ||
              host.contains(query))
            (candidate, host),
    ];
    final request = widget.controller.request;
    return EntriesListView(
      count: rows.length,
      floatingActionButton:
          context.dependOnInheritedWidgetOfExactType<AppShellScope>() == null
          ? null
          : const FabRegistrar(fab: null),
      search: _search,
      onSearchChanged: (_) => setState(() {}),
      showSearch: widget.controller.isAuthorized,
      actions: [
        IconButton(
          tooltip: l10n.vaultCancel,
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
      leading: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_failed) ...[
            Text(l10n.autofillRequestFailed),
            TextButton(
              onPressed: _busy || !widget.controller.isAuthorized
                  ? null
                  : () {
                      _automaticReloadAvailable = true;
                      unawaited(_load());
                    },
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
          ],
        ],
      ),
      footer:
          widget.controller.isAuthorized &&
              request != null &&
              request.requiresConfirmation
          ? SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenH,
                  vertical: AppSpacing.md,
                ),
                child: WarningZone(
                  title:
                      request.mode == AutoFillRequestMode.manualWeb ||
                          request.mode == AutoFillRequestMode.manualNative
                      ? l10n.autofillDestinationWarningTitle
                      : l10n.autofillRequestTitle,
                  message: request.mode == AutoFillRequestMode.manualWeb
                      ? l10n.autofillRequestUnverifiedWebWarning(
                          request.destinationApp!,
                        )
                      : request.mode == AutoFillRequestMode.manualNative
                      ? l10n.autofillRequestManualWarning
                      : l10n.autofillRequestUsernameOnly,
                ),
              ),
            )
          : null,
      slivers: [
        if (_busy && rows.isEmpty)
          const SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
            sliver: SliverToBoxAdapter(child: SkeletonBox(height: 80)),
          )
        else if (widget.controller.isAuthorized && rows.isEmpty && !_failed)
          SliverFillRemaining(
            hasScrollBody: false,
            child: AppEmptyState(
              icon: _candidates.isEmpty ? Icons.key_outlined : Icons.search,
              title: _candidates.isEmpty
                  ? l10n.autofillRequestEmpty
                  : l10n.searchResultsEmpty,
              hint: _candidates.isEmpty
                  ? l10n.autofillRequestEmptyHint
                  : l10n.autofillRequestSearchEmptyHint,
              actionLabel: _candidates.isEmpty
                  ? null
                  : l10n.autofillRequestClearSearch,
              onAction: _candidates.isEmpty
                  ? null
                  : () => setState(_search.clear),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenH,
              0,
              AppSpacing.screenH,
              AppSpacing.listBottom,
            ),
            sliver: SliverList.separated(
              itemCount: rows.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: AppSpacing.cardGap),
              itemBuilder: (_, index) {
                final (candidate, host) = rows[index];
                return EntryListCard.selection(
                  key: ValueKey((
                    candidate.vaultId,
                    candidate.entryId,
                    candidate.revision,
                    _viewGeneration,
                  )),
                  loadUsername: () => _usernamePreviews.read((
                    candidate.vaultId,
                    candidate.entryId,
                    candidate.revision,
                    candidate.keyVersion,
                    host,
                  ), () => _readUsernamePreview(candidate, host)),
                  entry: EntryEntity(
                    id: candidate.entryId,
                    vaultId: candidate.vaultId,
                    label: candidate.label,
                    username: candidate.username,
                    icon: candidate.icon,
                    type: EntryType.credential,
                    urlDomain: host,
                    currentRevision: candidate.revision,
                    currentKeyVersion: candidate.keyVersion,
                    createdAt: DateTime.fromMillisecondsSinceEpoch(
                      0,
                      isUtc: true,
                    ),
                    updatedAt: DateTime.fromMillisecondsSinceEpoch(
                      0,
                      isUtc: true,
                    ),
                  ),
                  enabled: !_busy,
                  onSelect: () => unawaited(_fill(candidate, host)),
                );
              },
            ),
          ),
      ],
    );
  }
}
