import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/app_logger.dart';
import '../../../grants/domain/entities/grant_method.dart';
import '../../domain/exceptions/approval_exceptions.dart';
import '../../domain/repositories/approval_repository.dart';

export '../../domain/repositories/approval_repository.dart'
    show GrantLimit, GrantExpiry, GrantUseLimit, GrantLifetime;

enum GrantAccessStatus { idle, submitting, done, error }

class GrantAccessState {
  const GrantAccessState({this.status = GrantAccessStatus.idle, this.error});

  final GrantAccessStatus status;
  final ApprovalErrorKind? error;

  bool get isSubmitting => status == GrantAccessStatus.submitting;

  GrantAccessState copyWith({
    GrantAccessStatus? status,
    ApprovalErrorKind? error,
    bool clearError = false,
  }) {
    return GrantAccessState(
      status: status ?? this.status,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Drives the proactive "Add agent / Add grant" flow — the mobile counterpart
/// of the web `GrantAccessDialog` create. Unlike [RegrantCubit] the subject
/// (agent / vault / entry) is chosen inside the sheet, so it is supplied to
/// the mode-specific submit method rather than at construction. The owner's
/// [privateKey] is passed at call time and never stored.
class GrantAccessCubit extends Cubit<GrantAccessState> {
  GrantAccessCubit({required this.repository})
    : super(const GrantAccessState());

  final ApprovalRepository repository;

  Future<void> submitFull({
    required String vaultId,
    required String agentId,
    required String agentPublicKey,
    required int recipientKeyVersion,
    required int agentAccessEpoch,
    required Uint8List privateKey,
    required GrantLimit limit,
    required List<GrantMethod> methods,
  }) => _submit(
    operation: () => repository.createFullGrant(
      vaultId: vaultId,
      agentId: agentId,
      agentPublicKey: agentPublicKey,
      recipientKeyVersion: recipientKeyVersion,
      agentAccessEpoch: agentAccessEpoch,
      privateKey: privateKey,
      limit: limit,
      methods: methods,
    ),
    successMessage: 'Granted FULL access to agent $agentId',
  );

  Future<void> submitGranular({
    required String vaultId,
    required String entryId,
    required String agentId,
    required String agentPublicKey,
    required int recipientKeyVersion,
    required int agentAccessEpoch,
    required Uint8List privateKey,
    required GrantLimit limit,
    required List<GrantMethod> methods,
  }) => _submit(
    operation: () => repository.createGranularGrant(
      vaultId: vaultId,
      entryId: entryId,
      agentId: agentId,
      agentPublicKey: agentPublicKey,
      recipientKeyVersion: recipientKeyVersion,
      agentAccessEpoch: agentAccessEpoch,
      privateKey: privateKey,
      limit: limit,
      methods: methods,
    ),
    successMessage: 'Granted GRANULAR access to agent $agentId',
  );

  Future<void> _submit({
    required Future<void> Function() operation,
    required String successMessage,
  }) async {
    emit(
      state.copyWith(status: GrantAccessStatus.submitting, clearError: true),
    );
    try {
      await operation();
      AppLogger.i('Approval', successMessage);
      emit(state.copyWith(status: GrantAccessStatus.done));
    } on ApprovalException catch (e) {
      AppLogger.w('Approval', 'grant access failed: ${e.kind.name}');
      emit(state.copyWith(status: GrantAccessStatus.error, error: e.kind));
    } catch (e, s) {
      AppLogger.e(
        'Approval',
        'grant access failed unexpectedly',
        error: e,
        stackTrace: s,
      );
      emit(
        state.copyWith(
          status: GrantAccessStatus.error,
          error: ApprovalErrorKind.unknown,
        ),
      );
    }
  }

  /// Reports the vault is locked so the envelope cannot be produced.
  void reportVaultLocked() {
    emit(
      state.copyWith(
        status: GrantAccessStatus.error,
        error: ApprovalErrorKind.vaultLocked,
      ),
    );
  }

  void acknowledgeError() {
    if (state.error == null) return;
    emit(state.copyWith(clearError: true, status: GrantAccessStatus.idle));
  }
}
