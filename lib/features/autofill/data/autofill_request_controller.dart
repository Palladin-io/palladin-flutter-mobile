import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/autofill_domain.dart';
import 'autofill_credential_source.dart';

final class AutoFillRequestInvalidated implements Exception {
  const AutoFillRequestInvalidated();
}

enum AutoFillRequestMode { web, verifiedNative, manualNative }

final class AutoFillRequest {
  AutoFillRequest._(
    this.id,
    this.mode,
    this.verifiedHosts,
    this.usernameOnly,
    this._remaining,
  ) : _elapsed = Stopwatch()..start();

  final String id;
  final AutoFillRequestMode mode;
  final Set<String> verifiedHosts;
  final bool usernameOnly;
  final Duration _remaining;
  final Stopwatch _elapsed;
  bool get expired => _elapsed.elapsed >= _remaining;

  static AutoFillRequest parse(Map<dynamic, dynamic> raw) {
    final id = raw['id'];
    final remaining = raw['remainingMs'];
    final usernameOnly = raw['usernameOnly'];
    final hosts = raw['verifiedHosts'];
    final mode = switch (raw['mode']) {
      'WEB' => AutoFillRequestMode.web,
      'VERIFIED_NATIVE' => AutoFillRequestMode.verifiedNative,
      'MANUAL_NATIVE' => AutoFillRequestMode.manualNative,
      _ => null,
    };
    if (id is! String ||
        id.isEmpty ||
        remaining is! int ||
        remaining <= 0 ||
        usernameOnly is! bool ||
        hosts is! List ||
        mode == null ||
        hosts.any(
          (host) => host is! String || normalizeAutoFillDomain(host) != host,
        )) {
      throw const AutoFillRequestInvalidated();
    }
    final domains = Set<String>.unmodifiable(hosts.cast<String>());
    if ((mode == AutoFillRequestMode.manualNative) != domains.isEmpty) {
      throw const AutoFillRequestInvalidated();
    }
    return AutoFillRequest._(
      id,
      mode,
      domains,
      usernameOnly,
      Duration(milliseconds: remaining),
    );
  }
}

