import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/app_logger.dart';
import '../../domain/entities/notification_preference.dart';
import '../../domain/exceptions/notification_center_exceptions.dart';
import '../../domain/repositories/notification_center_repository.dart';

enum NotificationPreferencesStatus { initial, loading, loaded, error }

class NotificationPreferencesState {
  const NotificationPreferencesState({
    this.status = NotificationPreferencesStatus.initial,
    this.items = const [],
    this.savingKeys = const {},
    this.error,
  });

  final NotificationPreferencesStatus status;
  final List<NotificationPreference> items;

  /// `${type}:${channel.name}` keys currently being persisted — used to show a
  /// per-row spinner / disable a toggle mid-flight.
  final Set<String> savingKeys;
  final NotificationCenterErrorKind? error;

  NotificationPreferencesState copyWith({
    NotificationPreferencesStatus? status,
    List<NotificationPreference>? items,
    Set<String>? savingKeys,
    NotificationCenterErrorKind? error,
    bool clearError = false,
  }) {
    return NotificationPreferencesState(
      status: status ?? this.status,
      items: items ?? this.items,
      savingKeys: savingKeys ?? this.savingKeys,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Drives the per-type × per-channel preferences screen. Factory-scoped per
/// page mount. Toggles are optimistic and roll back on failure; mandatory
/// inbox/realtime changes are blocked client-side (defense-in-depth — the
/// backend ignores them too).
class NotificationPreferencesCubit extends Cubit<NotificationPreferencesState> {
  NotificationPreferencesCubit({required this.repository})
    : super(const NotificationPreferencesState());

  final NotificationCenterRepository repository;

  Future<void> load() async {
    emit(
      state.copyWith(
        status: NotificationPreferencesStatus.loading,
        clearError: true,
      ),
    );
    try {
      final items = await repository.preferences();
      emit(
        state.copyWith(
          status: NotificationPreferencesStatus.loaded,
          items: items,
        ),
      );
    } on NotificationCenterException catch (error) {
      emit(
        state.copyWith(
          status: NotificationPreferencesStatus.error,
          error: error.kind,
        ),
      );
    } catch (error, stackTrace) {
      AppLogger.e(
        'Notifications',
        'Preferences load failed unexpectedly',
        error: error,
        stackTrace: stackTrace,
      );
      emit(
        state.copyWith(
          status: NotificationPreferencesStatus.error,
          error: NotificationCenterErrorKind.unknown,
        ),
      );
    }
  }

  /// Optimistically flips one channel for [type], persists, and reconciles
  /// against the effective state the backend returns. Mandatory inbox/realtime
  /// rows are locked — the call is a no-op for them.
  Future<void> toggle({
    required String type,
    required NotificationChannel channel,
    required bool value,
  }) async {
    final index = state.items.indexWhere((item) => item.type == type);
    if (index < 0) return;
    final current = state.items[index];
    if (current.mandatory && channel != NotificationChannel.push) return;

    final key = '$type:${channel.name}';
    if (state.savingKeys.contains(key)) return;

    final previous = state;
    final optimistic = [...state.items];
    final next = switch (channel) {
      NotificationChannel.inbox => current.copyWith(inboxEnabled: value),
      NotificationChannel.realtime => current.copyWith(signalREnabled: value),
      NotificationChannel.push => current.copyWith(pushEnabled: value),
    };
    optimistic[index] = next;
    emit(
      state.copyWith(
        items: optimistic,
        savingKeys: {...state.savingKeys, key},
        clearError: true,
      ),
    );

    try {
      // Send the FULL channel triple for the type, not just the toggled one.
      // The backend stores non-nullable booleans, so a partial payload would
      // zero the omitted channels — disabling one channel must not disable the
      // others.
      final effective = await repository.updatePreference(
        type: type,
        inboxEnabled: next.inboxEnabled,
        signalREnabled: next.signalREnabled,
        pushEnabled: next.pushEnabled,
      );
      emit(
        state.copyWith(
          items: _merge(state.items, effective),
          savingKeys: {...state.savingKeys}..remove(key),
        ),
      );
    } catch (error) {
      AppLogger.w('Notifications', 'Preference update failed: $error');
      emit(
        previous.copyWith(
          error: NotificationCenterErrorKind.unknown,
        ),
      );
    }
  }

  void acknowledgeError() {
    if (state.error == null) return;
    emit(state.copyWith(clearError: true));
  }

  /// Replaces any preference the server echoed back, keeping the rest in place
  /// and preserving the original list order.
  List<NotificationPreference> _merge(
    List<NotificationPreference> existing,
    List<NotificationPreference> effective,
  ) {
    if (effective.isEmpty) return existing;
    final byType = {for (final pref in effective) pref.type: pref};
    return [
      for (final item in existing) byType[item.type] ?? item,
    ];
  }
}
