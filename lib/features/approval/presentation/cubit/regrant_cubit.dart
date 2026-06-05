import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/app_logger.dart';
import '../../domain/exceptions/approval_exceptions.dart';
import '../../domain/repositories/approval_repository.dart';

export '../../domain/repositories/approval_repository.dart'
    show GrantLimit, GrantExpiry, GrantUseLimit, GrantLifetime;

/// Identifiers a re-grant ("Grant again") needs — built from the terminal
/// grant being re-issued. Passed as the DI factory param.
typedef RegrantArgs = ({
  String vaultId,
  String agentId,
  String agentPublicKey,
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
  RegrantCubit({required this.repository, required this.args})
      : super(const RegrantState());

  final ApprovalRepository repository;
  final RegrantArgs args;

  Future<void> submit({
    required Uint8List privateKey,
    required GrantLimit limit,
  }) async {
    emit(state.copyWith(status: RegrantStatus.submitting, clearError: true));
    try {
      await repository.createGrant(
        vaultId: args.vaultId,
        agentId: args.agentId,
        agentPublicKey: args.agentPublicKey,
        isFull: args.isFull,
        entryId: args.entryId,
        privateKey: privateKey,
        limit: limit,
      );
      AppLogger.i('Approval', 'Re-granted agent ${args.agentId}');
      emit(state.copyWith(status: RegrantStatus.done));
    } on ApprovalException catch (e) {
      AppLogger.w('Approval', 're-grant failed: ${e.kind.name}');
      emit(state.copyWith(status: RegrantStatus.error, error: e.kind));
    } catch (e, s) {
      AppLogger.e('Approval', 're-grant failed unexpectedly',
          error: e, stackTrace: s);
      emit(state.copyWith(
        status: RegrantStatus.error,
        error: ApprovalErrorKind.unknown,
      ));
    }
  }

  /// Reports the vault is locked so the envelope cannot be produced.
  void reportVaultLocked() {
    emit(state.copyWith(
      status: RegrantStatus.error,
      error: ApprovalErrorKind.vaultLocked,
    ));
  }

  void acknowledgeError() {
    if (state.error == null) return;
    emit(state.copyWith(clearError: true, status: RegrantStatus.idle));
  }
}
