import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';

import '../domain/autofill_record.dart';
import '../domain/autofill_incremental.dart';

abstract interface class AutoFillCacheBridge {
  Future<int> beginCacheSession();

  Future<void> replaceCache(
    AutoFillCachePayload payload, {
    required int sessionToken,
  });

  Future<int> revokeCacheAccess();

  Future<void> clearCache({required int sessionToken});
}

abstract interface class AutoFillIncrementalCacheBridge {
  Future<int> beginWriterSession({required int sessionToken});
  Future<void> endWriterSession({required int writerEpoch});
  Future<AutoFillCacheBase> replaceCacheV3(
    AutoFillCachePayload payload, {
    required int sessionToken,
    required int writerEpoch,
    required void Function() validatePublication,
    AutoFillCacheBase? base,
    List<String> releasingDenies = const [],
  });
  Future<AutoFillScopedDenial> denyEntries({
    required AutoFillCacheBase base,
    required int writerEpoch,
    required List<AutoFillEntryCoordinate> entries,
  });
  Future<AutoFillCacheBase> applyCacheDelta({
    required AutoFillCacheBase base,
    required int writerEpoch,
    required AutoFillCacheManifest manifest,
    required List<AutoFillRecord> upserts,
    required List<AutoFillEntryCoordinate> removals,
    required List<String> releasingDenies,
    required void Function() validatePublication,
  });
}

class MethodChannelAutoFillCacheBridge
    implements AutoFillCacheBridge, AutoFillIncrementalCacheBridge {
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

  @override
  Future<int> beginWriterSession({required int sessionToken}) async {
    final epoch = await _invokeMethod<int>('beginWriterSession', {
      'sessionToken': sessionToken,
    });
    if (epoch == null || epoch <= 0) {
      throw const FormatException('Invalid AutoFill writer epoch');
    }
    return epoch;
  }

  @override
  Future<void> endWriterSession({required int writerEpoch}) =>
      _invokeMethod<void>('endWriterSession', {'writerEpoch': writerEpoch});

  @override
  Future<AutoFillCacheBase> replaceCacheV3(
    AutoFillCachePayload payload, {
    required int sessionToken,
    required int writerEpoch,
    required void Function() validatePublication,
    AutoFillCacheBase? base,
    List<String> releasingDenies = const [],
  }) async => AutoFillCacheBase.fromPlatform(
    await _invokeMethod<Object>('replaceCacheV3', {
      'sessionToken': sessionToken,
      'writerEpoch': writerEpoch,
      if (base != null) 'base': base.toPlatformMap(),
      'releasingDenies': releasingDenies,
      'payload': {
        'version': 3,
        'manifest': autoFillV3Manifest(payload.manifest),
        'records': payload.records
            .map((record) => record.toPlatformMap())
            .toList(growable: false),
      },
    }, validatePublication),
  );

  @override
  Future<AutoFillScopedDenial> denyEntries({
    required AutoFillCacheBase base,
    required int writerEpoch,
    required List<AutoFillEntryCoordinate> entries,
  }) async => AutoFillScopedDenial.fromPlatform(
    await _invokeMethod<Object>('denyEntries', {
      'base': base.toPlatformMap(),
      'writerEpoch': writerEpoch,
      'entries': entries
          .map((entry) => entry.toPlatformMap())
          .toList(growable: false),
    }),
  );

  @override
  Future<AutoFillCacheBase> applyCacheDelta({
    required AutoFillCacheBase base,
    required int writerEpoch,
    required AutoFillCacheManifest manifest,
    required List<AutoFillRecord> upserts,
    required List<AutoFillEntryCoordinate> removals,
    required List<String> releasingDenies,
    required void Function() validatePublication,
  }) async => AutoFillCacheBase.fromPlatform(
    await _invokeMethod<Object>('applyCacheDelta', {
      'base': base.toPlatformMap(),
      'writerEpoch': writerEpoch,
      'manifest': autoFillV3Manifest(manifest),
      'upserts': upserts
          .map((record) => record.toPlatformMap())
          .toList(growable: false),
      'removals': removals
          .map((entry) => entry.toPlatformMap())
          .toList(growable: false),
      'releasingDenies': releasingDenies,
    }, validatePublication),
  );

  Future<T?> _invokeMethod<T>(
    String method, [
    Object? arguments,
    void Function()? beforeInvoke,
  ]) async {
    await _ensureAvailable();
    // Even a cached availability Future yields. Fence after that last await,
    // immediately before submitting the platform message.
    beforeInvoke?.call();
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
    if (Platform.isAndroid) {
      return (await DeviceInfoPlugin().androidInfo).version.sdkInt >= 26;
    }
    if (!Platform.isIOS) return true;
    final iosInfo = await DeviceInfoPlugin().iosInfo;
    return iosInfo.isPhysicalDevice;
  }
}
