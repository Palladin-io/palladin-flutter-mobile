import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';

import '../domain/autofill_record.dart';

abstract interface class AutoFillCacheBridge {
  Future<int> beginCacheSession();

  Future<void> replaceCache(
    AutoFillCachePayload payload, {
    required int sessionToken,
  });

  Future<int> revokeCacheAccess();

  Future<void> clearCache({required int sessionToken});
}

class MethodChannelAutoFillCacheBridge implements AutoFillCacheBridge {
  MethodChannelAutoFillCacheBridge({
    MethodChannel? channel,
    Future<bool> Function()? availabilityProbe,
  }) : _channel = channel ?? const MethodChannel(_channelName),
       _availabilityProbe = availabilityProbe ?? _isSupportedDevice;

  static const _channelName = 'io.palladin.mobile/autofill';
  final MethodChannel _channel;
  final Future<bool> Function() _availabilityProbe;
  Future<bool>? _availability;

  @override
  Future<int> beginCacheSession() async {
    final token = await _invokeMethod<int>('beginCacheSession');
    if (token == null) throw const FormatException('Missing session token');
    return token;
  }

  @override
  Future<void> replaceCache(
    AutoFillCachePayload payload, {
    required int sessionToken,
  }) async {
    await _invokeMethod<void>('replaceCache', {
      'sessionToken': sessionToken,
      'payload': payload.toPlatformMap(),
    });
  }

  @override
  Future<int> revokeCacheAccess() async {
    final token = await _invokeMethod<int>('revokeCacheAccess');
    if (token == null) throw const FormatException('Missing cleanup token');
    return token;
  }

  @override
  Future<void> clearCache({required int sessionToken}) async {
    await _invokeMethod<void>('clearCache', {'sessionToken': sessionToken});
  }

  Future<T?> _invokeMethod<T>(String method, [Object? arguments]) async {
    await _ensureAvailable();
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      // [_ensureAvailable] is the only authority that may classify a host as
      // unsupported. Once it confirms a supported device, a missing channel
      // handler is an embedding failure and must keep mutations fail closed.
      throw PlatformException(code: 'AUTOFILL_BRIDGE_MISSING');
    }
  }

  Future<void> _ensureAvailable() async {
    final available = await (_availability ??= _probeAvailability());
    if (!available) {
      throw MissingPluginException(
        'AutoFill credential-provider cache is unavailable on this device',
      );
    }
  }

  Future<bool> _probeAvailability() async {
    try {
      return await _availabilityProbe();
    } on MissingPluginException {
      // A missing device-info handler on a supported build is an embedding
      // failure, not evidence that this is an intentionally unsupported host.
      throw PlatformException(code: 'AUTOFILL_AVAILABILITY_UNAVAILABLE');
    }
  }

  static Future<bool> _isSupportedDevice() async {
    if (!Platform.isIOS) return true;
    final iosInfo = await DeviceInfoPlugin().iosInfo;
    return iosInfo.isPhysicalDevice;
  }
}
