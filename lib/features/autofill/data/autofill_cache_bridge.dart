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
    await _ensureAvailable();
    final token = await _channel.invokeMethod<int>('beginCacheSession');
    if (token == null) throw const FormatException('Missing session token');
    return token;
  }

  @override
  Future<void> replaceCache(
    AutoFillCachePayload payload, {
    required int sessionToken,
  }) async {
    await _ensureAvailable();
    await _channel.invokeMethod<void>('replaceCache', {
      'sessionToken': sessionToken,
      'payload': payload.toPlatformMap(),
    });
  }

  @override
  Future<int> revokeCacheAccess() async {
    await _ensureAvailable();
    final token = await _channel.invokeMethod<int>('revokeCacheAccess');
    if (token == null) throw const FormatException('Missing cleanup token');
    return token;
  }

  @override
  Future<void> clearCache({required int sessionToken}) async {
    await _ensureAvailable();
    await _channel.invokeMethod<void>('clearCache', {
      'sessionToken': sessionToken,
    });
  }

  Future<void> _ensureAvailable() async {
    final available = await (_availability ??= _availabilityProbe());
    if (!available) {
      throw MissingPluginException(
        'AutoFill credential-provider cache is unavailable on this device',
      );
    }
  }

  static Future<bool> _isSupportedDevice() async {
    if (!Platform.isIOS) return true;
    final iosInfo = await DeviceInfoPlugin().iosInfo;
    return iosInfo.isPhysicalDevice;
  }
}
