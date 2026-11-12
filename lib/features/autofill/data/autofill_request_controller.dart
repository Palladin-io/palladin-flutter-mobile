import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/autofill_domain.dart';
import 'autofill_credential_source.dart';
import 'autofill_source_access_service.dart';
import '../../vault/data/services/member_sync_session_authority_provider.dart';

final class AutoFillRequestInvalidated implements Exception {
  const AutoFillRequestInvalidated();
}

enum AutoFillRequestMode { web, verifiedNative, manualNative, manualWeb }

final class AutoFillRequest {
  AutoFillRequest._(
    this.id,
    this.mode,
    this.verifiedHosts,
    this.usernameOnly,
    this._remaining,
    this.reportedHost,
    this.destinationApp,
  ) : _elapsed = Stopwatch()..start();

  final String id;
  final AutoFillRequestMode mode;
  final Set<String> verifiedHosts;
  final bool usernameOnly;
  final String? reportedHost;
  final String? destinationApp;
  Set<String> get matchingHosts =>
      mode == AutoFillRequestMode.manualWeb ? {reportedHost!} : verifiedHosts;
  bool get requiresConfirmation =>
      usernameOnly ||
      mode == AutoFillRequestMode.manualNative ||
      mode == AutoFillRequestMode.manualWeb;
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
      'MANUAL_WEB' => AutoFillRequestMode.manualWeb,
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
    final reportedHost = raw['reportedHost'];
    final destinationApp = raw['destinationApp'];
    if (mode == AutoFillRequestMode.manualWeb) {
      if (domains.isNotEmpty ||
          reportedHost is! String ||
          normalizeAutoFillDomain(reportedHost) != reportedHost ||
          destinationApp is! String ||
          destinationApp.trim().isEmpty ||
          destinationApp.length > 512) {
        throw const AutoFillRequestInvalidated();
      }
    } else if ((mode == AutoFillRequestMode.manualNative) != domains.isEmpty ||
        reportedHost != null ||
        destinationApp != null) {
      throw const AutoFillRequestInvalidated();
    }
    return AutoFillRequest._(
      id,
      mode,
      domains,
      usernameOnly,
      Duration(milliseconds: remaining),
      reportedHost as String?,
      destinationApp as String?,
    );
  }
}

/// Owns only request capabilities. Native owns OS origins, fields and biometric
/// proof; account keys are returned to the existing unlock owner, never retained.
final class AutoFillRequestController extends ChangeNotifier {
  AutoFillRequestController({
    required AutoFillSourceAccessService source,
    MemberSyncSessionAuthorityProvider? authority,
    MethodChannel? channel,
  }) : _source = source,
       _authority = authority,
       _channel =
           channel ??
           const MethodChannel('io.palladin.mobile/autofill-request') {
    _channel.setMethodCallHandler(_onNativeEvent);
  }

  final MethodChannel _channel;
  final AutoFillSourceAccessService _source;
  final MemberSyncSessionAuthorityProvider? _authority;
  Future<void>? _bindingOperation;
  AutoFillRequest? _request;
  String? _binding;
  String? _boundPrincipalId;
  String? _boundSessionId;
  String? get boundPrincipalId => _boundPrincipalId;
  String? _authorization;
  int _generation = 0;
  bool _disposed = false;
  Future<void>? _polling;
  Object? _authentication;
  bool _authenticationInteractive = false;
  bool _completing = false;
  Timer? _expiry;
  int _selectionRevision = 0;
  int get selectionRevision => _selectionRevision;

  AutoFillRequest? get request => _request;
  bool get isAuthenticating =>
      _authentication != null && _authenticationInteractive;
  bool get hasBoundRequest =>
      !_disposed && _request != null && !_request!.expired && _binding != null;
  bool get isAuthorized =>
      !_disposed &&
      _request != null &&
      !_request!.expired &&
      _binding != null &&
      _authorization != null;

  Future<void> _onNativeEvent(MethodCall event) async {
    if (_disposed) return;
    if (event.method == 'pendingChanged') {
      if (kDebugMode) debugPrint('AUTOFILL_HANDOFF PENDING_EVENT');
      await poll();
    } else if (event.method == 'invalidated') {
      final arguments = event.arguments;
      if (arguments is String && arguments == _request?.id) {
        if (kDebugMode) debugPrint('AUTOFILL_HANDOFF NATIVE_INVALIDATED_CLEAR');
        _clearRequest();
      }
    } else if (event.method == 'sourceChanged') {
      final arguments = event.arguments;
      if (arguments is String && arguments == _request?.id) {
        _selectionRevision++;
        notifyListeners();
      }
    }
  }

