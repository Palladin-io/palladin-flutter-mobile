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
  MethodChannelAutoFillCacheBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'io.palladin.mobile/autofill';
  final MethodChannel _channel;

  @override
  Future<int> beginCacheSession() async {
    final token = await _channel.invokeMethod<int>('beginCacheSession');
    if (token == null) throw const FormatException('Missing session token');
    return token;
  }

  @override
  Future<void> replaceCache(
    AutoFillCachePayload payload, {
    required int sessionToken,
  }) => _channel.invokeMethod<void>('replaceCache', {
    'sessionToken': sessionToken,
    'payload': payload.toPlatformMap(),
  });

  @override
  Future<int> revokeCacheAccess() async {
    final token = await _channel.invokeMethod<int>('revokeCacheAccess');
    if (token == null) throw const FormatException('Missing cleanup token');
    return token;
  }

  @override
  Future<void> clearCache({required int sessionToken}) =>
      _channel.invokeMethod<void>('clearCache', {'sessionToken': sessionToken});
}
