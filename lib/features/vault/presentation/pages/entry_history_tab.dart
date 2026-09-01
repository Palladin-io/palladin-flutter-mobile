import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/secure_clipboard.dart';
import '../../../../core/widgets/compact_primary_button.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../public_asset_catalog/presentation/widgets/public_asset_image.dart';
import '../../data/services/canonical_entry_detail_service.dart';
import '../../data/services/encrypted_presentation_asset_service.dart';
import '../../data/services/entry_history_service.dart';
import '../../domain/entities/custom_field.dart';
import '../../domain/entities/entry_entity.dart';
import '../../domain/entities/totp_config.dart';
import '../cubit/entry_history_cubit.dart';
import '../widgets/encrypted_asset_image.dart';
import '../widgets/entry_field_row.dart';
import '../widgets/totp_display.dart';
import '../widgets/vault_visuals.dart';

class EntryHistoryTab extends StatefulWidget {
  const EntryHistoryTab({
    super.key,
    required this.entry,
    required this.onUpdated,
  });

  final EntryEntity entry;
  final ValueChanged<EntryEntity> onUpdated;

  @override
  State<EntryHistoryTab> createState() => _EntryHistoryTabState();
}

class _EntryHistoryTabState extends State<EntryHistoryTab>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      context.read<EntryHistoryCubit>().clearSensitiveState(keepItems: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BlocConsumer<EntryHistoryCubit, EntryHistoryState>(
      listenWhen: (previous, current) =>
          previous.updatedEntry != current.updatedEntry ||
          previous.failure != current.failure,
      listener: (context, state) {
        final updated = state.updatedEntry;
        if (updated != null) {
          widget.onUpdated(updated);
          _showMessage(l10n.entryHistoryRestored);
        }
        final message = switch (state.failure) {
          EntryHistoryFailure.reveal => l10n.entryHistoryDecryptError,
          EntryHistoryFailure.restore => l10n.entryHistoryRestoreError,
          EntryHistoryFailure.loadMore => l10n.entryHistoryLoadError,
          _ => null,
        };
        if (message != null) _showMessage(message);
      },
      builder: (context, state) {
        if (state.status == EntryHistoryStatus.loading) {
          return const _HistorySkeleton();
        }
        if (state.status == EntryHistoryStatus.error && state.items.isEmpty) {
          return _HistoryLoadError(
            message: l10n.entryHistoryLoadError,
            retryLabel: l10n.vaultRetry,
            onRetry: () => context.read<EntryHistoryCubit>().open(widget.entry),
          );
        }
        return ListView(
          key: const ValueKey('entry-history-list'),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH,
            AppSpacing.fieldGap,
            AppSpacing.screenH,
            AppSpacing.listBottom,
          ),
          children: [
            if (state.items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
                child: Center(
                  child: Text(
                    l10n.entryHistoryEmpty,
                    style: TextStyle(
                      color: AppColors.onSurfaceSubtle(
                        Theme.of(context).brightness,
                      ),
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            for (final version in state.items)
              _VersionCard(
                key: ValueKey('entry-history-${version.revision}'),
                entry: widget.entry,
                version: version,
                selected: state.selectedRevision == version.revision,
                snapshot: state.selectedRevision == version.revision
                    ? state.selected
                    : null,
                revealing:
                    state.status == EntryHistoryStatus.revealing &&
                    state.selectedRevision == version.revision,
                restoring:
                    state.status == EntryHistoryStatus.restoring &&
                    state.selectedRevision == version.revision,
                onReveal: () => _reveal(context, version),
                onHide: context.read<EntryHistoryCubit>().hideSelected,
                onRestore: () => _restore(context),
              ),
            if (state.nextCursor != null)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  onPressed:
                      state.status == EntryHistoryStatus.ready &&
                          !state.loadingMore
                      ? () => context.read<EntryHistoryCubit>().loadMore(
                          widget.entry,
                        )
                      : null,
                  child: Text(l10n.entryHistoryLoadMore),
                ),
              ),
          ],
        );
      },
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _reveal(BuildContext context, EntryHistoryVersion version) {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated || auth.privateKey == null) {
      _showMessage(AppLocalizations.of(context)!.entryHistoryLocked);
      return;
    }
    context.read<EntryHistoryCubit>().reveal(
      entry: widget.entry,
      version: version,
      privateKey: Uint8List.fromList(auth.privateKey!),
    );
  }

  void _restore(BuildContext context) {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated || auth.privateKey == null) return;
    context.read<EntryHistoryCubit>().restore(
      entry: widget.entry,
      privateKey: Uint8List.fromList(auth.privateKey!),
    );
  }
}

