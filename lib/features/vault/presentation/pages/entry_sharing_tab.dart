import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/crypto/vault_session_store.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/permissions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/app_form_section.dart';
import '../../../../core/widgets/card_action_footer.dart';
import '../../../../core/widgets/accent_button.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/sheet_action_buttons.dart';
import '../../../../core/widgets/sheet_drag_handle.dart';
import '../../../../core/widgets/skeleton_box.dart';
import '../../../../core/widgets/warning_zone.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../grants/presentation/widgets/org_grant_card.dart';
import '../../data/datasources/entry_sharing_remote_datasource.dart';
import '../../data/services/member_sync_session_authority_provider.dart';
import '../../domain/entities/entry_entity.dart';
import '../../domain/entities/entry_share_list.dart';
import '../../domain/entities/entry_share_creation.dart';
import '../cubit/entry_sharing_cubit.dart';
import '../widgets/entry_share_creation_form.dart';
import '../widgets/entry_share_protection_sheet.dart';
import 'entry_share_creation_page.dart';

class EntrySharingTab extends StatefulWidget {
  const EntrySharingTab({super.key, required this.entry, required this.active});
  final EntryEntity entry;
  final bool active;
  @override
  State<EntrySharingTab> createState() => _EntrySharingTabState();
}

class _EntrySharingTabState extends State<EntrySharingTab>
    with WidgetsBindingObserver {
  late final EntrySharingCubit _cubit;
  late final AuthBloc _auth;
  late final AuthState _initialAuth;
  late final StreamSubscription<AuthState> _authSubscription;
  Timer? _poll;
  bool _foreground = true;
  bool _identityInvalidated = false;
  bool _creating = false;
  BuildContext? _sheetContext;
  final _sheetAuthorityEpoch = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthBloc>();
    _initialAuth = _auth.state;
    _cubit = EntrySharingCubit(
      remote: getIt<EntrySharingRemoteDatasource>(),
      vaultId: widget.entry.vaultId,
      entryId: widget.entry.id,
      sessionReader: _session,
    );
    _authSubscription = _auth.stream.listen((state) {
      if (!_sameAuth(state)) {
        _identityInvalidated = true;
        _stop();
        _cubit.clear(failure: EntrySharingFailure.unavailable);
      }
    });
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _start();
  }

  bool _sameAuth(AuthState current) {
    final initial = _initialAuth;
    return initial is AuthAuthenticated &&
        current is AuthAuthenticated &&
        !current.isVaultLocked &&
        current.privateKey != null &&
        current.emailVerified &&
        current.userId == initial.userId &&
        identical(current.privateKey, initial.privateKey) &&
        (current.permissions & Permissions.vaultManage) != 0;
  }

  Future<EntrySharingSession?> _session() async {
    if (_identityInvalidated ||
        _creating ||
        !mounted ||
        !widget.active ||
        !_foreground ||
        !_sameAuth(_auth.state)) {
      return null;
    }
    final keys = getIt<VaultSessionStore>();
    final generation = keys.memberKeySessionGeneration;
    final authority = await getIt<MemberSyncSessionAuthorityProvider>()
        .current();
    if (_identityInvalidated ||
        _creating ||
        !mounted ||
        !widget.active ||
        !_foreground ||
        !_sameAuth(_auth.state) ||
        keys.memberKeySessionGeneration != generation ||
        authority.principalId != (_initialAuth as AuthAuthenticated).userId) {
      return null;
    }
    return (
      principalId: authority.principalId,
      organizationId: authority.organizationId,
      authorizationGeneration: authority.organizationMembershipGeneration,
      keyGeneration: generation,
    );
  }

  void _start() {
    if (!widget.active || !_foreground || _identityInvalidated || _creating) {
      return;
    }
    unawaited(_cubit.load());
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_sheetContext == null && !_creating) unawaited(_cubit.load());
    });
  }

  void _stop() {
    _sheetAuthorityEpoch.value++;
    _poll?.cancel();
    _poll = null;
    _cubit.clear();
    final sheet = _sheetContext;
    if (sheet != null &&
        sheet.mounted &&
        ModalRoute.of(sheet)?.isCurrent == true) {
      Navigator.of(sheet).pop(false);
    }
    _sheetContext = null;
  }

  @override
  void didUpdateWidget(EntrySharingTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      if (widget.active) {
        _start();
      } else {
        _stop();
      }
    } else if (widget.active &&
        oldWidget.entry.currentRevision != widget.entry.currentRevision) {
      unawaited(_cubit.load());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _start();
    } else {
      _stop();
    }
  }

  @override
  void dispose() {
    _sheetAuthorityEpoch.value++;
    _sheetAuthorityEpoch.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    unawaited(_authSubscription.cancel());
    unawaited(_cubit.close());
    super.dispose();
  }

  Future<void> _revoke(EntryShareListItem item) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: AppColors.modalBackground(Theme.of(context).brightness),
      builder: (sheetContext) {
        _sheetContext = sheetContext;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: SheetDragHandle()),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.screenH),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.sharingRevoke,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface(
                        Theme.of(sheetContext).brightness,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.fieldGap),
                  Text(
                    l10n.sharingRevokeNotice,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.onSurfaceSubtle(
                        Theme.of(sheetContext).brightness,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SheetActionButtons(
              onCancel: () => Navigator.of(sheetContext).pop(false),
              onConfirm: () => Navigator.of(sheetContext).pop(true),
              confirmLabel: l10n.sharingRevoke,
              confirmColor: AppColors.brandRed,
              equalActions: true,
            ),
          ],
        );
      },
    );
    _sheetContext = null;
    if (confirmed != true ||
        !mounted ||
        _identityInvalidated ||
        !widget.active ||
        !_foreground) {
      return;
    }
    final success = await _cubit.revoke(item.shareId);
    if (success &&
        mounted &&
        !_identityInvalidated &&
        widget.active &&
        _foreground) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.sharingRevoked)));
    }
  }

  Future<void> _create() async {
    if (_creating ||
        _identityInvalidated ||
        !_foreground ||
        !_sameAuth(_auth.state)) {
      return;
    }
    _creating = true;
    _poll?.cancel();
    _cubit.clear();
    await EntryShareCreationPage.push(context, widget.entry);
    _creating = false;
    if (mounted) _start();
  }

  Future<void> _changeProtection(EntryShareListItem item) async {
    if (!item.canChangeProtection ||
        _cubit.state.busy ||
        !mounted ||
        _identityInvalidated ||
        !widget.active ||
        !_foreground) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final changed = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: AppColors.transparent,
      builder: (sheetContext) {
        _sheetContext = sheetContext;
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * 0.8,
            child: EntryShareProtectionSheet(
              protection: EntryShareProtection.values.firstWhere(
                (value) => value.name == item.protection,
              ),
              authorityEpoch: _sheetAuthorityEpoch,
              onSave: (protection, secret) =>
                  _cubit.changeProtection(item.shareId, protection, secret),
            ),
          ),
        );
      },
    );
    _sheetContext = null;
    if (_cubit.state.changingProtectionId != null) {
      _cubit.clear();
      if (mounted) _start();
    }
    if (changed == true &&
        mounted &&
        !_identityInvalidated &&
        widget.active &&
        _foreground) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.sharingProtectionChanged)));
    }
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<EntrySharingCubit, EntrySharingState>(
        bloc: _cubit,
        builder: (context, state) => EntrySharingListBody(
          state: state,
          onRefresh: () => _cubit.load(),
          onMore: () => _cubit.load(more: true),
          onRevoke: _revoke,
          onChangeProtection: _changeProtection,
          onCreate:
              !_creating && state.failure != EntrySharingFailure.unavailable
              ? _create
              : null,
        ),
      );
}

