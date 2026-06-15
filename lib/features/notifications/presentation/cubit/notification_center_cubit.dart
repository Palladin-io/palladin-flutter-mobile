import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/app_logger.dart';
import '../../domain/entities/inbox_notification.dart';
import '../../domain/exceptions/notification_center_exceptions.dart';
import '../../domain/repositories/notification_center_repository.dart';

enum NotificationCenterStatus { initial, loading, loaded, error }

class NotificationCenterState {
  const NotificationCenterState({
    this.status = NotificationCenterStatus.initial,
    this.items = const [],
    this.unreadCount = 0,
    this.pendingActionCount = 0,
    this.isLoadingMore = false,
    this.isMarkingAllRead = false,
    this.nextCursor,
    this.error,
  });

  final NotificationCenterStatus status;
  final List<InboxNotification> items;
  final int unreadCount;
  final int pendingActionCount;
  final bool isLoadingMore;
  final bool isMarkingAllRead;
  final String? nextCursor;
  final NotificationCenterErrorKind? error;

  NotificationCenterState copyWith({
    NotificationCenterStatus? status,
    List<InboxNotification>? items,
    int? unreadCount,
    int? pendingActionCount,
    bool? isLoadingMore,
    bool? isMarkingAllRead,
    String? nextCursor,
    bool clearCursor = false,
    NotificationCenterErrorKind? error,
    bool clearError = false,
  }) {
    return NotificationCenterState(
      status: status ?? this.status,
      items: items ?? this.items,
      unreadCount: unreadCount ?? this.unreadCount,
      pendingActionCount: pendingActionCount ?? this.pendingActionCount,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isMarkingAllRead: isMarkingAllRead ?? this.isMarkingAllRead,
      nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class NotificationCenterCubit extends Cubit<NotificationCenterState> {
  NotificationCenterCubit({required this.repository})
    : super(const NotificationCenterState());

  final NotificationCenterRepository repository;

  /// Clears user-specific notification titles and metadata on logout.
  void reset() => emit(const NotificationCenterState());

  Future<void> load() async {
    emit(
      state.copyWith(
        status: NotificationCenterStatus.loading,
        clearError: true,
      ),
    );
    try {
      final results = await Future.wait<dynamic>([
        repository.list(),
        repository.summary(),
      ]);
      final page = results[0] as NotificationPage;
      final summary = results[1] as NotificationSummary;
      emit(
        state.copyWith(
          status: NotificationCenterStatus.loaded,
          items: page.items,
          unreadCount: summary.unreadCount,
          pendingActionCount: summary.pendingActionCount,
          nextCursor: page.nextCursor,
          clearCursor: page.nextCursor == null,
        ),
      );
    } on NotificationCenterException catch (error) {
      emit(
        state.copyWith(
          status: NotificationCenterStatus.error,
          error: error.kind,
        ),
      );
    } catch (error, stackTrace) {
      AppLogger.e(
        'Notifications',
        'Inbox load failed unexpectedly',
        error: error,
        stackTrace: stackTrace,
      );
      emit(
        state.copyWith(
          status: NotificationCenterStatus.error,
          error: NotificationCenterErrorKind.unknown,
        ),
      );
    }
  }

  Future<void> refresh() async {
    try {
      final results = await Future.wait<dynamic>([
        repository.list(),
        repository.summary(),
      ]);
      final page = results[0] as NotificationPage;
      final summary = results[1] as NotificationSummary;
      emit(
        state.copyWith(
          status: NotificationCenterStatus.loaded,
          items: page.items,
          unreadCount: summary.unreadCount,
          pendingActionCount: summary.pendingActionCount,
          nextCursor: page.nextCursor,
          clearCursor: page.nextCursor == null,
          clearError: true,
        ),
      );
    } catch (error) {
      AppLogger.w('Notifications', 'Inbox refresh failed (quiet): $error');
    }
  }

  Future<void> refreshSummary() async {
    try {
      final summary = await repository.summary();
      emit(
        state.copyWith(
          unreadCount: summary.unreadCount,
          pendingActionCount: summary.pendingActionCount,
        ),
      );
    } catch (error) {
      AppLogger.w('Notifications', 'Summary refresh failed (quiet): $error');
    }
  }

  Future<void> loadMore() async {
    final cursor = state.nextCursor;
    if (cursor == null || state.isLoadingMore) return;
    emit(state.copyWith(isLoadingMore: true));
    try {
      final page = await repository.list(cursor: cursor);
      emit(
        state.copyWith(
          items: [...state.items, ...page.items],
          nextCursor: page.nextCursor,
          clearCursor: page.nextCursor == null,
          isLoadingMore: false,
        ),
      );
    } catch (error) {
      AppLogger.w('Notifications', 'Inbox pagination failed: $error');
      emit(state.copyWith(isLoadingMore: false));
    }
  }

  Future<void> markRead(String id) async {
    final index = state.items.indexWhere((item) => item.id == id);
    if (index < 0 || state.items[index].isRead) return;
    final previous = state;
    final updated = [...state.items];
    updated[index] = updated[index].copyWith(markRead: true);
    emit(
      state.copyWith(
        items: updated,
        unreadCount: (state.unreadCount - 1).clamp(0, 1 << 31),
      ),
    );
    try {
      await repository.markRead(id);
    } catch (error) {
      emit(previous);
      AppLogger.w('Notifications', 'Mark read failed: $error');
    }
  }

  Future<void> markAllRead() async {
    if (state.unreadCount == 0 || state.isMarkingAllRead) return;
    final previous = state;
    emit(
      state.copyWith(
        items: [for (final item in state.items) item.copyWith(markRead: true)],
        unreadCount: 0,
        isMarkingAllRead: true,
      ),
    );
    try {
      await repository.markAllRead();
      emit(state.copyWith(isMarkingAllRead: false));
    } catch (error) {
      emit(previous);
      AppLogger.w('Notifications', 'Mark all read failed: $error');
    }
  }
}
