import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../onboarding/presentation/widgets/onboarding_text_field.dart';
import '../cubit/grant_approval_cubit.dart';
import '../widgets/approval_format.dart';
import '../widgets/grant_limit_selector.dart';

/// Approve / deny screen for a single pending grant request.
///
/// On approve, the owner's in-memory private key (from the unlocked auth
/// state) is read here and handed to the cubit, which produces the
/// zero-knowledge envelope and submits it. The key is never persisted and
/// never logged.
class GrantApprovalPage extends StatelessWidget {
  const GrantApprovalPage({super.key, required this.grant});

  final PendingGrant grant;

  /// Pushes the screen and resolves to `true` when the grant was approved
  /// or denied (so the caller can drop it from the inbox).
  static Future<bool?> push(BuildContext context, PendingGrant grant) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => GrantApprovalPage(grant: grant)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<GrantApprovalCubit>(
      create: (_) => getIt<GrantApprovalCubit>(param1: grant),
      child: _GrantApprovalView(grant: grant),
    );
  }
}

class _GrantApprovalView extends StatefulWidget {
  const _GrantApprovalView({required this.grant});

  final PendingGrant grant;

  @override
  State<_GrantApprovalView> createState() => _GrantApprovalViewState();
}

class _GrantApprovalViewState extends State<_GrantApprovalView> {
  GrantLimit _limit = GrantExpiry(
    DateTime.now().add(const Duration(hours: 24)),
  );
  final TextEditingController _denyReasonController = TextEditingController();

  @override
  void dispose() {
    _denyReasonController.dispose();
    super.dispose();
  }

  /// Reads the in-memory private key from the unlocked auth state, or
  /// `null` when the vault is locked / not authenticated.
  Uint8List? _privateKey() {
    final auth = context.read<AuthBloc>().state;
    if (auth is AuthAuthenticated && !auth.isVaultLocked) {
      return auth.privateKey;
    }
    return null;
  }

  void _onApprove() {
    final key = _privateKey();
    if (key == null) {
      context.read<GrantApprovalCubit>().reportVaultLocked();
      return;
    }
    context.read<GrantApprovalCubit>().approve(privateKey: key, limit: _limit);
  }

  void _onDeny() {
    context
        .read<GrantApprovalCubit>()
        .deny(reason: _denyReasonController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final grant = widget.grant;

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
          elevation: 0,
          titleSpacing: 0,
          iconTheme: IconThemeData(color: AppColors.onSurface(brightness)),
          title: Text(
            l10n.approvalScreenTitle,
            style: TextStyle(
              color: AppColors.onSurface(brightness),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: BlocConsumer<GrantApprovalCubit, GrantApprovalState>(
            listenWhen: (prev, curr) =>
                prev.status != curr.status &&
                (curr.status == GrantApprovalStatus.done ||
                    curr.status == GrantApprovalStatus.error),
            listener: (context, state) {
              if (state.status == GrantApprovalStatus.done) {
                if (context.canPop()) context.pop(true);
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
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  _RequestSummary(grant: grant),
                  const SizedBox(height: 16),
                  Text(
                    l10n.approvalLimitSectionTitle,
                    style: TextStyle(
                      color: AppColors.onSurface(brightness),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.approvalLimitSectionHint,
                    style: TextStyle(
                      color: AppColors.onSurfaceSubtle(brightness),
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  GrantLimitSelector(
                    value: _limit,
                    enabled: !state.isSubmitting,
                    onChanged: (l) => setState(() => _limit = l),
                  ),
                  const SizedBox(height: 24),
                  _ApproveButton(
                    isSubmitting: state.isSubmitting,
                    onPressed: state.isSubmitting ? null : _onApprove,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    l10n.approvalDenySectionTitle,
                    style: TextStyle(
                      color: AppColors.onSurface(brightness),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OnboardingTextField(
                    controller: _denyReasonController,
                    label: l10n.approvalDenyReasonLabel,
                    hintText: l10n.approvalDenyReasonHint,
                    textInputAction: TextInputAction.done,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: state.isSubmitting ? null : _onDeny,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.brandRed,
                      side: const BorderSide(color: AppColors.brandRed),
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      l10n.approvalDeny,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _RequestSummary extends StatelessWidget {
  const _RequestSummary({required this.grant});

  final PendingGrant grant;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder(brightness)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            pendingAgentDisplayName(l10n, grant),
            style: TextStyle(
              color: AppColors.onSurface(brightness),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          _Line(
            label: l10n.approvalSummaryEntry,
            value: pendingEntryLabel(l10n, grant),
          ),
          _Line(
            label: l10n.approvalSummaryVault,
            value: grant.vaultName ?? l10n.approvalVaultUnknown,
          ),
          if (grant.reason != null && grant.reason!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              l10n.approvalSummaryReason,
              style: TextStyle(
                color: AppColors.onSurfaceSubtle(brightness),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              grant.reason!.trim(),
              style: TextStyle(
                color: AppColors.onSurface(brightness),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.onSurfaceSubtle(brightness),
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: AppColors.onSurface(brightness),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ApproveButton extends StatelessWidget {
  const _ApproveButton({required this.isSubmitting, required this.onPressed});

  final bool isSubmitting;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.positiveAccent,
        foregroundColor: AppColors.onBrandRed,
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      child: isSubmitting
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.onBrandRed,
              ),
            )
          : Text(
              l10n.approvalApprove,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }
}
