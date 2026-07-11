import 'package:flutter/services.dart';

import '../domain/autofill_record.dart';

abstract interface class AutoFillCacheBridge {
  Future<void> replaceCache(List<AutoFillRecord> records);

  Future<void> clearCache();
}

class MethodChannelAutoFillCacheBridge implements AutoFillCacheBridge {
  MethodChannelAutoFillCacheBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'io.palladin.mobile/autofill';
  final MethodChannel _channel;

  @override
  Future<void> replaceCache(List<AutoFillRecord> records) =>
      _channel.invokeMethod<void>(
        'replaceCache',
        records.map((record) => record.toPlatformMap()).toList(growable: false),
      );

  @override
  Future<void> clearCache() => _channel.invokeMethod<void>('clearCache');
}
