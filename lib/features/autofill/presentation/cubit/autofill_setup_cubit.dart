import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/autofill_provider_bridge.dart';

sealed class AutoFillSetupState {
  const AutoFillSetupState();
}

final class AutoFillSetupLoading extends AutoFillSetupState {
  const AutoFillSetupLoading();
}

final class AutoFillSetupLoaded extends AutoFillSetupState {
  const AutoFillSetupLoaded(this.status);
  final AutoFillProviderStatus status;
}

final class AutoFillSetupError extends AutoFillSetupState {
  const AutoFillSetupError();
}

class AutoFillSetupCubit extends Cubit<AutoFillSetupState> {
  AutoFillSetupCubit(this._bridge) : super(const AutoFillSetupLoading());
  final AutoFillProviderBridge _bridge;
  int _revision = 0;
  bool _opening = false;

  Future<void> refresh() async {
    final revision = ++_revision;
    try {
      final status = await _bridge.status();
      if (!isClosed && revision == _revision) emit(AutoFillSetupLoaded(status));
    } catch (_) {
      if (!isClosed && revision == _revision) emit(const AutoFillSetupError());
    }
  }

  Future<void> openSettings() async {
    if (_opening) return;
    _opening = true;
    try {
      await _bridge.openSettings();
      // Opening settings is not consent; only an OS status check can confirm it.
      await refresh();
    } catch (_) {
      if (!isClosed) emit(const AutoFillSetupError());
    } finally {
      _opening = false;
    }
  }
}
