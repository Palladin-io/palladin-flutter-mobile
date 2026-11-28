import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Reports unavailable device capabilities without invoking native plugins.
class PreviewBinding extends WidgetsFlutterBinding {
  // This binding is used only by the offline design entrypoint. Browser
  // iframe focus is not a device background event for synthetic fixtures.
  // Product bindings and their plaintext lifecycle protections are unchanged.
  @override
  void handleAppLifecycleStateChanged(AppLifecycleState state) {
    if (lifecycleState != AppLifecycleState.resumed) {
      super.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }
  }

  @override
  BinaryMessenger createBinaryMessenger() =>
      _PreviewMessenger(super.createBinaryMessenger());
}

class _PreviewMessenger implements BinaryMessenger {
  _PreviewMessenger(this.delegate);
  final BinaryMessenger delegate;

  @override
  Future<ByteData?>? send(String channel, ByteData? message) {
    if (channel == 'io.palladin.mobile/autofill') {
      const codec = StandardMethodCodec();
      final call = codec.decodeMethodCall(message);
      return Future.value(switch (call.method) {
        'getProviderStatus' => codec.encodeSuccessEnvelope('unsupported'),
        'getChromeAutofillStatus' => codec.encodeSuccessEnvelope('unavailable'),
        _ => codec.encodeErrorEnvelope(code: 'PREVIEW_DEVICE_UNAVAILABLE'),
      });
    }
    return delegate.send(channel, message);
  }

  @override
  void setMessageHandler(String channel, MessageHandler? handler) =>
      delegate.setMessageHandler(channel, handler);

  @override
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    PlatformMessageResponseCallback? callback,
  ) => Future<void>.sync(
    () => ServicesBinding.instance.channelBuffers.push(
      channel,
      data,
      callback ?? (_) {},
    ),
  );
}