class _VersionCard extends StatelessWidget {
  const _VersionCard({
    super.key,
    required this.entry,
    required this.version,
    required this.selected,
    required this.snapshot,
    required this.revealing,
    required this.restoring,
    required this.onReveal,
    required this.onHide,
    required this.onRestore,
  });

  final EntryEntity entry;
  final EntryHistoryVersion version;
  final bool selected;
  final CanonicalEntryHistorySnapshot? snapshot;
  final bool revealing;
  final bool restoring;
  final VoidCallback onReveal;
  final VoidCallback onHide;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final current = version.revision == entry.currentRevision;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
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
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.entryHistoryVersion(version.revision),
                    style: TextStyle(
                      color: AppColors.onSurface(brightness),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                CompactPrimaryButton(
                  label: revealing
                      ? l10n.entryHistoryDecrypting
                      : selected && snapshot != null
                      ? l10n.entryHistoryHide
                      : l10n.entryHistoryReveal,
                  isLoading: revealing,
                  minimumWidth: 88,
                  onPressed: revealing
                      ? null
                      : selected && snapshot != null
                      ? onHide
                      : onReveal,
                ),
              ],
            ),
          ),
          if (snapshot != null) ...[
            Divider(
              height: 1,
              thickness: 1,
              color: AppColors.cardBorder(brightness),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.cardPadding),
              child: _HistoricalEntryView(
                key: ValueKey('entry-history-form-${version.revision}'),
                entry: entry,
                snapshot: snapshot!,
              ),
            ),
            if (!current)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.cardPadding,
                  0,
                  AppSpacing.cardPadding,
                  AppSpacing.cardPadding,
                ),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: restoring ? null : onRestore,
                    icon: restoring
                        ? const SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.onBrandRed,
                            ),
                          )
                        : const Icon(Icons.restore, size: 16),
                    label: Text(
                      restoring
                          ? l10n.entryHistoryRestoring
                          : l10n.entryHistoryRestore,
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.brandRed,
                      foregroundColor: AppColors.onBrandRed,
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
          ],
          _VersionFooter(version: version, current: current),
        ],
      ),
    );
  }
}

class _VersionFooter extends StatelessWidget {
  const _VersionFooter({required this.version, required this.current});

