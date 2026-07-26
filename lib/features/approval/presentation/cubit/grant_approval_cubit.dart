import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/app_logger.dart';
import '../../../grants/domain/entities/grant_method.dart';
import '../../domain/entities/pending_grant.dart';
import '../../domain/exceptions/approval_exceptions.dart';
import '../../domain/repositories/approval_repository.dart';
import '../../data/services/grant_approval_review_service.dart';

export '../../../grants/domain/entities/grant_method.dart' show GrantMethod;
export '../../domain/entities/pending_grant.dart';
export '../../domain/repositories/approval_repository.dart'
    show GrantLimit, GrantExpiry, GrantUseLimit, GrantLifetime;

enum GrantApprovalStatus { idle, reviewing, ready, submitting, done, error }

/// State for the approve/deny screen of a single pending grant.
class GrantApprovalState {
  const GrantApprovalState({
    this.status = GrantApprovalStatus.idle,
    this.error,
    this.review,
  });

  final GrantApprovalStatus status;
  final ApprovalErrorKind? error;
  final GrantApprovalReview? review;

  bool get isSubmitting => status == GrantApprovalStatus.submitting;

  GrantApprovalState copyWith({
    GrantApprovalStatus? status,
    ApprovalErrorKind? error,
    bool clearError = false,
    GrantApprovalReview? review,
    bool clearReview = false,
  }) {
    return GrantApprovalState(
      status: status ?? this.status,
      error: clearError ? null : (error ?? this.error),
      review: clearReview ? null : (review ?? this.review),
    );
  }
}

/// Drives approve / deny for one pending grant. Factory-scoped per page
/// mount (see DI) so transient submit state never leaks.
///
/// The owner's [privateKey] (in-memory, from the unlocked auth state) is
/// passed in at call time — the cubit never stores it.
class GrantApprovalCubit extends Cubit<GrantApprovalState> {
  GrantApprovalCubit({
    required this.repository,
    this.reviewService,
    required this.grant,
  }) : super(const GrantApprovalState());

  final ApprovalRepository repository;
  final GrantApprovalReviewer? reviewService;
  final PendingGrant grant;

  Future<void> loadReview(Uint8List privateKey) async {
    clearReview();
    emit(
      state.copyWith(status: GrantApprovalStatus.reviewing, clearError: true),
    );
    final keyCopy = Uint8List.fromList(privateKey);
    try {
      final service = reviewService;
      if (service == null) throw StateError('Approval review unavailable');
      final review = await service.open(
        grant: grant,
        memberPrivateKey: keyCopy,
      );
      emit(state.copyWith(status: GrantApprovalStatus.ready, review: review));
    } catch (_) {
      clearReview();
      emit(
        state.copyWith(
          status: GrantApprovalStatus.error,
          error: ApprovalErrorKind.cryptoFailure,
        ),
      );
    } finally {
      keyCopy.fillRange(0, keyCopy.length, 0);
    }
  }

  void clearReview() {
    state.review?.clear();
    if (state.review != null) emit(state.copyWith(clearReview: true));
  }

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
    required List<String> fieldIds,
    required String reviewedEntryRevision,
  }) async {
    emit(
      state.copyWith(status: GrantApprovalStatus.submitting, clearError: true),
    );
    final keyCopy = Uint8List.fromList(privateKey);
    try {
      await repository.approveGrant(
        grant: grant,
        privateKey: keyCopy,
        limit: limit,
        methods: methods,
        fieldIds: fieldIds,
        reviewedEntryRevision: reviewedEntryRevision,
      );
      AppLogger.i('Approval', 'Grant approved');
      emit(state.copyWith(status: GrantApprovalStatus.done));
    } on ApprovalException catch (e) {
      if (e.kind == ApprovalErrorKind.conflict) clearReview();
      AppLogger.w('Approval', 'approve failed: ${e.kind.name}');
      emit(state.copyWith(status: GrantApprovalStatus.error, error: e.kind));
    } catch (_) {
      AppLogger.w('Approval', 'approve failed unexpectedly');
      emit(
        state.copyWith(
          status: GrantApprovalStatus.error,
          error: ApprovalErrorKind.unknown,
        ),
      );
    } finally {
      keyCopy.fillRange(0, keyCopy.length, 0);
    }
  }

  /// Reports that the vault is locked so the envelope cannot be produced —
  /// surfaces a typed error without attempting the call.
  void reportVaultLocked() {
    emit(
      state.copyWith(
        status: GrantApprovalStatus.error,
        error: ApprovalErrorKind.vaultLocked,
      ),
    );
  }

  /// Denies without decrypting or transmitting any secret/reason material.
  Future<void> deny() async {
    emit(
      state.copyWith(status: GrantApprovalStatus.submitting, clearError: true),
    );
    try {
      await repository.denyGrant(grant: grant);
      AppLogger.i('Approval', 'Grant denied');
      emit(state.copyWith(status: GrantApprovalStatus.done));
    } on ApprovalException catch (e) {
      AppLogger.w('Approval', 'deny failed: ${e.kind.name}');
      emit(state.copyWith(status: GrantApprovalStatus.error, error: e.kind));
    } catch (_) {
      AppLogger.w('Approval', 'deny failed unexpectedly');
      emit(
        state.copyWith(
          status: GrantApprovalStatus.error,
          error: ApprovalErrorKind.unknown,
        ),
      );
    }
  }

  void acknowledgeError() {
    if (state.error == null) return;
    emit(state.copyWith(clearError: true, status: GrantApprovalStatus.idle));
  }

  @override
  Future<void> close() {
    state.review?.clear();
    return super.close();
  }
}
