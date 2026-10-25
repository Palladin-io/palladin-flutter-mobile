import 'package:flutter/services.dart';

/// OS selection is independent of cache availability or Vault unlock.
enum AutoFillProviderStatus {
  enabled,
  enabledManual,
  disabled,
  manual,
  unsupported,
}

class AutoFillProviderBridge {
  const AutoFillProviderBridge();

  static const _channel = MethodChannel('io.palladin.mobile/autofill');

  Future<AutoFillProviderStatus> status() async {
    final status = await _channel.invokeMethod<String>('getProviderStatus');
    return switch (status) {
      'enabled' => AutoFillProviderStatus.enabled,
      'enabledManual' => AutoFillProviderStatus.enabledManual,
      'disabled' => AutoFillProviderStatus.disabled,
      'manual' => AutoFillProviderStatus.manual,
      'unsupported' => AutoFillProviderStatus.unsupported,
      _ => throw PlatformException(code: 'AUTOFILL_STATUS_UNAVAILABLE'),
    };
  }

  Future<void> openSettings() =>
      _channel.invokeMethod<void>('openProviderSettings');
}