  Future<void> poll() =>
      _polling ??= _poll().whenComplete(() => _polling = null);

  Future<void> _poll() async {
    if (_disposed || _request != null) return;
    final generation = _generation;
    final raw = await _channel.invokeMapMethod<dynamic, dynamic>('pending');
    if (_disposed || generation != _generation) return;
    if (raw == null) {
      if (kDebugMode) debugPrint('AUTOFILL_HANDOFF PENDING_EMPTY');
      return;
    }
    final pending = _request = AutoFillRequest.parse(raw);
    if (kDebugMode) debugPrint('AUTOFILL_HANDOFF PENDING_ACCEPTED');
    _expiry?.cancel();
    _expiry = Timer(pending._remaining, () {
      if (identical(_request, pending)) unawaited(cancel());
    });
    notifyListeners();
  }

  Future<void> ensureBound() {
    if (hasBoundRequest) return Future.value();
    final existing = _bindingOperation;
    if (existing != null) return existing;
    final pending = _requireRequest();
    final generation = _generation;
    late final Future<void> operation;
    operation = _prepareBinding(pending, generation).whenComplete(() {
      if (identical(_bindingOperation, operation)) _bindingOperation = null;
    });
    return _bindingOperation = operation;
  }

  Future<void> _prepareBinding(AutoFillRequest pending, int generation) async {
    final authorityProvider = _authority;
    if (authorityProvider == null) throw const AutoFillRequestInvalidated();
    final ticket = await _source.ticket();
    final authority = await authorityProvider.captureForPreparation();
    _requireCurrent(generation, pending);
    authority.validateCurrent();
    _source.validateAuthority(ticket, authority.claims);
    await bind(
      principalId: authority.claims.principalId,
      organizationId: authority.claims.organizationId,
      sessionId: ticket.sessionId,
    );
  }

  Future<Future<void> Function()> preparePasswordAuthorization() async {
    final pending = _requireRequest();
    await ensureBound();
    if (!identical(_request, pending)) throw const AutoFillRequestInvalidated();
    return capturePasswordAuthorization();
  }

  Future<void> bind({
    required String principalId,
    required String organizationId,
    required String sessionId,
  }) async {
    final pending = _requireRequest();
    final generation = ++_generation;
    _binding = null;
    _boundPrincipalId = null;
    _boundSessionId = null;
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
    _boundPrincipalId = principalId;
    _boundSessionId = sessionId;
    notifyListeners();
  }

  /// Capture before KDF/account unwrap; invoke only from its verified success
  /// branch. A replacement request cannot borrow an older crypto completion.
  Future<void> Function() capturePasswordAuthorization() {
    final pending = _requireRequest();
    final binding = _requireBinding();
    final generation = _generation;
    var used = false;
    return () async {
      _requireCurrent(generation, pending);
      if (used) throw const AutoFillRequestInvalidated();
      used = true;
      final operation = _beginAuthentication();
      _authorization = null;
      try {
        final authorization = await _channel.invokeMethod<String>(
          'authorizePasswordUnlock',
          {'id': pending.id, 'bindingToken': binding},
        );
        _acceptAuthorization(generation, pending, authorization);
      } finally {
        if (identical(_authentication, operation)) _authentication = null;
      }
    };
  }

