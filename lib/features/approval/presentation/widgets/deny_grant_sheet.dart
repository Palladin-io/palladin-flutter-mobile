import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/sheet_action_buttons.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../onboarding/presentation/widgets/onboarding_text_field.dart';
import '../cubit/grant_approval_cubit.dart';
import 'approval_format.dart';

/// Bottom sheet to deny a pending grant with an optional reason — the mobile
/// counterpart of the web `DenyGrantDialog`. Resolves to `true` once denied.
class DenyGrantSheet extends StatelessWidget {
  const DenyGrantSheet({super.key, required this.grant});

  final PendingGrant grant;

  static Future<bool?> show(BuildContext context, PendingGrant grant) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BlocProvider<GrantApprovalCubit>(
        create: (_) => getIt<GrantApprovalCubit>(param1: grant),
        child: DenyGrantSheet(grant: grant),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _DenySheetBody(grant: grant);
}

class _DenySheetBody extends StatefulWidget {
  const _DenySheetBody({required this.grant});

  final PendingGrant grant;

  @override
  State<_DenySheetBody> createState() => _DenySheetBodyState();
}

class _DenySheetBodyState extends State<_DenySheetBody> {
  final TextEditingController _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  void _onDeny() {
    final reason = _reasonController.text.trim();
    context
        .read<GrantApprovalCubit>()
        .deny(reason: reason.isEmpty ? null : reason);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

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
                      l10n.approvalDenyTitle(
                          pendingAgentDisplayName(l10n, widget.grant)),
                      style: TextStyle(
                        color: AppColors.onSurface(brightness),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.approvalDenyText,
                      style: TextStyle(
                        color: AppColors.onSurfaceMuted(brightness),
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 16),
                    OnboardingTextField(
                      controller: _reasonController,
                      label: l10n.approvalDenyReasonLabel,
                      hintText: l10n.approvalDenyReasonHint,
                      textInputAction: TextInputAction.done,
                    ),
                  ],
                ),
              ),
              SheetActionButtons(
                onCancel: () => Navigator.of(context).pop(),
                onConfirm: _onDeny,
                confirmLabel:
                    state.isSubmitting ? l10n.approvalDenying : l10n.approvalDeny,
                confirmColor: AppColors.brandRed,
                busy: state.isSubmitting,
              ),
            ],
          ),
        );
      },
    );
  }
}
