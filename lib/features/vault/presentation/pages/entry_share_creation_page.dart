import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../config/env_config.dart';
import '../../../../core/crypto/vault_session_store.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/permissions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/accent_button.dart';
import '../../../../core/widgets/app_action_footer.dart';
import '../../../../core/widgets/app_bar_title.dart';
import '../../../../core/widgets/app_dropdown_field.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/skeleton_box.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../data/datasources/entry_sharing_remote_datasource.dart';
import '../../data/services/canonical_entry_detail_service.dart';
import '../../data/services/entry_sharing/entry_share_crypto_service.dart';
import '../../data/services/entry_sharing/entry_share_link_service.dart';
import '../../data/services/local_current_entry_service.dart';
import '../../data/services/member_sync_session_authority_provider.dart';
import '../../domain/entities/entry_entity.dart';
import '../../domain/entities/entry_share.dart';
import '../../domain/entities/entry_share_list.dart';
import '../../domain/entities/vault_entity.dart';
import '../cubit/vault_list_cubit.dart';
import '../cubit/entry_share_creation_cubit.dart';
import '../widgets/entry_share_creation_form.dart';

class EntryShareCreationPage extends StatefulWidget {
  const EntryShareCreationPage({super.key, required this.entry, this.vault});
  final EntryEntity entry;
  final VaultEntity? vault;

  static Future<void> push(BuildContext context, EntryEntity entry) {
    final auth = context.read<AuthBloc>();
    final vaults = getIt<VaultListCubit>().state;
    final vault = vaults is VaultListLoaded
        ? vaults.vaults.where((vault) => vault.id == entry.vaultId).firstOrNull
        : null;
    return Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        builder: (_) => BlocProvider.value(
          value: auth,
          child: EntryShareCreationPage(entry: entry, vault: vault),
        ),
      ),
    );
  }

  @override
  State<EntryShareCreationPage> createState() => _EntryShareCreationPageState();
}