/// Owns only request capabilities. Native owns OS origins, fields and biometric
/// proof; account keys are returned to the existing unlock owner, never retained.
final class AutoFillRequestController extends ChangeNotifier {
  AutoFillRequestController({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('io.palladin.mobile/autofill-request');

  final MethodChannel _channel;
  AutoFillRequest? _request;
  String? _binding;
  String? _authorization;
  int _generation = 0;
  bool _disposed = false;
  Future<void>? _polling;
  Object? _authentication;
  bool _completing = false;

  AutoFillRequest? get request => _request;
  bool get isAuthorized =>
      !_disposed &&
      _request != null &&
      !_request!.expired &&
      _binding != null &&
      _authorization != null;

  Future<void> poll() =>
      _polling ??= _poll().whenComplete(() => _polling = null);

  Future<void> _poll() async {
    if (_disposed || _request != null) return;
    final generation = _generation;
    final raw = await _channel.invokeMapMethod<dynamic, dynamic>('pending');
    if (_disposed || generation != _generation) return;
    if (raw == null) return;
    _request = AutoFillRequest.parse(raw);
    notifyListeners();
  }

  Future<void> bind({
    required String principalId,
    required String organizationId,
    required String sessionId,
  }) async {
    final pending = _requireRequest();
    final generation = ++_generation;
    _binding = null;
    _authorization = null;
    final binding = await _channel.invokeMethod<String>('bind', {
      'id': pending.id,
      'principalId': principalId,
      'organizationId': organizationId,
      'sessionId': sessionId,
    });
    _requireCurrent(generation, pending);
    if (binding == null || binding.isEmpty) {
      throw const AutoFillRequestInvalidated();
    }
    _binding = binding;
    notifyListeners();
  }

  Future<void> authenticatePresence() async {
    final pending = _requireRequest();
    final binding = _requireBinding();
    final generation = _generation;
    final operation = _beginAuthentication();
    _authorization = null;
    try {
      final authorization = await _channel.invokeMethod<String>(
        'authenticatePresence',
        {'id': pending.id, 'bindingToken': binding},
      );
      _acceptAuthorization(generation, pending, authorization);
    } finally {
      if (identical(_authentication, operation)) _authentication = null;
    }
  }

  Future<Uint8List> readBiometricMasterKey({
    required String promptTitle,
    required String cancelLabel,
  }) async {
    final pending = _requireRequest();
    final binding = _requireBinding();
    final generation = _generation;
    final operation = _beginAuthentication();
    _authorization = null;
    Uint8List? key;
    try {
      final raw = await _channel
          .invokeMapMethod<dynamic, dynamic>('readBiometricMasterKey', {
            'id': pending.id,
            'bindingToken': binding,
            'promptTitle': promptTitle,
            'cancelLabel': cancelLabel,
          });
      final bytes = raw?['masterKey'];
      if (bytes is Uint8List) key = bytes;
      if (key == null || key.length != 32) {
        throw const AutoFillRequestInvalidated();
      }
      _acceptAuthorization(generation, pending, raw?['authorizationToken']);
      return key;
    } catch (_) {
      key?.fillRange(0, key.length, 0);
      rethrow;
    } finally {
      if (identical(_authentication, operation)) _authentication = null;
    }
  }

  Object _beginAuthentication() {
    if (_authentication != null) throw const AutoFillRequestInvalidated();
    return _authentication = Object();
  }

  void Function() captureGuard() {
    final pending = _requireRequest();
    final generation = _generation;
    final authorization = _authorization;
    if (!isAuthorized) throw const AutoFillRequestInvalidated();
    return () {
      _requireCurrent(generation, pending);
      if (!isAuthorized || authorization != _authorization) {
        throw const AutoFillRequestInvalidated();
      }
    };
  }

  Future<void> completeCredential(
    AutoFillSelectedCredential credential, {
    String? consentToken,
  }) async {
    final guard = captureGuard();
    final pending = _requireRequest();
    if (_completing ||
        ((pending.usernameOnly ||
                pending.mode == AutoFillRequestMode.manualNative) &&
            (consentToken == null || consentToken.isEmpty))) {
      throw const AutoFillRequestInvalidated();
    }
    _completing = true;
    final capability = {
      'id': pending.id,
      'bindingToken': _binding!,
      'authorizationToken': _authorization!,
    };
    try {
      final valid = await _channel.invokeMethod<bool>('validate', {
        ...capability,
        'selectedHost': credential.selectedHost,
      });
      guard();
      if (valid != true) throw const AutoFillRequestInvalidated();
      final completed = await _channel.invokeMethod<bool>('complete', {
        ...capability,
        'vaultId': credential.candidate.vaultId,
        'entryId': credential.candidate.entryId,
        'selectedHost': credential.selectedHost,
        'effectiveNotAfterMillis':
            credential.accessContext.notAfter.millisecondsSinceEpoch,
        'username': credential.username,
        if (!pending.usernameOnly) 'password': credential.password,
        'consentToken': ?consentToken,
      });
      if (completed != true) throw const AutoFillRequestInvalidated();
    } finally {
      _completing = false;
      // Cancellation is scoped to this original request, never a newer one.
      if (identical(_request, pending)) await cancel();
    }
  }

  void _acceptAuthorization(
    int generation,
    AutoFillRequest pending,
    Object? value,
  ) {
    _requireCurrent(generation, pending);
    if (value is! String || value.isEmpty) {
      throw const AutoFillRequestInvalidated();
    }
    _authorization = value;
    notifyListeners();
  }

  AutoFillRequest _requireRequest() {
    final pending = _request;
    if (_disposed || pending == null || pending.expired) {
      throw const AutoFillRequestInvalidated();
    }
    return pending;
  }

  String _requireBinding() =>
      _binding ?? (throw const AutoFillRequestInvalidated());

  void _requireCurrent(int generation, AutoFillRequest pending) {
    if (generation != _generation || !identical(_requireRequest(), pending)) {
      throw const AutoFillRequestInvalidated();
    }
  }

  Future<void> cancel() async {
    final id = _request?.id;
    ++_generation;
    _request = null;
    _binding = null;
    _authorization = null;
    _authentication = null;
    if (!_disposed) notifyListeners();
    if (id != null) await _channel.invokeMethod<void>('cancel', {'id': id});
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(cancel());
    super.dispose();
  }
}
