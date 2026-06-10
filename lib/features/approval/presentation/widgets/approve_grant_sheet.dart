import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/sheet_action_buttons.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../grants/domain/entities/grant_method.dart';
import '../cubit/grant_approval_cubit.dart';
import 'approval_format.dart';
import 'grant_limit_selector.dart';
import 'grant_methods_selector.dart';

/// Bottom sheet to approve a pending GRANULAR grant — the mobile counterpart of
/// the web `ApproveGrantDialog`. The owner picks an access policy (Time / Uses /
/// Lifetime) and confirms; the in-memory private key is read from the unlocked
/// auth state and handed to the cubit, which produces the zero-knowledge
/// envelope and submits it. Resolves to `true` once approved.
class ApproveGrantSheet extends StatelessWidget {
  const ApproveGrantSheet({super.key, required this.grant});

  final PendingGrant grant;

  static Future<bool?> show(BuildContext context, PendingGrant grant) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BlocProvider<GrantApprovalCubit>(
        create: (_) => getIt<GrantApprovalCubit>(param1: grant),
        child: ApproveGrantSheet(grant: grant),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _ApproveSheetBody(grant: grant);
}

class _ApproveSheetBody extends StatefulWidget {
  const _ApproveSheetBody({required this.grant});

  final PendingGrant grant;

  @override
  State<_ApproveSheetBody> createState() => _ApproveSheetBodyState();
}

class _ApproveSheetBodyState extends State<_ApproveSheetBody> {
  GrantLimit _limit = GrantExpiry(DateTime.now().add(const Duration(hours: 24)));

  // Pre-select what the agent requested; fall back to the privacy-preserving
  // default when the request predates the methods feature.
  late List<GrantMethod> _methods = widget.grant.requestedMethods.isNotEmpty
      ? List.of(widget.grant.requestedMethods)
      : List.of(kDefaultGrantMethods);

  Uint8List? _privateKey() {
    final auth = context.read<AuthBloc>().state;
    if (auth is AuthAuthenticated && !auth.isVaultLocked) return auth.privateKey;
    return null;
  }

  void _onApprove() {
    final key = _privateKey();
    if (key == null) {
      context.read<GrantApprovalCubit>().reportVaultLocked();
      return;
    }
    if (_methods.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context)!.approvalMethodNoneSelected),
        ));
      return;
    }
    context
        .read<GrantApprovalCubit>()
        .approve(privateKey: key, limit: _limit, methods: _methods);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final grant = widget.grant;

    return BlocConsumer<GrantApprovalCubit, GrantApprovalState>(
      listenWhen: (p, c) =>
          p.status != c.status &&
          (c.status == GrantApprovalStatus.done ||
              c.status == GrantApprovalStatus.error),
      listener: (context, state) {
        if (state.status == GrantApprovalStatus.done) {
          Navigator.of(context).pop(true);
        } else if (state.status == GrantApprovalStatus.error) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
              content: Text(approvalErrorMessage(l10n, state.error!)),
            ));
          context.read<GrantApprovalCubit>().acknowledgeError();
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
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
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
                    const SizedBox(height: 16),
                    Text(
                      l10n.approvalApproveTitle,
                      style: TextStyle(
                        color: AppColors.onSurface(brightness),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _Subtitle(grant: grant),
                    const SizedBox(height: 18),
                    Text(
                      l10n.approvalAccessType,
                      style: TextStyle(
                        color: AppColors.onSurfaceSubtle(brightness),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    GrantLimitSelector(
                      value: _limit,
                      enabled: !state.isSubmitting,
                      onChanged: (l) => setState(() => _limit = l),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      l10n.approvalMethodsLegend,
                      style: TextStyle(
                        color: AppColors.onSurfaceSubtle(brightness),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.approvalMethodsHelp,
                      style: TextStyle(
                        color: AppColors.onSurfaceMuted(brightness),
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    GrantMethodsSelector(
                      value: _methods,
                      requested: grant.requestedMethods,
                      enabled: !state.isSubmitting,
                      onChanged: (m) => setState(() => _methods = m),
                    ),
                  ],
                ),
              ),
              SheetActionButtons(
                onCancel: () => Navigator.of(context).pop(),
                onConfirm: _onApprove,
                confirmLabel: state.isSubmitting
                    ? l10n.approvalApproving
                    : l10n.approvalApprove,
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

/// "Grant {agent} access to {entry} in {vault}." with the names emphasised,
/// mirroring the web approve dialog's subtitle.
class _Subtitle extends StatelessWidget {
  const _Subtitle({required this.grant});

  final PendingGrant grant;

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
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '${l10n.approvalApproveSubGrant} ', style: base),
          TextSpan(text: pendingAgentDisplayName(l10n, grant), style: strong),
          TextSpan(text: ' ${l10n.approvalApproveSubAccessTo} ', style: base),
          TextSpan(text: pendingEntryLabel(l10n, grant), style: strong),
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