  /// The app supplies its captured, verified unlock-session guard; native still
  /// mints only a request-bound capability and independently fences the source.
  Future<void> authorizeUnlockedSession({
    required String expectedPrincipalId,
    required void Function() validateCurrentSession,
  }) async {
    final pending = _requireRequest();
    validateCurrentSession();
    await ensureBound();
    if (!identical(_request, pending) ||
        _boundPrincipalId != expectedPrincipalId) {
      throw const AutoFillRequestInvalidated();
    }
    final generation = _generation;
    final binding = _requireBinding();
    void guard() {
      _requireCurrent(generation, pending);
      validateCurrentSession();
      if (_boundPrincipalId != expectedPrincipalId) {
        throw const AutoFillRequestInvalidated();
      }
    }

    guard();
    final ticket = await _source.ticket();
    guard();
    if (_boundSessionId != ticket.sessionId) {
      throw const AutoFillRequestInvalidated();
    }
    _source.validateTicket(ticket);
    final operation = _beginAuthentication(interactive: false);
    _authorization = null;
    try {
      final authorization = await _channel
          .invokeMethod<String>('authorizeUnlockedSession', {
            'id': pending.id,
            'bindingToken': binding,
            'principalId': expectedPrincipalId,
            'sessionId': ticket.sessionId,
            'sourceEpoch': ticket.sourceEpoch,
          });
      guard();
      _source.validateTicket(ticket);
      _acceptAuthorization(generation, pending, authorization);
    } finally {
      if (identical(_authentication, operation)) _authentication = null;
    }
  }

  Future<void> authenticatePresence() async {
    final pending = _requireRequest();
    await ensureBound();
    if (!identical(_request, pending)) throw const AutoFillRequestInvalidated();
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

  /// Keeps OS-prompt lifecycle/cancellation bound to this request without
  /// waiting for source initialization or granting a fill capability.
  Future<Uint8List?> guardLocalBiometricUnlock(
    Future<Uint8List?> Function() unlock,
  ) async {
    final pending = _requireRequest();
    final operation = _beginAuthentication();
    Uint8List? key;
    try {
      key = await unlock();
      if (!identical(_requireRequest(), pending) ||
          !identical(_authentication, operation)) {
        throw const AutoFillRequestInvalidated();
      }
      return key;
    } catch (_) {
      key?.fillRange(0, key.length, 0);
      rethrow;
    } finally {
      if (identical(_authentication, operation)) _authentication = null;
    }
  }

  Future<Uint8List> readBiometricMasterKey({
    required String promptTitle,
    required String cancelLabel,
  }) async {
    final pending = _requireRequest();
    await ensureBound();
    if (!identical(_request, pending)) throw const AutoFillRequestInvalidated();
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

  Object _beginAuthentication({bool interactive = true}) {
    if (_authentication != null) throw const AutoFillRequestInvalidated();
    _authenticationInteractive = interactive;
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

  Future<String> confirmSelection({
    required AutoFillCandidate candidate,
    required String selectedHost,
    required AutoFillSourceTicket source,
  }) async {
    final guard = captureGuard();
    _source.validateTicket(source);
    final pending = _requireRequest();
    final consent = await _channel.invokeMethod<String>('confirmSelection', {
      'id': pending.id,
      'bindingToken': _binding!,
      'authorizationToken': _authorization!,
      'sourceEpoch': source.sourceEpoch,
      'vaultId': candidate.vaultId,
      'entryId': candidate.entryId,
      'selectedHost': selectedHost,
    });
    guard();
    _source.validateTicket(source);
    if (consent == null || consent.isEmpty) {
      throw const AutoFillRequestInvalidated();
    }
    return consent;
  }

  Future<void> completeCredential(
    AutoFillSelectedCredential credential, {
    required AutoFillSourceTicket source,
    String? consentToken,
  }) async {
    final authGuard = captureGuard();
    void guard() {
      authGuard();
      _source.validateTicket(source);
    }

    guard();
    final pending = _requireRequest();
    if (_completing ||
        (pending.requiresConfirmation &&
            (consentToken == null || consentToken.isEmpty))) {
      throw const AutoFillRequestInvalidated();
    }
    _completing = true;
    final capability = {
      'id': pending.id,
      'bindingToken': _binding!,
      'authorizationToken': _authorization!,
      'sourceEpoch': source.sourceEpoch,
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
    final id = _clearRequest();
    if (id != null) await _channel.invokeMethod<void>('cancel', {'id': id});
  }

  String? _clearRequest() {
    final id = _request?.id;
    _expiry?.cancel();
    _expiry = null;
    ++_generation;
    _request = null;
    _binding = null;
    _boundPrincipalId = null;
    _boundSessionId = null;
    _authorization = null;
    _authentication = null;
    _bindingOperation = null;
    if (!_disposed) notifyListeners();
    return id;
  }

  @override
  void dispose() {
    _disposed = true;
    _channel.setMethodCallHandler(null);
    unawaited(cancel());
    super.dispose();
  }
}
