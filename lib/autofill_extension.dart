import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'features/autofill/data/ios_member_source_runtime.dart';

/// Dedicated credential-extension entrypoint: no app/account/network bootstrap.
@pragma('vm:entry-point')
void autoFillExtensionMain() {
  WidgetsFlutterBinding.ensureInitialized();
  final bridge = _AutoFillExtensionBridge();
  bridge.install();
}

final class _AutoFillExtensionBridge {
  static const _channel = MethodChannel(
    'io.palladin.mobile/autofill-extension',
  );
  IosMemberSourceRuntime? _runtime;
  Future<IosMemberSourceRuntime>? _opening;
  var _generation = 0;
  var _closed = false;

  void install() {
    _channel.setMethodCallHandler(_handle);
    unawaited(_channel.invokeMethod<void>('ready'));
  }

  Future<Object?> _handle(MethodCall call) async {
    try {
      switch (call.method) {
        case 'open':
          if (_closed || _runtime != null || _opening != null) {
            throw const IosMemberSourceException(
              IosMemberSourceFailure.invalidated,
            );
          }
          final generation = _generation;
          final opening = IosMemberSourceRuntime.open(
            arguments: Map<dynamic, dynamic>.from(call.arguments as Map),
            validateNative: () async {
              if (_closed || generation != _generation) return false;
              final accepted = await _channel.invokeMethod<bool>(
                'validateSource',
              );
              return accepted == true && !_closed && generation == _generation;
            },
            completeNative: (value) async {
              if (_closed || generation != _generation) {
                throw const IosMemberSourceException(
                  IosMemberSourceFailure.invalidated,
                );
              }
              final accepted = await _channel.invokeMethod<bool>(
                'complete',
                value,
              );
              if (accepted != true) {
                throw const IosMemberSourceException(
                  IosMemberSourceFailure.invalidated,
                );
              }
            },
          );
          _opening = opening;
          final runtime = await opening;
          _runtime = runtime;
          if (_closed || generation != _generation) {
            await runtime.close();
            throw const IosMemberSourceException(
              IosMemberSourceFailure.invalidated,
            );
          }
          return await runtime.session.candidates();
        case 'select':
          final runtime = _runtime;
          if (_closed || runtime == null) {
            throw const IosMemberSourceException(
              IosMemberSourceFailure.invalidated,
            );
          }
          final arguments = call.arguments as Map;
          try {
            await runtime.session.select(
              selectionId: arguments['selectionId'] as String,
              selectedHost: arguments['selectedHost'] as String,
              manualConfirmed: arguments['manualConfirmed'] as bool,
            );
            return true;
          } finally {
            await runtime.close();
          }
        case 'close':
          _closed = true;
          _generation++;
          try {
            final opening = _opening;
            if (opening != null) await opening;
          } catch (_) {
            // The opening operation owns its failed-attempt cleanup.
          }
          await _runtime?.close();
          return null;
        default:
          throw MissingPluginException();
      }
    } catch (_) {
      await _runtime?.close();
      // Never forward exception strings, stack traces, account fields or keys.
      throw PlatformException(code: 'AUTOFILL_SOURCE_UNAVAILABLE');
    } finally {
      if (call.method == 'open' && call.arguments is Map) {
        final arguments = call.arguments as Map;
        final key = arguments.remove('masterKey');
        if (key is Uint8List) key.fillRange(0, key.length, 0);
        arguments.remove('masterPassword');
      }
    }
  }
}
