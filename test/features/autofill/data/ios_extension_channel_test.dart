import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/autofill_extension.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('io.palladin.mobile/autofill-extension');
  const codec = StandardMethodCodec();

  Future<Object?> invoke(String method, [Object? arguments]) async {
    final response = Completer<ByteData?>();
    binding.channelBuffers.push(
      channel.name,
      codec.encodeMethodCall(MethodCall(method, arguments)),
      response.complete,
    );
    final bytes = await response.future;
    return bytes == null ? null : codec.decodeEnvelope(bytes);
  }

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'close before opening denies request without invoking native auth',
    () async {
      final calls = <String>[];
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call.method);
        return null;
      });
      autoFillExtensionMain();
      await invoke('close');
      await expectLater(
        invoke('open', {'masterKey': Uint8List.fromList(List.filled(32, 7))}),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'AUTOFILL_SOURCE_UNAVAILABLE',
          ),
        ),
      );
      expect(calls, ['ready']);
    },
  );

  test(
    'close during native validation waits for cleanup and never admits metadata',
    () async {
      final validation = Completer<bool>();
      final entered = Completer<void>();
      final calls = <String>[];
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call.method);
        if (call.method == 'validateSource') {
          entered.complete();
          return validation.future;
        }
        return null;
      });
      autoFillExtensionMain();
      final opening = invoke('open', {
        'masterKey': Uint8List.fromList(List.filled(32, 8)),
      });
      final rejected = expectLater(
        opening,
        throwsA(
          isA<PlatformException>().having((e) => e.details, 'details', isNull),
        ),
      );
      await entered.future;
      final closing = invoke('close');
      validation.complete(true);
      await rejected;
      await closing;
      expect(calls, ['ready', 'validateSource']);
      await expectLater(
        invoke('select', {'selectionId': 'late'}),
        throwsA(isA<PlatformException>()),
      );
    },
  );
}
