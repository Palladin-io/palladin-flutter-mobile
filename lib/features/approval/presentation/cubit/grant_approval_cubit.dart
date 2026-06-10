import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/app_logger.dart';
import '../../../grants/domain/entities/grant_method.dart';
import '../../domain/entities/pending_grant.dart';
import '../../domain/exceptions/approval_exceptions.dart';
import '../../domain/repositories/approval_repository.dart';

export '../../../grants/domain/entities/grant_method.dart' show GrantMethod;
export '../../domain/entities/pending_grant.dart';
export '../../domain/repositories/approval_repository.dart'
    show GrantLimit, GrantExpiry, GrantUseLimit, GrantLifetime;

enum GrantApprovalStatus { idle, submitting, done, error }

/// State for the approve/deny screen of a single pending grant.
class GrantApprovalState {
  const GrantApprovalState({
    this.status = GrantApprovalStatus.idle,
    this.error,
  });

  final GrantApprovalStatus status;
  final ApprovalErrorKind? error;

  bool get isSubmitting => status == GrantApprovalStatus.submitting;

  GrantApprovalState copyWith({
    GrantApprovalStatus? status,
    ApprovalErrorKind? error,
    bool clearError = false,
  }) {
    return GrantApprovalState(
      status: status ?? this.status,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Drives approve / deny for one pending grant. Factory-scoped per page
/// mount (see DI) so transient submit state never leaks.
///
/// The owner's [privateKey] (in-memory, from the unlocked auth state) is
/// passed in at call time — the cubit never stores it.
class GrantApprovalCubit extends Cubit<GrantApprovalState> {
  GrantApprovalCubit({required this.repository, required this.grant})
      : super(const GrantApprovalState());

  final ApprovalRepository repository;
  final PendingGrant grant;

  /// Approves the grant with the chosen [limit] (exactly one of
  /// expiry/use-count — enforced by the [GrantLimit] sealed type).
  ///
  /// [privateKey] must be the owner's X25519 private key from the
  /// unlocked auth state; when the vault is locked the caller should not
  /// invoke this (pass a non-null key only). Flips to [GrantApprovalStatus.done]
  /// on success so the page can pop and the inbox can drop the grant.
  Future<void> approve({
    required Uint8List privateKey,
    required GrantLimit limit,
    required List<GrantMethod> methods,
  }) async {
    emit(state.copyWith(
        status: GrantApprovalStatus.submitting, clearError: true));
    try {
      await repository.approveGrant(
        grant: grant,
        privateKey: privateKey,
        limit: limit,
        methods: methods,
      );
      AppLogger.i('Approval', 'Grant approved: ${grant.grantId}');
      emit(state.copyWith(status: GrantApprovalStatus.done));
    } on ApprovalException catch (e) {
      AppLogger.w('Approval', 'approve failed: ${e.kind.name}');
      emit(state.copyWith(status: GrantApprovalStatus.error, error: e.kind));
    } catch (e, s) {
      AppLogger.e('Approval', 'approve failed unexpectedly',
          error: e, stackTrace: s);
      emit(state.copyWith(
        status: GrantApprovalStatus.error,
        error: ApprovalErrorKind.unknown,
      ));
    }
  }

  /// Reports that the vault is locked so the envelope cannot be produced —
  /// surfaces a typed error without attempting the call.
  void reportVaultLocked() {
    emit(state.copyWith(
      status: GrantApprovalStatus.error,
      error: ApprovalErrorKind.vaultLocked,
    ));
  }

  /// Denies the grant with an optional [reason].
  Future<void> deny({String? reason}) async {
    emit(state.copyWith(
        status: GrantApprovalStatus.submitting, clearError: true));
    try {
      await repository.denyGrant(grant: grant, reason: reason);
      AppLogger.i('Approval', 'Grant denied: ${grant.grantId}');
      emit(state.copyWith(status: GrantApprovalStatus.done));
    } on ApprovalException catch (e) {
      AppLogger.w('Approval', 'deny failed: ${e.kind.name}');
      emit(state.copyWith(status: GrantApprovalStatus.error, error: e.kind));
    } catch (e, s) {
      AppLogger.e('Approval', 'deny failed unexpectedly',
          error: e, stackTrace: s);
      emit(state.copyWith(
        status: GrantApprovalStatus.error,
        error: ApprovalErrorKind.unknown,
      ));
    }
  }

  void acknowledgeError() {
    if (state.error == null) return;
    emit(state.copyWith(clearError: true, status: GrantApprovalStatus.idle));
  }
}
