import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/autofill_provider_bridge.dart';

sealed class AutoFillSetupState {
  const AutoFillSetupState();
}

final class AutoFillSetupLoading extends AutoFillSetupState {
  const AutoFillSetupLoading();
}

final class AutoFillSetupLoaded extends AutoFillSetupState {
  const AutoFillSetupLoaded(
    this.status, {
    this.chromeStatus = ChromeAutoFillStatus.unavailable,
    this.chromeSettingsFailed = false,
  });
  final AutoFillProviderStatus status;
  final ChromeAutoFillStatus chromeStatus;
  final bool chromeSettingsFailed;
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
      final chromeStatus = defaultTargetPlatform == TargetPlatform.android
          ? await _bridge.chromeStatus()
          : ChromeAutoFillStatus.unavailable;
      if (!isClosed && revision == _revision) {
        emit(AutoFillSetupLoaded(status, chromeStatus: chromeStatus));
      }
    } catch (_) {
      if (!isClosed && revision == _revision) emit(const AutoFillSetupError());
    }
  }

  Future<void> openChromeSettings() async {
    if (_opening) return;
    _opening = true;
    try {
      await _bridge.openChromeSettings();
      await refresh();
    } catch (_) {
      final current = state;
      if (!isClosed && current is AutoFillSetupLoaded) {
        emit(
          AutoFillSetupLoaded(
            current.status,
            chromeStatus: current.chromeStatus,
            chromeSettingsFailed: true,
          ),
        );
      }
    } finally {
      _opening = false;
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
