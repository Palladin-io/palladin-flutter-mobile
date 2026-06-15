import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/permissions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_search_field.dart';
import '../../../../core/widgets/skeleton_box.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../approval/presentation/cubit/pending_grants_cubit.dart';
import '../../../approval/presentation/widgets/approve_grant_sheet.dart';
import '../../../approval/presentation/widgets/deny_grant_sheet.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/inbox_notification.dart';
import '../../domain/exceptions/notification_center_exceptions.dart';
import '../cubit/notification_center_cubit.dart';

class NotificationCenterPage extends StatefulWidget {
  const NotificationCenterPage({super.key});

  @override
  State<NotificationCenterPage> createState() => _NotificationCenterPageState();
}

class _NotificationCenterPageState extends State<NotificationCenterPage> {
  late final NotificationCenterCubit _notifications =
      getIt<NotificationCenterCubit>();
  late final PendingGrantsCubit _pendingGrants = getIt<PendingGrantsCubit>();

  @override
  void initState() {
    super.initState();
    if (_notifications.state.status == NotificationCenterStatus.initial) {
      _notifications.load();
    } else {
      _notifications.refresh();
    }
    final auth = context.read<AuthBloc>().state;
    if (auth is AuthAuthenticated &&
        (auth.permissions & Permissions.grantManage) != 0) {
      _pendingGrants.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<NotificationCenterCubit>.value(value: _notifications),
        BlocProvider<PendingGrantsCubit>.value(value: _pendingGrants),
      ],
      child: const _NotificationCenterView(),
    );
  }
}

class _NotificationCenterView extends StatefulWidget {
  const _NotificationCenterView();

  @override
  State<_NotificationCenterView> createState() =>
      _NotificationCenterViewState();
}

class _NotificationCenterViewState extends State<_NotificationCenterView> {
  final TextEditingController _searchController = TextEditingController();
  int _segment = 0;
  bool _filtersOpen = false;
  String? _topic;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openItem(InboxNotification item) async {
    final notifications = context.read<NotificationCenterCubit>();
    await notifications.markRead(item.id);
    if (!mounted || !item.isOpenAction) return;

    if (_isGrantAction(item)) {
      await _openGrantAction(item);
      return;
    }
    final target = item.actionTarget;
    if (target != null && target.startsWith('/')) context.go(target);
  }

  bool _isGrantAction(InboxNotification item) {
    final action = item.actionType?.toLowerCase() ?? '';
    final type = item.type.toLowerCase();
    return action.contains('grant') || type.contains('grant');
  }

