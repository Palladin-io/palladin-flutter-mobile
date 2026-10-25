import 'package:flutter/services.dart';

/// OS selection is independent of cache availability or Vault unlock.
enum AutoFillProviderStatus {
  enabled,
  enabledManual,
  disabled,
  manual,
  unsupported,
}

enum ChromeAutoFillStatus { enabled, disabled, unavailable, unknown }

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

  Future<ChromeAutoFillStatus> chromeStatus() async {
    try {
      final status = await _channel.invokeMethod<String>(
        'getChromeAutofillStatus',
      );
      return switch (status) {
        'enabled' => ChromeAutoFillStatus.enabled,
        'disabled' => ChromeAutoFillStatus.disabled,
        'unavailable' => ChromeAutoFillStatus.unavailable,
        _ => ChromeAutoFillStatus.unknown,
      };
    } on PlatformException {
      return ChromeAutoFillStatus.unknown;
    } on MissingPluginException {
      return ChromeAutoFillStatus.unavailable;
    }
  }

  Future<void> openChromeSettings() =>
      _channel.invokeMethod<void>('openChromeAutofillSettings');

  Future<void> openSettings() =>
      _channel.invokeMethod<void>('openProviderSettings');
}
