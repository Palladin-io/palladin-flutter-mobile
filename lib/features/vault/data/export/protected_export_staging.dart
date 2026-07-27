import 'package:flutter/services.dart';

/// A native, app-private staging area for short-lived plaintext export files.
abstract interface class ProtectedExportStaging {
  Future<int> sweepStaleExports();

  /// Closes open writers and removes every Palladin-owned staged export.
  Future<int> cleanupExports();

  /// Opens a unique file with platform data-protection and backup-exclusion
  /// flags already applied. Callers append bounded chunks, never a whole vault.
  Future<ProtectedExportSink> create({required String fileExtension});

  Future<bool> delete(String path);
}

abstract interface class ProtectedExportSink {
  Future<void> append(Uint8List bytes);
  Future<String> finish();
  Future<void> abort();
}

class MethodChannelProtectedExportStaging implements ProtectedExportStaging {
  MethodChannelProtectedExportStaging({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'io.palladin.mobile/protected-export';
  final MethodChannel _channel;

  @override
  Future<int> sweepStaleExports() async =>
      await _channel.invokeMethod<int>('sweepStaleExports') ?? 0;

  @override
  Future<int> cleanupExports() async =>
      await _channel.invokeMethod<int>('cleanupExports') ?? 0;

  @override
  Future<ProtectedExportSink> create({required String fileExtension}) async {
    final extension = _validatedExtension(fileExtension);
    final id = await _channel.invokeMethod<String>('createExport', {
      'extension': extension,
    });
    if (id == null || id.isEmpty) {
      throw const FormatException('Native export staging returned no id');
    }
    return _MethodChannelExportSink(_channel, id);
  }

  @override
  Future<bool> delete(String path) async =>
      await _channel.invokeMethod<bool>('deleteExport', {'path': path}) ??
      false;

  String _validatedExtension(String value) {
    final normalized = value.toLowerCase().replaceFirst(RegExp(r'^\.'), '');
    if (!RegExp(r'^[a-z0-9]{1,10}$').hasMatch(normalized)) {
      throw const FormatException('Invalid export file extension');
    }
    return normalized;
  }
}

final class _MethodChannelExportSink implements ProtectedExportSink {
  _MethodChannelExportSink(this._channel, this._id);

  final MethodChannel _channel;
  final String _id;
  bool _closed = false;

  @override
  Future<void> append(Uint8List bytes) async {
    if (_closed) throw StateError('Export sink is closed');
    await _channel.invokeMethod<void>('appendExport', {
      'id': _id,
      'bytes': bytes,
    });
  }

  @override
  Future<String> finish() async {
    if (_closed) throw StateError('Export sink is closed');
    final path = await _channel.invokeMethod<String>('finishExport', {
      'id': _id,
    });
    if (path == null || path.isEmpty) {
      throw const FormatException('Native export staging returned no path');
    }
    _closed = true;
    return path;
  }

  @override
  Future<void> abort() async {
    if (_closed) return;
    _closed = true;
    await _channel.invokeMethod<void>('abortExport', {'id': _id});
  }
}
