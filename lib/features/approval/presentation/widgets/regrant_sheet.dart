import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/sheet_action_buttons.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../grants/domain/entities/grant.dart';
import '../../../grants/presentation/widgets/grant_format.dart';
import '../cubit/regrant_cubit.dart';
import 'approval_format.dart';
import 'grant_limit_selector.dart';
import 'grant_methods_selector.dart';

/// Bottom sheet to re-grant ("Grant again") a terminal grant — the mobile
/// counterpart of the web `GrantAgainDialog`. Same policy picker + footer as
/// the approve sheet; on confirm it re-produces the zero-knowledge envelope(s)
/// and POSTs a fresh grant. Resolves to `true` once granted.
class RegrantSheet extends StatelessWidget {
  const RegrantSheet({super.key, required this.grant});

  final Grant grant;

  /// Whether [grant] can be re-granted on-device (needs the agent public key).
  static bool canRegrant(Grant grant) =>
      grant.agentPublicKey != null &&
      grant.agentPublicKey!.isNotEmpty &&
      grant.recipientAgentKeyVersion != null;

  static Future<bool?> show(BuildContext context, Grant grant) {
    final args = (
      vaultId: grant.vaultId,
      agentId: grant.agentId,
      agentPublicKey: grant.agentPublicKey ?? '',
      recipientKeyVersion: grant.recipientAgentKeyVersion,
      isFull: grant.scope == GrantScope.full,
      entryId: grant.entryId,
    );
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BlocProvider<RegrantCubit>(
        create: (_) => getIt<RegrantCubit>(param1: args),
        child: RegrantSheet(grant: grant),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _RegrantSheetBody(grant: grant);
}

class _RegrantSheetBody extends StatefulWidget {
  const _RegrantSheetBody({required this.grant});

  final Grant grant;

  @override
  State<_RegrantSheetBody> createState() => _RegrantSheetBodyState();
}

class _RegrantSheetBodyState extends State<_RegrantSheetBody> {
  GrantLimit _limit = GrantExpiry(DateTime.now().add(const Duration(days: 1)));

  // Pre-select the methods the original grant carried; fall back to the
  // privacy-preserving default when the source grant predates the feature.
  late List<GrantMethod> _methods = widget.grant.methods.isNotEmpty
      ? List.of(widget.grant.methods)
      : List.of(kDefaultGrantMethods);

  Uint8List? _privateKey() {
    final auth = context.read<AuthBloc>().state;
    if (auth is AuthAuthenticated && !auth.isVaultLocked) {
      return auth.privateKey;
    }
    return null;
  }

  void _onConfirm() {
    final key = _privateKey();
    if (key == null) {
      context.read<RegrantCubit>().reportVaultLocked();
      return;
    }
    if (_methods.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.approvalMethodNoneSelected,
            ),
          ),
        );
      return;
    }
    context.read<RegrantCubit>().submit(
      privateKey: key,
      limit: _limit,
      methods: _methods,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return BlocConsumer<RegrantCubit, RegrantState>(
      listenWhen: (p, c) =>
          p.status != c.status &&
          (c.status == RegrantStatus.done || c.status == RegrantStatus.error),
      listener: (context, state) {
        if (state.status == RegrantStatus.done) {
          Navigator.of(context).pop(true);
        } else if (state.status == RegrantStatus.error) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(content: Text(approvalErrorMessage(l10n, state.error!))),
            );
          context.read<RegrantCubit>().acknowledgeError();
        }
      },
      builder: (context, state) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.modalBackground(brightness),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenH,
                  AppSpacing.sm,
                  AppSpacing.screenH,
                  AppSpacing.xl,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.cardBorder(brightness),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.headerGap),
                    Text(
                      l10n.approvalRegrantTitle,
                      style: TextStyle(
                        color: AppColors.onSurface(brightness),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.innerGap),
                    _Subtitle(grant: widget.grant),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      l10n.approvalAccessType,
                      style: TextStyle(
                        color: AppColors.onSurfaceSubtle(brightness),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.innerGap),
                    GrantLimitSelector(
                      value: _limit,
                      enabled: !state.isSubmitting,
                      onChanged: (l) => setState(() => _limit = l),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      l10n.approvalMethodsLegend,
                      style: TextStyle(
                        color: AppColors.onSurfaceSubtle(brightness),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.innerGap),
                    GrantMethodsSelector(
                      value: _methods,
                      enabled: !state.isSubmitting,
                      onChanged: (m) => setState(() => _methods = m),
                    ),
                  ],
                ),
              ),
              SheetActionButtons(
                onCancel: () => Navigator.of(context).pop(),
                onConfirm: _onConfirm,
                confirmLabel: state.isSubmitting
                    ? l10n.approvalRegranting
                    : l10n.approvalRegrant,
                confirmColor: AppColors.positiveAccent,
                busy: state.isSubmitting,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Subtitle extends StatelessWidget {
  const _Subtitle({required this.grant});

  final Grant grant;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final base = TextStyle(
      color: AppColors.onSurfaceMuted(brightness),
      fontSize: 12,
      height: 1.45,
    );
    final strong = TextStyle(
      color: AppColors.onSurface(brightness),
      fontSize: 12,
      height: 1.45,
      fontWeight: FontWeight.w700,
    );
    final target = grant.scope == GrantScope.full
        ? l10n.grantScopeFull
        : (grant.entryLabel ?? l10n.grantEntryUnknown);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '${l10n.approvalApproveSubGrant} ', style: base),
          TextSpan(text: grantAgentDisplayName(l10n, grant), style: strong),
          TextSpan(text: ' ${l10n.approvalApproveSubAccessTo} ', style: base),
          TextSpan(text: target, style: strong),
          TextSpan(text: ' ${l10n.approvalApproveSubIn} ', style: base),
          TextSpan(
            text: grant.vaultName ?? l10n.approvalVaultUnknown,
            style: strong,
          ),
          TextSpan(text: '.', style: base),
        ],
      ),
    );
  }
}