  final EntryHistoryVersion version;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final timestamp = DateFormat.yMMMd(
      locale,
    ).add_Hm().format(version.changedAt);
    final operation = current
        ? l10n.entryHistoryCurrent
        : _operationLabel(l10n, version.operation);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.cardPadding,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: AppColors.cardFooterOverlay(brightness),
        border: Border(
          top: BorderSide(color: AppColors.cardBorder(brightness)),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.history,
            size: 13,
            color: AppColors.onSurfaceSubtle(brightness),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              '$operation · $timestamp',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.onSurfaceSubtle(brightness),
                fontSize: 10,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                _actorLabel(l10n, version),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: TextStyle(
                  color: AppColors.onSurfaceSubtle(brightness),
                  fontSize: 10,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoricalEntryView extends StatefulWidget {
  const _HistoricalEntryView({
    super.key,
    required this.entry,
    required this.snapshot,
  });

  final EntryEntity entry;
  final CanonicalEntryHistorySnapshot snapshot;

  @override
  State<_HistoricalEntryView> createState() => _HistoricalEntryViewState();
}

class _HistoricalEntryViewState extends State<_HistoricalEntryView> {
  bool _mainSecretRevealed = false;
  final Set<String> _revealedFields = <String>{};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final secret = widget.snapshot.secret;
    final payload = widget.snapshot.payload;
    final typeValue = secret['entryType'];
    final type = typeValue is int
        ? EntryTypeExtension.fromWire(typeValue)
        : widget.entry.type;
    final fields = <Widget>[];

    void add(String label, Widget value) {
      if (fields.isNotEmpty) {
        fields.add(
          Divider(
            height: 1,
            thickness: 1,
            color: AppColors.onSurface(brightness).withValues(alpha: 0.06),
          ),
        );
      }
      fields.add(_HistoryField(label: label, child: value));
    }

    final label = secret['memberLabel'] as String? ?? '';
    add(
      l10n.entryLabelLabel,
      Row(
        children: [
          _HistoricalIcon(
            reference: secret['iconReference'] as String?,
            color: secret['color'] as String?,
            type: type,
            vaultId: widget.entry.vaultId,
            entryId: widget.entry.id,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: SelectableText(label)),
        ],
      ),
    );
    add(l10n.entryTypeLabel, SelectableText(_typeLabel(l10n, type)));

    final agentLabel = secret['agentLabel'] as String? ?? '';
    if (agentLabel.isNotEmpty) {
      add(l10n.entryAgentsAgentLabel, SelectableText(agentLabel));
    }
    _addText(
      add,
      l10n.entryDescriptionLabel,
      secret['description'],
      Icons.notes,
    );
    _addText(add, l10n.entryUrlLabel, payload['url'], Icons.link);

    switch (type) {
      case EntryType.key:
        _addSecret(
          add,
          l10n.entryValueLabel,
          payload['value'],
          Icons.vpn_key,
          _mainSecretRevealed,
          () => setState(() => _mainSecretRevealed = !_mainSecretRevealed),
        );
      case EntryType.credential:
        _addText(
          add,
          l10n.entryUsernameLabel,
          payload['username'],
          Icons.person,
        );
        _addSecret(
          add,
          l10n.entryPasswordLabel,
          payload['password'],
          Icons.lock,
          _mainSecretRevealed,
          () => setState(() => _mainSecretRevealed = !_mainSecretRevealed),
        );
        final legacyTotp = payload['totp'];
        if (legacyTotp is String) {
          final config = TotpConfig.parseUri(legacyTotp);
          if (config != null) {
            add(
              l10n.totpSectionTitle,
              TotpDisplay(config: config, onCopy: _copy),
            );
          }
        }
      case EntryType.script:
        _addSecret(
          add,
          l10n.entryScriptLabel,
          payload['script'],
          Icons.terminal,
          _mainSecretRevealed,
          () => setState(() => _mainSecretRevealed = !_mainSecretRevealed),
          multiline: true,
        );
        _addText(
          add,
          l10n.entryInterpreterLabel,
          payload['interpreter'],
          Icons.code,
        );
        for (final raw
            in payload['refs'] is List ? payload['refs'] as List : const []) {
          if (raw is! Map) continue;
          final env = raw['env'];
          final entryId = raw['entryId'];
          final fieldId = raw['fieldId'] ?? raw['field'];
          if (env is! String || entryId is! String || fieldId is! String) {
            continue;
          }
          add(env, SelectableText('${_shortId(entryId)} · $fieldId'));
        }
      case EntryType.creditCard:
        _addText(
          add,
          l10n.entryCardholderNameLabel,
          payload['cardholderName'],
          Icons.person,
        );
        _addSecret(
          add,
          l10n.entryCardNumberLabel,
          payload['cardNumber'],
          Icons.credit_card,
          _revealedFields.contains('cardNumber'),
          () => _toggle('cardNumber'),
        );
        _addText(
          add,
          l10n.entryExpiryMonthLabel,
          payload['expiryMonth'],
          Icons.calendar_month,
        );
        _addText(
          add,
          l10n.entryExpiryYearLabel,
          payload['expiryYear'],
          Icons.calendar_month,
        );
        _addText(
          add,
          l10n.entryBillingAddressLabel,
          payload['billingAddress'],
          Icons.home,
        );
    }

    for (final field in CustomField.listFromPayload(payload)) {
      switch (field.type) {
        case CustomFieldType.text || CustomFieldType.multiline:
          _addText(
            add,
            field.label,
            field.textValue,
            field.type == CustomFieldType.multiline
                ? Icons.notes
                : Icons.short_text,
            multiline: field.type == CustomFieldType.multiline,
          );
        case CustomFieldType.concealed:
          _addSecret(
            add,
            field.label,
            field.textValue,
            Icons.lock_outline,
            _revealedFields.contains(field.id),
            () => _toggle(field.id),
          );
        case CustomFieldType.totp:
          if (field.totp case final config?) {
            add(field.label, TotpDisplay(config: config, onCopy: _copy));
          }
        case CustomFieldType.unknown:
          break;
      }
    }
    _addText(
      add,
      l10n.entryNotesLabel,
      payload['notes'],
      Icons.sticky_note_2_outlined,
      multiline: true,
    );

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.inputBorder(brightness)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.cardPadding,
        vertical: AppSpacing.innerGap,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: fields,
      ),
    );
  }

  void _addText(
    void Function(String, Widget) add,
    String label,
    Object? raw,
    IconData icon, {
    bool multiline = false,
  }) {
    if (raw is! String || raw.isEmpty) return;
    add(
      label,
      EntryFieldRow(
        icon: icon,
        value: raw,
        isMasked: false,
        revealed: true,
        onToggleReveal: null,
        onCopy: () => _copy(raw),
        multiline: multiline,
      ),
    );
  }

