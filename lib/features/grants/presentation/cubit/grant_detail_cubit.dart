import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/app_logger.dart';
import '../../domain/entities/grant.dart';
import '../../domain/exceptions/grants_exceptions.dart';
import '../../domain/repositories/grants_repository.dart';

export '../../domain/entities/grant.dart';

/// Load + mutation status of the grant detail screen.
enum GrantDetailStatus { initial, loading, loaded, error }

/// Immutable state for the grant detail screen.
class GrantDetailState {
  const GrantDetailState({
    this.status = GrantDetailStatus.initial,
    this.grant,
    this.error,
    this.isRevoking = false,
    this.mutationError,
    this.revoked = false,
  });

  final GrantDetailStatus status;
  final Grant? grant;
  final GrantsErrorKind? error;

  /// `true` while a revoke is in flight.
  final bool isRevoking;

  /// Transient revoke error — shown as a snackbar.
  final GrantsErrorKind? mutationError;

  /// Flips to `true` after a successful revoke so the page can pop.
  final bool revoked;

  GrantDetailState copyWith({
    GrantDetailStatus? status,
    Grant? grant,
    GrantsErrorKind? error,
    bool clearError = false,
    bool? isRevoking,
    GrantsErrorKind? mutationError,
    bool clearMutationError = false,
    bool? revoked,
  }) {
    return GrantDetailState(
      status: status ?? this.status,
      grant: grant ?? this.grant,
      error: clearError ? null : (error ?? this.error),
      isRevoking: isRevoking ?? this.isRevoking,
      mutationError:
          clearMutationError ? null : (mutationError ?? this.mutationError),
      revoked: revoked ?? this.revoked,
    );
  }
}

/// Drives the grant detail screen — loads a single grant and handles
/// revoke. Factory-scoped per page mount (see DI).
class GrantDetailCubit extends Cubit<GrantDetailState> {
  GrantDetailCubit({
    required this.repository,
    required this.vaultId,
    required this.grantId,
  }) : super(const GrantDetailState());

  final GrantsRepository repository;
  final String vaultId;
  final String grantId;

  Future<void> load() async {
    emit(state.copyWith(status: GrantDetailStatus.loading, clearError: true));
    try {
      final grant = await repository.getGrant(vaultId, grantId);
      emit(state.copyWith(status: GrantDetailStatus.loaded, grant: grant));
    } on GrantsException catch (e) {
      AppLogger.w('Grants', 'getGrant failed: ${e.kind.name}');
      emit(state.copyWith(status: GrantDetailStatus.error, error: e.kind));
    } catch (e, s) {
      AppLogger.e('Grants', 'getGrant failed unexpectedly',
          error: e, stackTrace: s);
      emit(state.copyWith(
        status: GrantDetailStatus.error,
        error: GrantsErrorKind.unknown,
      ));
    }
  }

  /// Revokes the grant. On success flips [GrantDetailState.revoked] so the
  /// page can pop back to the list.
  Future<void> revoke({String? reason}) async {
    emit(state.copyWith(isRevoking: true, clearMutationError: true));
    try {
      await repository.revokeGrant(vaultId, grantId, reason: reason);
      emit(state.copyWith(isRevoking: false, revoked: true));
    } on GrantsException catch (e) {
      AppLogger.w('Grants', 'revoke failed: ${e.kind.name}');
      emit(state.copyWith(isRevoking: false, mutationError: e.kind));
    } catch (e, s) {
      AppLogger.e('Grants', 'revoke failed unexpectedly',
          error: e, stackTrace: s);
      emit(state.copyWith(
        isRevoking: false,
        mutationError: GrantsErrorKind.unknown,
      ));
    }
  }

  void acknowledgeMutationError() {
    if (state.mutationError == null) return;
    emit(state.copyWith(clearMutationError: true));
  }
}
