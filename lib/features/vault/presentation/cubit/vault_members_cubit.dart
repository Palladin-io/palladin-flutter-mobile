import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/app_logger.dart';
import '../../domain/entities/vault_member.dart';
import '../../domain/repositories/vault_members_repository.dart';

enum VaultMembersStatus { initial, loading, loaded, error }

/// Immutable state for the Vault Members tab.
final class VaultMembersState {
  const VaultMembersState({
    this.status = VaultMembersStatus.initial,
    this.members = const [],
    this.removingMemberId,
    this.error,
    this.removalRequested = false,
  });

  final VaultMembersStatus status;
  final List<VaultMember> members;
  final String? removingMemberId;
  final VaultMembersErrorKind? error;
  final bool removalRequested;

  VaultMembersState copyWith({
    VaultMembersStatus? status,
    List<VaultMember>? members,
    String? removingMemberId,
    bool clearRemoving = false,
    VaultMembersErrorKind? error,
    bool clearError = false,
    bool? removalRequested,
  }) => VaultMembersState(
    status: status ?? this.status,
    members: members ?? this.members,
    removingMemberId: clearRemoving
        ? null
        : (removingMemberId ?? this.removingMemberId),
    error: clearError ? null : (error ?? this.error),
    removalRequested: removalRequested ?? this.removalRequested,
  );
}

/// Loads structural Member status and starts server-owned staged removals.
class VaultMembersCubit extends Cubit<VaultMembersState> {
  VaultMembersCubit({required this.repository, required this.vaultId})
    : super(const VaultMembersState());

  final VaultMembersRepository repository;
  final String vaultId;

  Future<void> load({bool preserveContent = false}) async {
    emit(
      state.copyWith(
        status: preserveContent
            ? VaultMembersStatus.loaded
            : VaultMembersStatus.loading,
        clearError: true,
        removalRequested: false,
      ),
    );
    try {
      final members = await repository.list(vaultId);
      emit(
        state.copyWith(
          status: VaultMembersStatus.loaded,
          members: members,
          clearError: true,
        ),
      );
    } on VaultMembersException catch (error) {
      AppLogger.w(
        'VaultMembers',
        'Member directory failed: ${error.kind.name}',
      );
      emit(state.copyWith(status: VaultMembersStatus.error, error: error.kind));
    }
  }

  Future<void> requestRemoval(VaultMember member) async {
    if (member.removalInProgress || state.removingMemberId != null) return;
    emit(
      state.copyWith(
        removingMemberId: member.id,
        clearError: true,
        removalRequested: false,
      ),
    );
    try {
      await repository.requestRemoval(member.id);
      final members = await repository.list(vaultId);
      emit(
        state.copyWith(
          status: VaultMembersStatus.loaded,
          members: members,
          clearRemoving: true,
          removalRequested: true,
        ),
      );
    } on VaultMembersException catch (error) {
      AppLogger.w('VaultMembers', 'Member removal failed: ${error.kind.name}');
      emit(
        state.copyWith(
          status: VaultMembersStatus.loaded,
          clearRemoving: true,
          error: error.kind,
        ),
      );
    }
  }
}