  void _addSecret(
    void Function(String, Widget) add,
    String label,
    Object? raw,
    IconData icon,
    bool revealed,
    VoidCallback onToggle, {
    bool multiline = false,
  }) {
    if (raw is! String || raw.isEmpty) return;
    add(
      label,
      EntryFieldRow(
        icon: icon,
        value: raw,
        isMasked: true,
        revealed: revealed,
        onToggleReveal: onToggle,
        onCopy: () => _copy(raw),
        multiline: multiline,
      ),
    );
  }

  void _toggle(String fieldId) {
    setState(() {
      if (!_revealedFields.remove(fieldId)) _revealedFields.add(fieldId);
    });
  }

  Future<void> _copy(String value) => SecureClipboard.copy(value);
}

class _HistoryField extends StatelessWidget {
  const _HistoryField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.innerGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppColors.onSurfaceSubtle(brightness),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          DefaultTextStyle.merge(
            style: TextStyle(
              color: AppColors.onSurface(brightness),
              fontSize: 12,
            ),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _HistoricalIcon extends StatelessWidget {
  const _HistoricalIcon({
    required this.reference,
    required this.color,
    required this.type,
    required this.vaultId,
    required this.entryId,
  });

  final String? reference;
  final String? color;
  final EntryType type;
  final String vaultId;
  final String entryId;

  @override
  Widget build(BuildContext context) {
    final accent = VaultVisuals.colorFor(color);
    final fallback = Icon(
      EntryVisuals.iconFor(reference ?? EntryVisuals.defaultIconForType(type)),
      size: 18,
      color: accent,
    );
    final content = switch (reference) {
      final String value when value.startsWith('asset:') => EncryptedAssetImage(
        reference: value,
        target: PresentationAssetTarget.entry,
        vaultId: vaultId,
        entryId: entryId,
        width: 38,
        height: 38,
        fallback: fallback,
      ),
      final String value when value.startsWith('public-asset:') =>
        PublicAssetImage(
          reference: value,
          width: 38,
          height: 38,
          fallback: fallback,
        ),
      _ => fallback,
    };
    return Container(
      width: 38,
      height: 38,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.inputBorder(Theme.of(context).brightness),
        ),
      ),
      child: content,
    );
  }
}

class _HistorySkeleton extends StatelessWidget {
  const _HistorySkeleton();

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        AppSpacing.fieldGap,
        AppSpacing.screenH,
        AppSpacing.listBottom,
      ),
      children: [
        for (var index = 0; index < 3; index++)
          Container(
            height: 92,
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.cardFill(brightness),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.cardBorder(brightness)),
            ),
          ),
      ],
    );
  }
}

class _HistoryLoadError extends StatelessWidget {
  const _HistoryLoadError({
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screenH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              color: AppColors.brandRed,
              size: 28,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.onSurfaceSubtle(brightness),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(onPressed: onRetry, child: Text(retryLabel)),
          ],
        ),
      ),
    );
  }
}

String _operationLabel(AppLocalizations l10n, String value) =>
    switch (value.toLowerCase()) {
      '1' || 'created' => l10n.entryHistoryOperationCreated,
      '2' || 'updated' => l10n.entryHistoryOperationUpdated,
      '3' || 'archived' => l10n.entryHistoryOperationArchived,
      '4' || 'restored' => l10n.entryHistoryOperationRestored,
      '5' || 'deleted' => l10n.entryHistoryOperationDeleted,
      _ => value,
    };

String _actorLabel(AppLocalizations l10n, EntryHistoryVersion version) {
  return switch (version.changedByType.toLowerCase()) {
    '1' || 'member' => version.actorName ?? _shortId(version.changedById),
    '2' ||
    'agent' => l10n.entryHistoryAgentActor(_shortId(version.changedById)),
    '3' || 'system' => l10n.entryHistorySystemActor,
    _ => _shortId(version.changedById),
  };
}

String _typeLabel(AppLocalizations l10n, EntryType type) => switch (type) {
  EntryType.key => l10n.entryTypeKey,
  EntryType.credential => l10n.entryTypeCredential,
  EntryType.script => l10n.entryTypeScript,
  EntryType.creditCard => l10n.entryTypeCreditCard,
};

String _shortId(String value) {
  if (value.length <= 15) return value;
  return '${value.substring(0, 8)}…${value.substring(value.length - 6)}';
}