class EntrySharingListBody extends StatelessWidget {
  const EntrySharingListBody({
    super.key,
    required this.state,
    required this.onRefresh,
    required this.onMore,
    required this.onRevoke,
    this.onCreate,
    this.onChangeProtection,
  });
  final EntrySharingState state;
  final Future<void> Function() onRefresh;
  final VoidCallback onMore;
  final ValueChanged<EntryShareListItem> onRevoke;
  final VoidCallback? onCreate;
  final ValueChanged<EntryShareListItem>? onChangeProtection;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: _content(context)),
        if (onCreate != null)
          EntryShareActionFooter(
            label: AppLocalizations.of(context)!.sharingCreate,
            onPressed: state.busy ? null : onCreate,
          ),
      ],
    );
  }

  Widget _content(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final textStyle = TextStyle(
      fontSize: 13,
      color: AppColors.onSurfaceSubtle(brightness),
    );
    // Do not flash the populated-list header before the first result arrives.
    // In particular, its top CTA must not jump into the centered empty state.
    if (!state.loaded && state.items.isEmpty && state.failure == null) {
      if (!state.loading) return const SizedBox.expand();
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
          child: SizedBox(width: 240, child: SkeletonBox(height: 180)),
        ),
      );
    }
    if (state.loaded && state.items.isEmpty && state.failure == null) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: AppEmptyState(
                icon: Icons.link_outlined,
                title: l10n.sharingEmpty,
                hint: l10n.sharingEmptyHint,
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenH,
          AppSpacing.fieldGap,
          AppSpacing.screenH,
          AppSpacing.screenBottom,
        ),
        children: [
          if (state.failure != null) ...[
            Text(switch (state.failure!) {
              EntrySharingFailure.unavailable => l10n.sharingUnavailable,
              EntrySharingFailure.revoke => l10n.sharingRevokeError,
              EntrySharingFailure.protection =>
                l10n.sharingProtectionChangeError,
              _ => l10n.sharingLoadError,
            }, style: textStyle),
            if (state.failure != EntrySharingFailure.unavailable)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: state.busy
                      ? null
                      : state.failure == EntrySharingFailure.loadMore
                      ? onMore
                      : onRefresh,
                  child: Text(l10n.vaultRetry),
                ),
              ),
          ],
          if (state.loading && state.items.isEmpty)
            const SkeletonBox(height: 180)
          else if (state.loaded && state.items.isEmpty)
            Text(l10n.sharingEmpty, style: textStyle),
          for (final item in state.items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.cardGap),
              child: _ShareCard(
                item: item,
                showChangeProtection: onChangeProtection != null,
                onRevoke: state.busy ? null : () => onRevoke(item),
                onChangeProtection: onChangeProtection == null
                    ? null
                    : state.busy
                    ? null
                    : () => onChangeProtection!(item),
              ),
            ),
          if (state.nextCursor != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: state.busy ? null : onMore,
                child: Text(l10n.entryHistoryLoadMore),
              ),
            ),
          if (state.loadingMore ||
              state.revokingId != null ||
              state.changingProtectionId != null)
            const SkeletonBox(height: AppSpacing.controlHeight),
        ],
      ),
    );
  }
}

