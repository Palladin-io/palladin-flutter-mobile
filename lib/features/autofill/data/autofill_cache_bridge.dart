import 'package:flutter/services.dart';

import '../domain/autofill_record.dart';

abstract interface class AutoFillCacheBridge {
  Future<void> replaceCache(
    List<AutoFillRecord> records, {
    required int generation,
  });

  Future<void> revokeCacheAccess({required int generation});

  Future<void> clearCache({required int generation});
}

class MethodChannelAutoFillCacheBridge implements AutoFillCacheBridge {
  MethodChannelAutoFillCacheBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'io.palladin.mobile/autofill';
  final MethodChannel _channel;

  @override
  Future<void> replaceCache(
    List<AutoFillRecord> records, {
    required int generation,
  }) => _channel.invokeMethod<void>('replaceCache', {
    'generation': generation,
    'records': records
        .map((record) => record.toPlatformMap())
        .toList(growable: false),
  });

  @override
  Future<void> revokeCacheAccess({required int generation}) => _channel
      .invokeMethod<void>('revokeCacheAccess', {'generation': generation});

  @override
  Future<void> clearCache({required int generation}) =>
      _channel.invokeMethod<void>('clearCache', {'generation': generation});
}
