import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/fab_registrar.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../onboarding/presentation/widgets/onboarding_text_field.dart';
import '../../../onboarding/presentation/widgets/primary_button.dart';
import '../../domain/entities/agent.dart';
import '../bloc/agents_cubit.dart';
import '../widgets/agent_format.dart';

/// Edit screen for an agent — lets an operator change the agent's
/// display name and description.
///
/// Owns its own [AgentsCubit], loads the list on mount and resolves the
/// agent by [agentId]. On a successful save it pops back to the caller.
/// The public key suffix and enrolled date are shown read-only.
class AgentEditPage extends StatelessWidget {
  const AgentEditPage({super.key, required this.agentId});

  /// Server-issued id of the agent being edited.
  final String agentId;

  /// Pushes the edit screen for [agentId] onto the navigator.
  static Future<void> push(BuildContext context, String agentId) {
    return context.push('/agents/$agentId/edit');
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AgentsCubit>(
      create: (_) => getIt<AgentsCubit>()..load(),
      child: _AgentEditView(agentId: agentId),
    );
  }
}

class _AgentEditView extends StatelessWidget {
  const _AgentEditView({required this.agentId});

  final String agentId;

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
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          elevation: 0,
          titleSpacing: 0,
          centerTitle: false,
          iconTheme: IconThemeData(color: AppColors.onSurface(brightness)),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 18),
            onPressed: () => context.pop(),
          ),
          title: Text(
            l10n.agentsEditTitle,
            style: TextStyle(
              color: AppColors.onSurface(brightness),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: Stack(
            children: [
              BlocBuilder<AgentsCubit, AgentsState>(
                builder: (context, state) {
                  return switch (state.status) {
                    AgentsStatus.initial || AgentsStatus.loading => const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.brandRed,
                        ),
                      ),
                    AgentsStatus.error => _CenteredMessage(
                        message: agentsErrorMessage(l10n, state.error!),
                      ),
                    AgentsStatus.loaded => _resolveBody(context, state),
                  };
                },
              ),
              const Positioned(
                width: 0,
                height: 0,
                child: FabRegistrar(fab: null),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resolveBody(BuildContext context, AgentsState state) {
    final l10n = AppLocalizations.of(context)!;
    final agent = state.agentById(agentId);
    if (agent == null) {
      return _CenteredMessage(message: l10n.agentsDetailNotFound);
    }
    return _EditForm(agent: agent);
  }
}

/// The editable form — display name + multiline description, a save
/// button and the read-only public-key / enrolled-date info.
class _EditForm extends StatefulWidget {
  const _EditForm({required this.agent});

  final Agent agent;

  @override
  State<_EditForm> createState() => _EditFormState();
}

class _EditFormState extends State<_EditForm> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.agent.name ?? '');
    _descriptionController =
        TextEditingController(text: widget.agent.description ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _onSave() async {
    final cubit = context.read<AgentsCubit>();
    // Trim both fields at submission — the cubit also trims defensively.
    await cubit.updateAgent(
      widget.agent.agentId,
      name: _nameController.text.trim(),
      description: _descriptionController.text.trim(),
    );
    if (!mounted) return;
    // Leave the screen only when the save actually succeeded — on
    // failure the snackbar surfaces the error and the form stays put.
    if (cubit.state.mutationError == null) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return BlocConsumer<AgentsCubit, AgentsState>(
      listenWhen: (prev, curr) =>
          prev.mutationError != curr.mutationError &&
          curr.mutationError != null,
      listener: (context, state) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(agentsErrorMessage(l10n, state.mutationError!)),
            ),
          );
        context.read<AgentsCubit>().acknowledgeMutationError();
      },
      builder: (context, state) {
        final isSaving = state.mutatingAgentId == widget.agent.agentId;
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            OnboardingTextField(
              controller: _nameController,
              label: l10n.agentsEditName,
              textCapitalization: TextCapitalization.none,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            OnboardingTextField(
              controller: _descriptionController,
              label: l10n.agentsEditDescription,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 20),
            _ReadOnlyInfo(agent: widget.agent),
            const SizedBox(height: 24),
            PrimaryButton(
              label: l10n.agentsEditSave,
              isLoading: isSaving,
              onPressed: isSaving ? null : _onSave,
            ),
            // A bit of trailing space so the keyboard never overlaps the
            // save button on short screens.
            SizedBox(
              height: MediaQuery.viewInsetsOf(context).bottom,
            ),
          ],
        );
      },
    );
  }
}

/// Read-only card showing the immutable public-key suffix and enrolled
/// date — context the operator may want while editing.
class _ReadOnlyInfo extends StatelessWidget {
  const _ReadOnlyInfo({required this.agent});

  final Agent agent;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder(brightness)),
      ),
      child: Column(
        children: [
          _InfoRow(
            label: l10n.agentsDetailPublicKey,
            value: agent.publicKeySuffix.isEmpty
                ? '—'
                : agent.publicKeySuffix,
            mono: true,
          ),
          if (agent.enrolledAt != null) ...[
            const SizedBox(height: 8),
            _InfoRow(
              label: l10n.agentsDetailEnrolledAt,
              value: formatAgentDate(agent.enrolledAt!),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.mono = false,
  });

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.onSurfaceSubtle(brightness),
            fontSize: 12,
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: AppColors.onSurface(brightness),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFamily: mono ? 'monospace' : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.onSurface(brightness),
            fontSize: 14,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}
