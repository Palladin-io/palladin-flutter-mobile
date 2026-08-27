import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/app_logger.dart';
import '../../../agents/domain/repositories/agents_repository.dart';
import '../../../grants/domain/entities/grant_method.dart';
import '../../domain/exceptions/approval_exceptions.dart';
import '../../domain/repositories/approval_repository.dart';

export '../../domain/repositories/approval_repository.dart'
    show GrantLimit, GrantExpiry, GrantUseLimit, GrantLifetime;

/// Closed, mode-specific inputs for a re-grant. Invalid FULL/Entry
/// combinations are not representable at the DI boundary.
sealed class RegrantArgs {
  const RegrantArgs({required this.vaultId, required this.agentId});

  final String vaultId;
  final String agentId;
}

final class FullRegrantArgs extends RegrantArgs {
  const FullRegrantArgs({required super.vaultId, required super.agentId});
}

final class GranularRegrantArgs extends RegrantArgs {
  const GranularRegrantArgs({
    required super.vaultId,
    required super.agentId,
    required this.entryId,
  });

  final String entryId;
}

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
abstract class RegrantCubit extends Cubit<RegrantState> {
  RegrantCubit({
    required this.repository,
    required this.agentsRepository,
    required this.vaultId,
    required this.agentId,
  }) : super(const RegrantState());

  final ApprovalRepository repository;
  final AgentsRepository agentsRepository;
  final String vaultId;
  final String agentId;

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
      final agent = await agentsRepository.getAgent(agentId);
      await _createGrant(
        agentPublicKey: agent.publicKey,
        recipientKeyVersion: agent.recipientKeyVersion,
        agentAccessEpoch: agent.accessEpoch,
        privateKey: privateKey,
        limit: limit,
        methods: methods,
      );
      AppLogger.i('Approval', 'Re-granted agent $agentId');
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

  Future<void> _createGrant({
    required String agentPublicKey,
    required int recipientKeyVersion,
    required int agentAccessEpoch,
    required Uint8List privateKey,
    required GrantLimit limit,
    required List<GrantMethod> methods,
  });
}

final class FullRegrantCubit extends RegrantCubit {
  FullRegrantCubit({
    required super.repository,
    required super.agentsRepository,
    required super.vaultId,
    required super.agentId,
  });

  @override
  Future<void> _createGrant({
    required String agentPublicKey,
    required int recipientKeyVersion,
    required int agentAccessEpoch,
    required Uint8List privateKey,
    required GrantLimit limit,
    required List<GrantMethod> methods,
  }) => repository.createFullGrant(
    vaultId: vaultId,
    agentId: agentId,
    agentPublicKey: agentPublicKey,
    recipientKeyVersion: recipientKeyVersion,
    agentAccessEpoch: agentAccessEpoch,
    privateKey: privateKey,
    limit: limit,
    methods: methods,
  );
}

final class GranularRegrantCubit extends RegrantCubit {
  GranularRegrantCubit({
    required super.repository,
    required super.agentsRepository,
    required super.vaultId,
    required super.agentId,
    required this.entryId,
  });

  final String entryId;

  @override
  Future<void> _createGrant({
    required String agentPublicKey,
    required int recipientKeyVersion,
    required int agentAccessEpoch,
    required Uint8List privateKey,
    required GrantLimit limit,
    required List<GrantMethod> methods,
  }) => repository.createGranularGrant(
    vaultId: vaultId,
    entryId: entryId,
    agentId: agentId,
    agentPublicKey: agentPublicKey,
    recipientKeyVersion: recipientKeyVersion,
    agentAccessEpoch: agentAccessEpoch,
    privateKey: privateKey,
    limit: limit,
    methods: methods,
  );
}
