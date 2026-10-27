import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

final class AutoFillSaveDraft extends ChangeNotifier {
  AutoFillSaveDraft({
    required this.id,
    required this.session,
    required this.packageName,
    this.sourceLabel,
    required this.domains,
    required this.isWeb,
    required this.username,
    required this.password,
  });
  final String id;
  final String session;
  final String packageName;
  final String? sourceLabel;
  final List<String> domains;
  final bool isWeb;
  String username;
  String password;
  bool valid = true;
  void clear() {
    valid = false;
    username = '';
    password = '';
    notifyListeners();
  }
}

/// Original-login authority is RAM-only and survives an ordinary Vault lock.
final class AutoFillSaveController {
  AutoFillSaveController({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('io.palladin.mobile/autofill-save') {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'pending') await poll();
      if (call.method == 'invalidated' && call.arguments == draft?.id) {
        _clearLocal();
      }
    });
  }
  final MethodChannel _channel;
  String? _principal;
  String? _session;
  bool _unlocked = false;
  bool _foreground = true;
  bool _disposed = false;
  bool _polling = false;
  int _generation = 0;
  int _pollGeneration = 0;
  Future<void> _activation = Future.value();
  Timer? _expiry;
  AutoFillSaveDraft? draft;
  ValueChanged<AutoFillSaveDraft>? onDraft;
  String? Function()? biometricPrompt;

  Future<void> synchronize(String? principal, {required bool unlocked}) async {
    if (_disposed) return;
    if (_unlocked && !unlocked) {
      final id = draft?.id;
      _clearLocal();
      if (id != null) unawaited(_invoke<void>('cancel', {'id': id}));
    }
    _unlocked = unlocked;
    if (principal != _principal) {
      cancel();
      _principal = principal;
      _session = null;
      final generation = ++_generation;
      _activation = _activation.then((_) async {
        await _invoke<void>('revoke');
        if (_disposed ||
            generation != _generation ||
            _principal == null ||
            !_unlocked) {
          return;
        }
        final session = await _invoke<String>('activate', {
          'principalId': _principal,
        });
        if (generation == _generation) _session = session;
      });
    } else if (principal != null && unlocked && _session == null) {
      final generation = _generation;
      _activation = _activation.then((_) async {
        if (_session != null ||
            generation != _generation ||
            !_unlocked ||
            _disposed) {
          return;
        }
        final session = await _invoke<String>('activate', {
          'principalId': principal,
        });
        if (generation == _generation) _session = session;
      });
    }
    await _activation;
    await poll();
  }

  Future<T?> _invoke<T>(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<void> poll() async {
    if (_disposed ||
        !_unlocked ||
        !_foreground ||
        _session == null ||
        _polling ||
        draft != null) {
      return;
    }
    _polling = true;
    final generation = _generation;
    final pollGeneration = _pollGeneration;
    final session = _session!;
    bool current() =>
        _current(generation, session) && pollGeneration == _pollGeneration;
    try {
      final id = await _invoke<String>('pending');
      if (id == null) return;
      if (!current()) {
        await _invoke<void>('cancel', {'id': id});
        return;
      }
      final raw = await _invoke<Map<dynamic, dynamic>>('take', {
        'id': id,
        'session': session,
        'prompt': biometricPrompt?.call(),
      });
      if (raw == null) return;
      if (!current()) {
        await _invoke<void>('cancel', {'id': id});
        return;
      }
      final domains =
          (raw['domains'] as List?)?.whereType<String>().toList() ?? [];
      final username = raw['username'];
      final password = raw['password'];
      final remaining = raw['remainingMs'];
      final mode = raw['mode'];
      if (domains.isEmpty ||
          domains.length > 16 ||
          !domains.every(
            (host) =>
                RegExp(r'^[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?$').hasMatch(host),
          ) ||
          username is! String ||
          username.isEmpty ||
          username.length > 1024 ||
          password is! String ||
          password.isEmpty ||
          password.length > 4096 ||
          remaining is! int ||
          remaining <= 0 ||
          remaining > 120000 ||
          raw['packageName'] is! String ||
          raw['id'] != id ||
          (mode != 'WEB' && mode != 'VERIFIED_NATIVE' && mode != 'IOS_HTTPS') ||
          (mode != 'VERIFIED_NATIVE' && domains.length != 1)) {
        await _invoke<void>('cancel');
        return;
      }
      final value = AutoFillSaveDraft(
        id: id,
        session: session,
        packageName: raw['packageName'] as String,
        sourceLabel: raw['sourceLabel'] as String?,
        domains: domains,
        isWeb: mode != 'VERIFIED_NATIVE',
        username: username,
        password: password,
      );
      draft = value;
      _expiry = Timer(
        Duration(milliseconds: remaining),
        () => cancelDraft(value),
      );
      onDraft?.call(value);
    } catch (_) {
      cancel();
    } finally {
      _polling = false;
    }
  }

  bool _current(int generation, String session) =>
      !_disposed &&
      _unlocked &&
      _foreground &&
      generation == _generation &&
      session == _session;

  Future<bool> validate(AutoFillSaveDraft value, String domain) async {
    if (!identical(value, draft) || !value.valid || !_unlocked) return false;
    final valid = await _invoke<bool>('validate', {
      'id': value.id,
      'session': value.session,
      'domain': domain,
    });
    return valid == true && identical(value, draft) && value.valid && _unlocked;
  }

  void _clearLocal() {
    ++_pollGeneration;
    _expiry?.cancel();
    _expiry = null;
    final previous = draft;
    draft = null;
    previous?.clear();
  }

  void background() {
    _foreground = false;
    final id = draft?.id;
    _clearLocal();
    if (id != null) unawaited(_invoke<void>('cancel', {'id': id}));
  }

  Future<void> resume() async {
    _foreground = true;
    await poll();
  }

  void cancelDraft(AutoFillSaveDraft value) {
    if (identical(draft, value)) _clearLocal();
    unawaited(_invoke<void>('cancel', {'id': value.id}));
  }

  void cancel() {
    final id = draft?.id;
    _clearLocal();
    unawaited(_invoke<void>('cancel', {'id': ?id}));
  }

  void dispose() {
    _disposed = true;
    ++_generation;
    cancel();
    unawaited(_invoke<void>('revoke'));
    _channel.setMethodCallHandler(null);
  }
}