class _EntryShareCreationPageState extends State<EntryShareCreationPage>
    with WidgetsBindingObserver {
  late final AuthBloc _auth;
  String? _initialUserId;
  Uint8List? _initialKey;
  final _sourceKeys = <Uint8List>{};
  late final EntryShareCreationCubit _cubit;
  late final StreamSubscription<AuthState> _authSubscription;
  late final StreamSubscription<EntryShareCreationState> _flowSubscription;
  EntryShareLinkService? _links;
  Animation<double>? _coverAnimation;
  Timer? _authorityCheck;
  Timer? _handoffExpiry;
  DateTime? _handoffUntil;
  bool _invalidated = false, _copying = false;
  String? _copyMessage;

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthBloc>();
    final initial = _auth.state;
    if (initial is AuthAuthenticated) {
      _initialUserId = initial.userId;
      _initialKey = initial.privateKey;
    }
    _cubit = EntryShareCreationCubit(
      remote: getIt<EntrySharingRemoteDatasource>(),
      crypto: getIt<EntryShareCryptoService>(),
      expected: widget.entry,
      sessionReader: _session,
      sourceReader: _source,
    );
    try {
      _links = EntryShareLinkService(getIt<EnvConfig>());
    } on EntryShareException {
      _invalidated = true;
    }
    _authSubscription = _auth.stream.listen((state) {
      if (!_sameAuth(state)) {
        _invalidate();
      } else if (!_invalidated) {
        unawaited(_cubit.revalidate());
      }
    });
    _flowSubscription = _cubit.stream.listen((state) {
      if (state.phase == EntryShareCreationPhase.unavailable) _clearLocal();
    });
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (_invalidated ||
        (lifecycle != null && lifecycle != AppLifecycleState.resumed)) {
      _invalidate();
    } else {
      unawaited(_cubit.load());
      _authorityCheck = Timer.periodic(
        const Duration(seconds: 5),
        (_) => unawaited(_cubit.revalidate()),
      );
    }
  }

  bool _sameAuth(AuthState state) {
    return state is AuthAuthenticated &&
        !state.isVaultLocked &&
        state.emailVerified &&
        state.privateKey != null &&
        state.userId == _initialUserId &&
        identical(state.privateKey, _initialKey) &&
        (state.permissions & Permissions.vaultManage) != 0;
  }

  Future<EntrySharingSession?> _session() async {
    if (!mounted || _invalidated || !_sameAuth(_auth.state)) return null;
    final keys = getIt<VaultSessionStore>();
    final generation = keys.memberKeySessionGeneration;
    final authority = await getIt<MemberSyncSessionAuthorityProvider>()
        .current();
    if (!mounted ||
        _invalidated ||
        !_sameAuth(_auth.state) ||
        generation != keys.memberKeySessionGeneration ||
        authority.principalId != _initialUserId) {
      return null;
    }
    return (
      principalId: authority.principalId,
      organizationId: authority.organizationId,
      authorizationGeneration: authority.organizationMembershipGeneration,
      keyGeneration: generation,
    );
  }

  Future<CanonicalEntrySnapshot> _source() async {
    if (_invalidated || !_sameAuth(_auth.state)) {
      throw const EntryShareException(EntryShareErrorKind.invalidSnapshot);
    }
    final copy = Uint8List.fromList(
      (_auth.state as AuthAuthenticated).privateKey!,
    );
    _sourceKeys.add(copy);
    try {
      return await getIt<LocalCurrentEntryService>().reveal(
        expected: widget.entry,
        memberPrivateKey: copy,
      );
    } finally {
      copy.fillRange(0, copy.length, 0);
      _sourceKeys.remove(copy);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.secondaryAnimation;
    if (!identical(animation, _coverAnimation)) {
      _coverAnimation?.removeStatusListener(_covered);
      _coverAnimation = animation;
      animation?.addStatusListener(_covered);
    }
  }

  void _covered(AnimationStatus status) {
    if (status == AnimationStatus.forward ||
        status == AnimationStatus.completed) {
      _invalidate();
    }
  }

  void _invalidate() {
    _clearLocal();
    _cubit.clear();
  }

  void _clearLocal() {
    _invalidated = true;
    _initialKey = null;
    _wipeSourceKeys();
    _authorityCheck?.cancel();
    _authorityCheck = null;
    _handoffExpiry?.cancel();
    _handoffExpiry = null;
    _handoffUntil = null;
    _copyMessage = null;
  }

  void _wipeSourceKeys() {
    for (final key in _sourceKeys) {
      key.fillRange(0, key.length, 0);
    }
    _sourceKeys.clear();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _handoffUntil != null) {
      final valid =
          DateTime.now().isBefore(_handoffUntil!) && _sameAuth(_auth.state);
      _handoffExpiry?.cancel();
      _handoffExpiry = null;
      _handoffUntil = null;
      if (!valid) {
        _invalidate();
      } else {
        unawaited(_cubit.revalidate());
      }
    } else if (state != AppLifecycleState.resumed &&
        (state == AppLifecycleState.detached ||
            _handoffUntil == null ||
            !DateTime.now().isBefore(_handoffUntil!) ||
            !_sameAuth(_auth.state))) {
      _invalidate();
    }
  }

  void _allowOneDeliveryRoundtrip() {
    // Only an explicit Copy/Share of a multi-recipient batch may briefly keep
    // its RAM-only links while the OS opens the selected receiving app.
    if (!_cubit.hasMultipleRequestedRecipients ||
        _cubit.state.links.isEmpty ||
        _invalidated) {
      return;
    }
    _handoffExpiry?.cancel();
    _handoffUntil = DateTime.now().add(const Duration(minutes: 10));
    _handoffExpiry = Timer(const Duration(minutes: 10), _invalidate);
  }

  @override
  void dispose() {
    _initialKey = null;
    _wipeSourceKeys();
    WidgetsBinding.instance.removeObserver(this);
    _coverAnimation?.removeStatusListener(_covered);
    _authorityCheck?.cancel();
    _handoffExpiry?.cancel();
    unawaited(_authSubscription.cancel());
    unawaited(_flowSubscription.cancel());
    unawaited(_cubit.close());
    super.dispose();
  }

  Future<void> _copy([int index = 0]) async {
    if (_copying || _invalidated || _links == null) return;
    setState(() {
      _copying = true;
      _copyMessage = null;
    });
    final l10n = AppLocalizations.of(context)!;
    try {
      final fragment = await _cubit.fragmentForCopy(index);
      final shareId = index < _cubit.state.links.length
          ? _cubit.state.links[index].shareId
          : null;
      if (!mounted || _invalidated || fragment == null || shareId == null) {
        return;
      }
      await Clipboard.setData(
        ClipboardData(
          text: _links!.create(shareId: shareId, fragment: fragment),
        ),
      );
      if (await _cubit.revalidate() && _canShowCopyResult) {
        _allowOneDeliveryRoundtrip();
      }
      if (_canShowCopyResult &&
          await _cubit.revalidate() &&
          _canShowCopyResult) {
        setState(() => _copyMessage = l10n.sharingCopiedLink);
      }
    } catch (_) {
      if (_canShowCopyResult &&
          await _cubit.revalidate() &&
          _canShowCopyResult) {
        setState(() => _copyMessage = l10n.sharingCopyError);
      }
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  bool get _canShowCopyResult =>
      mounted &&
      !_invalidated &&
      (_cubit.state.phase == EntryShareCreationPhase.created ||
          _cubit.state.phase == EntryShareCreationPhase.retry);

  Future<void> _share(int index, Rect origin) async {
    if (_copying || _invalidated || _links == null) return;
    setState(() {
      _copying = true;
      _copyMessage = null;
    });
    final l10n = AppLocalizations.of(context)!;
    try {
      final fragment = await _cubit.fragmentForCopy(index);
      final shareId = index < _cubit.state.links.length
          ? _cubit.state.links[index].shareId
          : null;
      if (!mounted || _invalidated || fragment == null || shareId == null) {
        return;
      }
      _allowOneDeliveryRoundtrip();
      await Share.share(
        _links!.create(shareId: shareId, fragment: fragment),
        sharePositionOrigin: origin,
      );
    } catch (_) {
      if (_canShowCopyResult &&
          await _cubit.revalidate() &&
          _canShowCopyResult) {
        setState(() => _copyMessage = l10n.sharingShareError);
      }
    } finally {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _handoffExpiry?.cancel();
        _handoffExpiry = null;
        _handoffUntil = null;
      }
      if (mounted) setState(() => _copying = false);
    }
  }

  String? _failure(AppLocalizations l10n, EntryShareCreationFailure? failure) =>
      switch (failure) {
        EntryShareCreationFailure.load => l10n.sharingSourceLoadError,
        EntryShareCreationFailure.create => l10n.sharingCreateError,
        EntryShareCreationFailure.sourceChanged => l10n.sharingSourceError,
        EntryShareCreationFailure.invalidSelection =>
          l10n.sharingSelectionError,
        null => null,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopScope<void>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _invalidate();
      },
      child: AppScreen.appBar(
        safeAreaBottom: false,
        appBar: AppBar(
          titleSpacing: 0,
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: AppColors.transparent,
          surfaceTintColor: AppColors.transparent,
          title: AppBarTitle(title: l10n.sharingCreate),
        ),
        body: BlocBuilder<EntryShareCreationCubit, EntryShareCreationState>(
          bloc: _cubit,
          builder: (context, state) {
            final selection = state.selection;
            if (selection != null) {
              return EntryShareCreationForm(
                key: ObjectKey(selection),
                selection: selection,
                entry: widget.entry,
                vault: widget.vault,
                busy: state.phase == EntryShareCreationPhase.creating,
                failure: _failure(l10n, state.failure),
                onCreate: (options) =>
                    unawaited(_cubit.create(options: options)),
              );
            }
            final loading =
                state.phase == EntryShareCreationPhase.loading ||
                state.phase == EntryShareCreationPhase.creating;
            final created =
                state.phase == EntryShareCreationPhase.created ||
                (state.phase == EntryShareCreationPhase.retry &&
                    state.links.isNotEmpty);
            if (created) {
              return _CreatedLinkView(
                links: state.links,
                retryPending: state.phase == EntryShareCreationPhase.retry,
                copying: _copying,
                message: _copyMessage,
                onCopy: _copy,
                onShare: _share,
                onRetry: () => unawaited(_cubit.retry()),
              );
            }
            final retry = state.phase == EntryShareCreationPhase.retry;
            final canLoad = state.phase == EntryShareCreationPhase.initial;
            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(AppSpacing.screenH),
                    children: [
                      if (loading)
                        const SkeletonBox(height: 180)
                      else ...[
                        Text(
                          _links == null
                              ? l10n.sharingConfigurationError
                              : retry
                              ? l10n.sharingRetryNotice
                              : _failure(l10n, state.failure) ??
                                    l10n.sharingUnavailable,
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.onSurface(
                              Theme.of(context).brightness,
                            ),
                          ),
                        ),
                        if (retry) ...[
                          const SizedBox(height: AppSpacing.section),
                          Text(l10n.sharingCancelNotice),
                        ],
                        if (_copyMessage != null) ...[
                          const SizedBox(height: AppSpacing.section),
                          Text(_copyMessage!),
                        ],
                      ],
                    ],
                  ),
                ),
                if (retry || canLoad || loading)
                  EntryShareActionFooter(
                    label: retry ? l10n.sharingRetryCreate : l10n.vaultRetry,
                    busy: loading || _copying,
                    onPressed: loading
                        ? null
                        : retry
                        ? () => unawaited(_cubit.retry())
                        : () => unawaited(_cubit.load()),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CreatedLinkView extends StatefulWidget {
  const _CreatedLinkView({
    required this.links,
    required this.retryPending,
    required this.copying,
    required this.message,
    required this.onCopy,
    required this.onShare,
    required this.onRetry,
  });

  final List<CreatedEntryShareLink> links;
  final bool retryPending;
  final bool copying;
  final String? message;
  final ValueChanged<int> onCopy;
  final void Function(int, Rect) onShare;
  final VoidCallback onRetry;

  @override
  State<_CreatedLinkView> createState() => _CreatedLinkViewState();
}

class _CreatedLinkViewState extends State<_CreatedLinkView> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, viewport) => CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: viewport.maxHeight),
                    child: Align(
                      alignment: const Alignment(0, -0.15),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.screenH,
                          vertical: AppSpacing.screenBottom,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 320),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                l10n.sharingCreated,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.onSurface(brightness),
                                ),
                              ),
                              if (widget.links.length > 1) ...[
                                const SizedBox(height: AppSpacing.section),
                                AppDropdownField<int>(
                                  label: l10n.sharingRecipientSection,
                                  value: _selected,
                                  items: [
                                    for (
                                      var index = 0;
                                      index < widget.links.length;
                                      index++
                                    )
                                      DropdownMenuItem(
                                        value: index,
                                        child: Text(
                                          widget.links[index].recipientEmail ??
                                              l10n.sharingAnyone,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                  onChanged: (value) {
                                    if (value != null) {
                                      setState(() => _selected = value);
                                    }
                                  },
                                ),
                                const SizedBox(height: AppSpacing.innerGap),
                                Text(
                                  l10n.sharingMultipleLinkHandoff,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.onSurfaceMuted(brightness),
                                  ),
                                ),
                              ],
                              if (widget.retryPending) ...[
                                const SizedBox(height: AppSpacing.section),
                                Text(
                                  l10n.sharingPartialCreation,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.onSurfaceMuted(brightness),
                                  ),
                                ),
                                TextButton(
                                  onPressed: widget.copying
                                      ? null
                                      : widget.onRetry,
                                  child: Text(l10n.sharingRetryCreate),
                                ),
                              ],
                              const SizedBox(height: AppSpacing.innerGap),
                              Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(text: l10n.sharingLinkOnceBefore),
                                    TextSpan(
                                      text: l10n.sharingLinkOnceEmphasis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    TextSpan(text: l10n.sharingLinkOnceAfter),
                                  ],
                                ),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.4,
                                  color: AppColors.onSurfaceMuted(brightness),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.innerGap),
                              Visibility(
                                visible: widget.message != null,
                                maintainSize: true,
                                maintainAnimation: true,
                                maintainState: true,
                                child: Semantics(
                                  liveRegion: true,
                                  child: IndexedStack(
                                    index:
                                        widget.message == l10n.sharingShareError
                                        ? 2
                                        : widget.message ==
                                              l10n.sharingCopyError
                                        ? 1
                                        : 0,
                                    alignment: Alignment.topCenter,
                                    children: [
                                      for (final feedback in [
                                        l10n.sharingCopiedLink,
                                        l10n.sharingCopyError,
                                        l10n.sharingShareError,
                                      ])
                                        Text(
                                          feedback,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 12,
                                            height: 1.4,
                                            color: AppColors.onSurfaceSubtle(
                                              brightness,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        AppActionFooter(
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Builder(
                    builder: (buttonContext) => AccentButton(
                      height: null,
                      label: l10n.sharingShareLink,
                      onPressed: widget.copying
                          ? null
                          : () {
                              final box =
                                  buttonContext.findRenderObject()!
                                      as RenderBox;
                              widget.onShare(
                                _selected,
                                box.localToGlobal(Offset.zero) & box.size,
                              );
                            },
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: PrimaryButton(
                    height: null,
                    label: l10n.sharingCopyLink,
                    isLoading: widget.copying,
                    onPressed: () => widget.onCopy(_selected),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