  Future<void> _openGrantAction(InboxNotification item) async {
    final pending = context.read<PendingGrantsCubit>();
    // Resolve against fresh source data: the Inbox event can arrive before
    // the pending-grants singleton has observed the new request.
    await pending.refresh();
    if (!mounted) return;
    final grantId = _grantId(item);
    PendingGrant? grant;
    for (final candidate in pending.state.grants) {
      if (candidate.grantId == grantId) {
        grant = candidate;
        break;
      }
    }
    if (grant == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.inboxActionGone)),
      );
      await context.read<NotificationCenterCubit>().refresh();
      return;
    }
    final handled = await ApproveGrantSheet.show(context, grant);
    if (!mounted || handled != true) return;
    pending.removeGrant(grant.grantId);
    await context.read<NotificationCenterCubit>().refresh();
  }

  Future<void> _denyGrant(InboxNotification item) async {
    await context.read<NotificationCenterCubit>().markRead(item.id);
    if (!mounted) return;
    final pending = context.read<PendingGrantsCubit>();
    final grantId = _grantId(item);
    PendingGrant? grant;
    for (final candidate in pending.state.grants) {
      if (candidate.grantId == grantId) {
        grant = candidate;
        break;
      }
    }
    if (grant == null) {
      await _openGrantAction(item);
      return;
    }
    final handled = await DenyGrantSheet.show(context, grant);
    if (!mounted || handled != true) return;
    pending.removeGrant(grant.grantId);
    await context.read<NotificationCenterCubit>().refresh();
  }

  String? _grantId(InboxNotification item) {
    for (final key in const ['grantId', 'grant_id']) {
      final value = item.data[key];
      if (value is String && value.isNotEmpty) return value;
    }
    final target = item.actionTarget;
    if (target == null) return null;
    if (!target.contains('/')) return target;
    final segments = Uri.tryParse(target)?.pathSegments ?? const <String>[];
    final grantIndex = segments.indexOf('grants');
    if (grantIndex >= 0 && grantIndex + 1 < segments.length) {
      return segments[grantIndex + 1];
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.backgroundGradient(brightness),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          centerTitle: false,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          titleSpacing: 20,
          title: Text(
            l10n.inboxTitle,
            style: TextStyle(
              color: AppColors.onSurface(brightness),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          actions: [
            BlocBuilder<NotificationCenterCubit, NotificationCenterState>(
              buildWhen: (previous, current) =>
                  previous.unreadCount != current.unreadCount ||
                  previous.isMarkingAllRead != current.isMarkingAllRead,
              builder: (context, state) => TextButton(
                onPressed: state.unreadCount == 0 || state.isMarkingAllRead
                    ? null
                    : () =>
                          context.read<NotificationCenterCubit>().markAllRead(),
                child: Text(l10n.inboxMarkAllRead),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          top: false,
          child: BlocBuilder<NotificationCenterCubit, NotificationCenterState>(
            builder: (context, state) {
              final topics =
                  state.items
                      .map((item) => item.topic)
                      .where((topic) => topic.isNotEmpty)
                      .toSet()
                      .toList()
                    ..sort();
              final items = _filtered(state.items);
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: _SegmentToggle(
                      segment: _segment,
                      actionCount: state.openActionRequiredCount,
                      onChanged: (segment) =>
                          setState(() => _segment = segment),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: AppSearchField(
                      controller: _searchController,
                      hint: l10n.inboxSearchHint,
                      filterActive: _filtersOpen,
                      onChanged: (_) => setState(() {}),
                      onToggleFilter: () =>
                          setState(() => _filtersOpen = !_filtersOpen),
                    ),
                  ),
                  if (_filtersOpen)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: _TopicFilters(
                        topics: topics,
                        selected: _topic,
                        onSelected: (topic) => setState(() => _topic = topic),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Expanded(child: _content(state, items)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  List<InboxNotification> _filtered(List<InboxNotification> items) {
    final query = _searchController.text.trim().toLowerCase();
    return items
        .where((item) {
          final segmentMatches = _segment == 0
              ? item.isOpenAction
              : !item.isOpenAction;
          final topicMatches = _topic == null || item.topic == _topic;
          final queryMatches =
              query.isEmpty ||
              item.title.toLowerCase().contains(query) ||
              item.body.toLowerCase().contains(query);
          return segmentMatches && topicMatches && queryMatches;
        })
        .toList(growable: false);
  }

  Widget _content(
    NotificationCenterState state,
    List<InboxNotification> items,
  ) {
    final l10n = AppLocalizations.of(context)!;
    return switch (state.status) {
      NotificationCenterStatus.initial ||
      NotificationCenterStatus.loading => const _InboxSkeleton(),
      NotificationCenterStatus.error => _ErrorView(
        message: _errorMessage(l10n, state.error!),
        onRetry: () => context.read<NotificationCenterCubit>().load(),
      ),
      NotificationCenterStatus.loaded => RefreshIndicator(
        color: AppColors.brandRed,
        backgroundColor: AppColors.cardSurface(Theme.of(context).brightness),
        onRefresh: () => context.read<NotificationCenterCubit>().refresh(),
        child: items.isEmpty
            ? _EmptyView(
                title: _segment == 0
                    ? l10n.inboxTodoEmpty
                    : l10n.inboxUpdatesEmpty,
                canLoadMore: state.nextCursor != null,
                isLoadingMore: state.isLoadingMore,
                onLoadMore: () =>
                    context.read<NotificationCenterCubit>().loadMore(),
              )
            : NotificationListener<ScrollEndNotification>(
                onNotification: (notification) {
                  if (notification.metrics.extentAfter < 160) {
                    context.read<NotificationCenterCubit>().loadMore();
                  }
                  return false;
                },
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
                  itemCount: items.length + (state.isLoadingMore ? 1 : 0),
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    if (index == items.length) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(
                            color: AppColors.brandRed,
                          ),
                        ),
                      );
                    }
                    final item = items[index];
                    return _NotificationCard(
                      item: item,
                      onTap: () => _openItem(item),
                      onDeny: _isGrantAction(item) && item.isOpenAction
                          ? () => _denyGrant(item)
                          : null,
                    );
                  },
                ),
              ),
      ),
    };
  }

  String _errorMessage(
    AppLocalizations l10n,
    NotificationCenterErrorKind error,
  ) {
    return switch (error) {
      NotificationCenterErrorKind.forbidden => l10n.inboxErrorForbidden,
      NotificationCenterErrorKind.networkError => l10n.inboxErrorNetwork,
      NotificationCenterErrorKind.serverError ||
      NotificationCenterErrorKind.unknown => l10n.inboxErrorUnknown,
    };
  }
}

class _SegmentToggle extends StatelessWidget {
  const _SegmentToggle({
    required this.segment,
    required this.actionCount,
    required this.onChanged,
  });

  final int segment;
  final int actionCount;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder(brightness)),
      ),
      child: Row(
        children: [
          _SegmentButton(
            label: l10n.inboxTodo,
            badge: actionCount,
            selected: segment == 0,
            onTap: () => onChanged(0),
          ),
          _SegmentButton(
            label: l10n.inboxUpdates,
            selected: segment == 1,
            onTap: () => onChanged(1),
          ),
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final color = selected
        ? AppColors.onBrandRed
        : AppColors.onSurfaceMuted(brightness);
    return Expanded(
      child: Material(
        color: selected ? AppColors.brandRed : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (badge > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.onBrandRed.withValues(alpha: 0.2)
                          : AppColors.brandRed.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$badge',
                      style: TextStyle(
                        color: selected
                            ? AppColors.onBrandRed
                            : AppColors.brandRed,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopicFilters extends StatelessWidget {
  const _TopicFilters({
    required this.topics,
    required this.selected,
    required this.onSelected,
  });

  final List<String> topics;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _TopicChip(
          label: l10n.inboxTopicAll,
          selected: selected == null,
          onTap: () => onSelected(null),
        ),
        for (final topic in topics)
          _TopicChip(
            label: _topicLabel(l10n, topic),
            selected: selected == topic,
            onTap: () => onSelected(topic),
          ),
      ],
    );
  }
}

class _TopicChip extends StatelessWidget {
  const _TopicChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return ActionChip(
      onPressed: onTap,
      label: Text(label),
      labelStyle: TextStyle(
        color: selected
            ? AppColors.brandRed
            : AppColors.onSurfaceMuted(brightness),
        fontSize: 11,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
      backgroundColor: Colors.transparent,
      side: BorderSide(
        color: selected ? AppColors.brandRed : AppColors.cardBorder(brightness),
      ),
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.item,
    required this.onTap,
    this.onDeny,
  });

  final InboxNotification item;
  final VoidCallback onTap;
  final VoidCallback? onDeny;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final accent = item.isSecurityCritical
        ? AppColors.brandRed
        : item.isOpenAction
        ? AppColors.premiumAmber
        : AppColors.vaultBlue;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: item.isRead
              ? AppColors.cardBorder(brightness)
              : accent.withValues(alpha: 0.55),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accent.withValues(alpha: 0.14),
                        ),
                        child: Icon(_icon(item), size: 17, color: accent),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item.title,
                                    style: TextStyle(
                                      color: AppColors.onSurface(brightness),
                                      fontSize: 13,
                                      fontWeight: item.isRead
                                          ? FontWeight.w600
                                          : FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (!item.isRead)
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: const BoxDecoration(
                                      color: AppColors.brandRed,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.body,
                              style: TextStyle(
                                color: AppColors.onSurfaceMuted(brightness),
                                fontSize: 11,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${_topicLabel(l10n, item.topic)} · ${_formatDate(context, item.occurredAt)}',
                              style: TextStyle(
                                color: AppColors.onSurfaceSubtle(brightness),
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (item.isOpenAction)
              Container(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                decoration: BoxDecoration(
                  color: AppColors.cardFooterOverlay(brightness),
                  border: Border(
                    top: BorderSide(color: AppColors.cardBorder(brightness)),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (onDeny != null) ...[
                      TextButton(
                        onPressed: onDeny,
                        child: Text(l10n.approvalDeny),
                      ),
                      const SizedBox(width: 8),
                    ],
                    FilledButton(
                      onPressed: onTap,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.brandRed,
                        foregroundColor: AppColors.onBrandRed,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: Text(l10n.inboxReviewAction),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  IconData _icon(InboxNotification item) {
    if (item.isSecurityCritical) return Icons.gpp_maybe_outlined;
    final topic = item.topic.toLowerCase();
    if (topic.contains('grant') || topic.contains('access')) {
      return Icons.key_outlined;
    }
    if (topic.contains('agent') || topic.contains('identity')) {
      return Icons.smart_toy_outlined;
    }
    if (topic.contains('billing')) return Icons.receipt_long_outlined;
    return item.isOpenAction
        ? Icons.task_alt_outlined
        : Icons.notifications_outlined;
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({
    required this.title,
    required this.canLoadMore,
    required this.isLoadingMore,
    required this.onLoadMore,
  });

  final String title;
  final bool canLoadMore;
  final bool isLoadingMore;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        Icon(
          Icons.inbox_outlined,
          size: 40,
          color: AppColors.onSurfaceSubtle(brightness),
        ),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.onSurface(brightness),
            fontWeight: FontWeight.w600,
          ),
        ),
        if (canLoadMore) ...[
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: isLoadingMore ? null : onLoadMore,
              child: Text(AppLocalizations.of(context)!.inboxLoadMore),
            ),
          ),
        ],
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      children: [
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Center(
          child: OutlinedButton(
            onPressed: onRetry,
            child: Text(l10n.approvalRetry),
          ),
        ),
      ],
    );
  }
}

class _InboxSkeleton extends StatelessWidget {
  const _InboxSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      itemCount: 4,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, _) => const SkeletonBox(height: 112, borderRadius: 12),
    );
  }
}

String _topicLabel(AppLocalizations l10n, String topic) {
  return switch (topic.toLowerCase()) {
    'vault' || 'grants' || 'grant' || 'access' => l10n.inboxTopicAccess,
    'identity' || 'agents' || 'agent' => l10n.inboxTopicAgents,
    'security' => l10n.inboxTopicSecurity,
    'billing' => l10n.inboxTopicBilling,
    'system' => l10n.inboxTopicSystem,
    _ =>
      topic
          .replaceAll(RegExp(r'[_-]+'), ' ')
          .split(' ')
          .where((part) => part.isNotEmpty)
          .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
          .join(' '),
  };
}

String _formatDate(BuildContext context, DateTime date) {
  final locale = Localizations.localeOf(context).toString();
  return DateFormat.MMMd(locale).add_Hm().format(date);
}