class _ShareCard extends StatelessWidget {
  const _ShareCard({
    required this.item,
    required this.onRevoke,
    this.onChangeProtection,
    this.showChangeProtection = false,
  });
  final EntryShareListItem item;
  final VoidCallback? onRevoke;
  final VoidCallback? onChangeProtection;
  final bool showChangeProtection;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    String date(DateTime? value) => value == null
        ? '—'
        : DateFormat.yMMMd(
            Localizations.localeOf(context).toLanguageTag(),
          ).add_Hm().format(value);
    final shortId = item.shareId.length <= 15
        ? item.shareId
        : '${item.shareId.substring(0, 8)}…${item.shareId.substring(item.shareId.length - 6)}';
    final recipient = switch (item.recipientMode) {
      'namedRecipient' => item.recipientEmail ?? shortId,
      'anyoneWithLink' => l10n.sharingAnyone,
      _ => shortId,
    };
    final status = switch (item.status) {
      'active' => l10n.sharingActive,
      'revoked' => l10n.sharingRevokedStatus,
      'expired' => l10n.sharingExpired,
      'suspended' => l10n.sharingSuspended,
      'locked' => l10n.sharingLocked,
      'consumed' => l10n.sharingConsumed,
      _ => l10n.responseUnknownValue,
    };
    final protection = switch (item.protection) {
      'none' => l10n.sharingProtectionNone,
      'password' => l10n.sharingProtectionPassword,
      'pin' => l10n.sharingProtectionPin,
      _ => l10n.responseUnknownValue,
    };
    Widget detail(String label, String value) => Padding(
      padding: const EdgeInsets.only(top: AppSpacing.innerGap),
      child: GrantDetailRow(label: label, value: value, maxLines: null),
    );
    return Container(
      key: ValueKey('entry-share-${item.shareId}'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder(brightness)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.cardPadding,
              vertical: AppSpacing.innerGap,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    recipient,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurface(brightness),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.innerGap),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: Text(
                    status,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurfaceSubtle(brightness),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: AppColors.cardBorder(brightness),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.cardPadding,
              AppSpacing.xs,
              AppSpacing.cardPadding,
              AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                detail(l10n.sharingValidUntil, date(item.expiresAt)),
                detail(
                  l10n.sharingReceipts,
                  '${item.deliveryCount} / ${item.maximumReceipts ?? l10n.sharingUnlimited}',
                ),
                AppFormSection(
                  label: l10n.entryTabDetails,
                  summary: protection,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      detail(
                        l10n.sharingFirstDelivery,
                        date(item.firstDeliveredAt),
                      ),
                      detail(
                        l10n.sharingLastDelivery,
                        date(item.lastDeliveredAt),
                      ),
                      detail(
                        l10n.sharingConfirmation,
                        date(item.firstConfirmedAt),
                      ),
                      detail(
                        l10n.sharingNotification,
                        item.notifyOnFirstReceipt
                            ? l10n.sharingNotificationOn
                            : l10n.sharingNotificationOff,
                      ),
                      const SizedBox(height: AppSpacing.innerGap),
                      Text(
                        l10n.sharingListNotice,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.onSurfaceSubtle(brightness),
                        ),
                      ),
                    ],
                  ),
                ),
                if (item.sourceChanged) ...[
                  const SizedBox(height: AppSpacing.section),
                  WarningZone(
                    title: l10n.sharingSourceChangedTitle,
                    message: l10n.sharingSourceChanged,
                  ),
                ],
              ],
            ),
          ),
          if (item.canRevoke)
            CardActionFooter(
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (item.canChangeProtection && showChangeProtection) ...[
                      Expanded(
                        child: AccentButton(
                          height: null,
                          label: l10n.sharingChangeProtection,
                          onPressed: onChangeProtection,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                    ],
                    Expanded(
                      child: CardRevokeButton(
                        height: item.canChangeProtection && showChangeProtection
                            ? null
                            : 36,
                        label: l10n.sharingRevoke,
                        onPressed: onRevoke,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
