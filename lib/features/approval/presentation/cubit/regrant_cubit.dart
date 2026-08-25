import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/app_logger.dart';
import '../../../agents/domain/repositories/agents_repository.dart';
import '../../../grants/domain/entities/grant_method.dart';
import '../../domain/exceptions/approval_exceptions.dart';
import '../../domain/repositories/approval_repository.dart';

export '../../domain/repositories/approval_repository.dart'
    show GrantLimit, GrantExpiry, GrantUseLimit, GrantLifetime;

/// Identifiers a re-grant ("Grant again") needs — built from the terminal
/// grant being re-issued. Passed as the DI factory param.
typedef RegrantArgs = ({
  String vaultId,
  String agentId,
  bool isFull,
  String? entryId,
});

enum RegrantStatus { idle, submitting, done, error }

class RegrantState {
  const RegrantState({this.status = RegrantStatus.idle, this.error});

  final RegrantStatus status;
  final ApprovalErrorKind? error;

  bool get isSubmitting => status == RegrantStatus.submitting;

  RegrantState copyWith({
    RegrantStatus? status,
    ApprovalErrorKind? error,
    bool clearError = false,
  }) {
    return RegrantState(
      status: status ?? this.status,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Drives the "Grant again" (re-access) action for one terminal grant.
/// Mirrors [GrantApprovalCubit] but creates a brand-new grant via the
/// proactive create endpoint. The owner's [privateKey] is passed at call
/// time and never stored.
class RegrantCubit extends Cubit<RegrantState> {
  RegrantCubit({
    required this.repository,
    required this.agentsRepository,
    required this.args,
  }) : super(const RegrantState());

  final ApprovalRepository repository;
  final AgentsRepository agentsRepository;
  final RegrantArgs args;

  Future<void> submit({
    required Uint8List privateKey,
    required GrantLimit limit,
    required List<GrantMethod> methods,
  }) async {
    emit(state.copyWith(status: RegrantStatus.submitting, clearError: true));
    try {
      // A terminal Grant carries the binding that was valid when it was
      // created. Resolve the Agent again so a re-grant can never seal to a
      // rotated recipient key or stale access epoch.
      final agent = await agentsRepository.getAgent(args.agentId);
      await repository.createGrant(
        vaultId: args.vaultId,
        agentId: args.agentId,
        agentPublicKey: agent.publicKey,
        recipientKeyVersion: agent.recipientKeyVersion,
        agentAccessEpoch: agent.accessEpoch,
        isFull: args.isFull,
        entryId: args.entryId,
        privateKey: privateKey,
        limit: limit,
        methods: methods,
      );
      AppLogger.i('Approval', 'Re-granted agent ${args.agentId}');
      emit(state.copyWith(status: RegrantStatus.done));
    } on ApprovalException catch (e) {
      AppLogger.w('Approval', 're-grant failed: ${e.kind.name}');
      emit(state.copyWith(status: RegrantStatus.error, error: e.kind));
    } catch (e, s) {
      AppLogger.e(
        'Approval',
        're-grant failed unexpectedly',
        error: e,
        stackTrace: s,
      );
      emit(
        state.copyWith(
          status: RegrantStatus.error,
          error: ApprovalErrorKind.unknown,
        ),
      );
    }
  }

  /// Reports the vault is locked so the envelope cannot be produced.
  void reportVaultLocked() {
    emit(
      state.copyWith(
        status: RegrantStatus.error,
        error: ApprovalErrorKind.vaultLocked,
      ),
    );
  }

  void acknowledgeError() {
    if (state.error == null) return;
    emit(state.copyWith(clearError: true, status: RegrantStatus.idle));
  }
}
