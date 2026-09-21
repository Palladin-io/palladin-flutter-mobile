import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../config/env_config.dart';
import '../../../../core/crypto/vault_session_store.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/permissions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/secure_clipboard.dart';
import '../../../../core/widgets/app_bar_title.dart';
import '../../../../core/widgets/app_screen.dart';
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
import '../cubit/entry_share_creation_cubit.dart';
import '../widgets/entry_share_creation_form.dart';

class EntryShareCreationPage extends StatefulWidget {
  const EntryShareCreationPage({super.key, required this.entry});
  final EntryEntity entry;

  static Future<void> push(BuildContext context, EntryEntity entry) {
    final auth = context.read<AuthBloc>();
    return Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        builder: (_) => BlocProvider.value(
          value: auth,
          child: EntryShareCreationPage(entry: entry),
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
    if (state != AppLifecycleState.resumed) _invalidate();
  }

  @override
  void dispose() {
    _initialKey = null;
    _wipeSourceKeys();
    WidgetsBinding.instance.removeObserver(this);
    _coverAnimation?.removeStatusListener(_covered);
    _authorityCheck?.cancel();
    unawaited(_authSubscription.cancel());
    unawaited(_flowSubscription.cancel());
    unawaited(_cubit.close());
    super.dispose();
  }

  Future<void> _copy() async {
    if (_copying || _invalidated || _links == null) return;
    setState(() {
      _copying = true;
      _copyMessage = null;
    });
    final l10n = AppLocalizations.of(context)!;
    try {
      final fragment = await _cubit.fragmentForCopy();
      final shareId = _cubit.state.shareId;
      if (!mounted || _invalidated || fragment == null || shareId == null) {
        return;
      }
      await SecureClipboard.copy(
        _links!.create(shareId: shareId, fragment: fragment),
      );
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
      _cubit.state.phase == EntryShareCreationPhase.created;

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
                busy: state.phase == EntryShareCreationPhase.creating,
                failure: _failure(l10n, state.failure),
                onCreate: (options, ids) => unawaited(
                  _cubit.create(options: options, selectedIds: ids),
                ),
              );
            }
            final loading =
                state.phase == EntryShareCreationPhase.loading ||
                state.phase == EntryShareCreationPhase.creating;
            final created = state.phase == EntryShareCreationPhase.created;
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
                              : created
                              ? l10n.sharingCreated
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
                        if (created) ...[
                          const SizedBox(height: AppSpacing.section),
                          Text(
                            _links!.displayOrigin,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.onSurfaceSubtle(
                                Theme.of(context).brightness,
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.section),
                          Text(l10n.sharingLinkOnceNotice),
                        ],
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
                if (created || retry || canLoad || loading)
                  EntryShareActionFooter(
                    label: created
                        ? l10n.sharingCopyLink
                        : retry
                        ? l10n.sharingRetryCreate
                        : l10n.vaultRetry,
                    busy: loading || _copying,
                    onPressed: loading
                        ? null
                        : created
                        ? _copy
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
