import 'package:flutter/services.dart';
import '../../../core/utils/request_id.dart';

import '../../../core/storage/biometric_key_store.dart';
import '../../vault/data/services/member_sync_service.dart';

final class AutoFillSourceConfiguration {
  const AutoFillSourceConfiguration({
    required this.authority,
    required this.profileBinding,
    required this.accountUnlock,
    required this.validateCurrent,
  });
  final MemberSyncSessionAuthority authority;
  final String profileBinding;
  final Map<String, Object?> accountUnlock;
  final void Function() validateCurrent;
}

final class AutoFillSourceTicket {
  const AutoFillSourceTicket._(
    this.sessionId,
    this.sourceEpoch,
    this.profileBinding,
    this._identity,
    this._revision,
  );
  final String sessionId;
  final int sourceEpoch;
  final String profileBinding;
  final Object _identity;
  final int _revision;

  Map<String, Object> toPlatformMap() => {
    'sessionId': sessionId,
    'sourceEpoch': sourceEpoch,
    'profileBinding': profileBinding,
  };
}

final class AutoFillSourceMutation {
  AutoFillSourceMutation._(this._identity);
  final Object _identity;
  bool _completed = false;
  AutoFillSourceTicket? _ticket;
}

/// Publishes only source-control authority. It never reads credential bodies or
/// stores keys. Native quarantine precedes sensitive work; metadata activation
/// cannot release an active, failed or newly admitted owner.
final class AutoFillSourceAccessService {
  AutoFillSourceAccessService({
    MethodChannel? channel,
    Future<AutoFillSourceConfiguration> Function()? loadConfiguration,
  }) : _loadConfiguration = loadConfiguration,
       _channel =
           channel ??
           const MethodChannel('io.palladin.mobile/autofill-request');
  final MethodChannel _channel;
  final Future<AutoFillSourceConfiguration> Function()? _loadConfiguration;
  Future<void>? _initializing;
  Future<void>? _transitionBarrier;
  bool _transitionRunning = false;
  Future<void> _tail = Future.value();
  Object _identity = Object();
  int _revision = 0;
  int _admissionRevision = 0;
  int _sessionRevision = 0;
  String? _sessionId;
  String? _profileBinding;
  int? _epoch;
  MemberSyncSessionAuthority? _authority;
  final Set<AutoFillSourceMutation> _owners = {};

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> ensureSession() {
    final transition = _transitionBarrier;
    if (transition != null) {
      final admission = _admissionRevision;
      return transition.then((_) {
        if (admission != _admissionRevision) {
          throw StateError('Source session changed');
        }
        return ensureSession();
      });
    }
    if (_epoch != null) return Future.value();
    final pending = _initializing;
    if (pending != null) return pending;
    final loader = _loadConfiguration;
    if (loader == null) return _tail;
    final identity = _identity;
    late final Future<void> initialization;
    initialization = Future<AutoFillSourceConfiguration>.sync(loader)
        .then((configuration) async {
          _requireIdentity(identity);
          configuration.validateCurrent();
          await _startSession(
            authority: configuration.authority,
            profileBinding: configuration.profileBinding,
            accountUnlock: configuration.accountUnlock,
            validateCurrent: configuration.validateCurrent,
            preserveOwners: true,
          );
        })
        .whenComplete(() {
          if (identical(_initializing, initialization)) _initializing = null;
        });
    return _initializing = initialization;
  }

  Future<void> begin({
    required MemberSyncSessionAuthority authority,
    required String profileBinding,
    required Map<String, Object?> accountUnlock,
    void Function()? validateCurrent,
  }) {
    _sessionRevision++;
    final admission = ++_admissionRevision;
    _initializing = null;
    final transition = _transitionBarrier;
    if (transition != null) {
      return transition.then((_) {
        if (admission != _admissionRevision) {
          throw StateError('Source session changed');
        }
        return _startSession(
          authority: authority,
          profileBinding: profileBinding,
          accountUnlock: accountUnlock,
          validateCurrent: validateCurrent,
        );
      });
    }
    return _startSession(
      authority: authority,
      profileBinding: profileBinding,
      accountUnlock: accountUnlock,
      validateCurrent: validateCurrent,
    );
  }

  Future<void> _startSession({
    required MemberSyncSessionAuthority authority,
    required String profileBinding,
    required Map<String, Object?> accountUnlock,
    void Function()? validateCurrent,
    bool preserveOwners = false,
  }) {
    final identity = preserveOwners ? _identity : (_identity = Object());
    final session = _sessionId = newRequestId();
    _profileBinding = profileBinding;
    _authority = authority;
    _epoch = null;
    _revision++;
    if (!preserveOwners) _owners.clear();
    return _serialize(() async {
      _requireIdentity(identity);
      validateCurrent?.call();
      final epoch = await _channel.invokeMethod<int>('beginSourceSession', {
        'sessionId': session,
        'forceQuarantine': !preserveOwners || _owners.isNotEmpty,
        'profileBinding': profileBinding,
        'principalId': authority.principalId,
        'organizationId': authority.organizationId,
        'organizationMembershipGeneration':
            authority.organizationMembershipGeneration,
        'offlinePolicy': authority.offlinePolicy,
        'offlinePolicyVersion': authority.offlinePolicyVersion,
        'accountUnlock': accountUnlock,
      });
      _requireIdentity(identity);
      validateCurrent?.call();
      if (epoch == null || epoch <= 0) {
        throw StateError('Source session unavailable');
      }
      _epoch = epoch;
    });
  }

  Future<void> transitionSession({
    Future<void> Function(Map<String, Object> capturedQuarantinedTicket)?
    cleanup,
  }) {
    _sessionRevision++;
    _admissionRevision++;
    _revision++;
    _initializing = null;
    if (_transitionRunning) return _transitionBarrier!;
    final session = _sessionId;
    final profile = _profileBinding;
    _identity = Object();
    _owners.clear();
    _transitionRunning = true;
    late final Future<void> barrier;
    barrier = _performTransition(session, profile, cleanup)
        .then((_) {
          if (identical(_transitionBarrier, barrier)) _transitionBarrier = null;
        })
        .whenComplete(() {
          _transitionRunning = false;
        });
    _transitionBarrier = barrier;
    return barrier;
  }

  Future<void> _performTransition(
    String? session,
    String? profile,
    Future<void> Function(Map<String, Object>)? cleanup,
  ) async {
    final cleanupTicket = await _serialize<Map<String, Object>?>(() async {
      final snapshot = await _channel.invokeMapMethod<String, Object?>(
        'sourceSnapshot',
      );
      if (snapshot == null) return null;
      final epoch = snapshot['sourceEpoch'];
      final digest = snapshot['profileDigest'];
      if (epoch is! int || epoch <= 0 || digest is! String || digest.isEmpty) {
        throw StateError('Source revocation unavailable');
      }
      final live = session != null && profile != null;
      final revoked = await _channel.invokeMethod<int>(
        live ? 'revokeSourceSession' : 'revokeSource',
        live
            ? {
                'sessionId': session,
                'sourceEpoch': epoch,
                'profileBinding': profile,
              }
            : {'sourceEpoch': epoch, 'profileDigest': digest},
      );
      if (revoked == null || revoked <= epoch) {
        throw StateError('Source revocation unavailable');
      }
      return live
          ? {
              'sessionId': session,
              'sourceEpoch': revoked,
              'profileBinding': profile,
            }
          : null;
    });
    if (cleanup != null) {
      if (cleanupTicket == null) {
        throw StateError('Source cleanup capability unavailable');
      }
      await cleanup(cleanupTicket);
    }
    await _serialize(() async {
      if (session != null) {
        await _channel.invokeMethod<void>('invalidateSession', {
          'sessionId': session,
        });
      }
    });
    _sessionId = null;
    _profileBinding = null;
    _authority = null;
    _epoch = null;
  }

  void Function() captureSessionGuard() {
    final admission = _sessionRevision;
    return () {
      if (admission != _sessionRevision) {
        throw StateError('Source session changed');
      }
    };
  }

  Future<void> revokeAccess() {
    final identity = _identity;
    _revision++;
    _owners.add(AutoFillSourceMutation._(identity));
    return _serialize(() async {
      _requireIdentity(identity);
      if (_epoch != null) {
        final current = _currentTicket();
        final epoch = await _channel.invokeMethod<int>(
          'revokeSourceSession',
          current.toPlatformMap(),
        );
        _requireIdentity(identity);
        if (epoch == null || epoch <= current.sourceEpoch) {
          throw StateError('Source revocation unavailable');
        }
        _epoch = epoch;
        return;
      }
      final snapshot = await _channel.invokeMapMethod<String, Object?>(
        'sourceSnapshot',
      );
      _requireIdentity(identity);
      if (snapshot == null) return;
      final epoch = snapshot['sourceEpoch'];
      final digest = snapshot['profileDigest'];
      if (epoch is! int || epoch <= 0 || digest is! String || digest.isEmpty) {
        throw StateError('Source revocation unavailable');
      }
      final revoked = await _channel.invokeMethod<int>('revokeSource', {
        'sourceEpoch': epoch,
        'profileDigest': digest,
      });
      _requireIdentity(identity);
      if (revoked == null || revoked <= epoch) {
        throw StateError('Source revocation unavailable');
      }
    });
  }

  Future<void> endSession() {
    _sessionRevision++;
    _admissionRevision++;
    final session = _sessionId;
    _identity = Object();
    _revision++;
    _sessionId = null;
    _profileBinding = null;
    _authority = null;
    _epoch = null;
    _initializing = null;
    _owners.clear();
    return _serialize(() async {
      if (session != null) {
        await _channel.invokeMethod<void>('invalidateSession', {
          'sessionId': session,
        });
      }
    });
  }

  Future<AutoFillSourceTicket> ticket() async {
    await ensureSession();
    final identity = _identity;
    await _tail;
    _requireIdentity(identity);
    return _currentTicket();
  }

  Future<Map<String, Object>> biometricSourceTicket() async =>
      (await ticket()).toPlatformMap();

  Future<AutoFillSourceMutation> invalidate({
    bool revokeAuthorization = false,
  }) {
    if (revokeAuthorization) _admissionRevision++;
    final identity = _identity;
    final owner = AutoFillSourceMutation._(identity);
    _owners.add(owner);
    final revision = ++_revision;
    Future<AutoFillSourceMutation> deny() => _serialize(() async {
      _requireIdentity(identity);
      if (_epoch == null) {
        final snapshot = await _channel.invokeMapMethod<String, Object?>(
          'sourceSnapshot',
        );
        _requireIdentity(identity);
        if (snapshot != null) {
          final epoch = snapshot['sourceEpoch'];
          final digest = snapshot['profileDigest'];
          if (epoch is! int ||
              epoch <= 0 ||
              digest is! String ||
              digest.isEmpty) {
            throw StateError('Source denial unavailable');
          }
          final revoked = await _channel.invokeMethod<int>('revokeSource', {
            'sourceEpoch': epoch,
            'profileDigest': digest,
          });
          _requireIdentity(identity);
          if (revoked == null || revoked <= epoch) {
            throw StateError('Source denial unavailable');
          }
        }
        return owner;
      }
      final current = _currentTicket();
      final epoch = await _channel.invokeMethod<int>(
        revokeAuthorization ? 'revokeSourceSession' : 'invalidateSource',
        current.toPlatformMap(),
      );
      _requireIdentity(identity);
      if (epoch == null || epoch <= current.sourceEpoch) {
        throw StateError('Source denial unavailable');
      }
      _epoch = epoch;
      owner._ticket = AutoFillSourceTicket._(
        current.sessionId,
        epoch,
        current.profileBinding,
        identity,
        revision,
      );
      return owner;
    });
    final transition = _transitionBarrier;
    return transition == null ? deny() : transition.then((_) => deny());
  }

  AutoFillSourceTicket ticketForMutation(AutoFillSourceMutation owner) {
    if (!ownsMutation(owner) || owner._ticket == null) {
      throw StateError('Source mutation unavailable');
    }
    final ticket = owner._ticket!;
    _requireTicket(ticket);
    return ticket;
  }

  bool ownsMutation(AutoFillSourceMutation owner) =>
      identical(owner._identity, _identity) && _owners.contains(owner);

  void complete(AutoFillSourceMutation owner) {
    _requireIdentity(owner._identity);
    if (!_owners.contains(owner)) throw StateError('Unknown source owner');
    owner._completed = true;
  }

  Future<T> withCiphertextMutation<T>(Future<T> Function() write) async {
    final admission = _admissionRevision;
    await ensureSession();
    if (admission != _admissionRevision) {
      throw StateError('Source session changed');
    }
    final owner = await invalidate();
    return _serialize(() async {
      _requireIdentity(owner._identity);
      final result = await write();
      _requireIdentity(owner._identity);
      complete(owner);
      return result;
    });
  }

  int _biometricMutations = 0;
  bool get isBiometricMutationActive => _biometricMutations > 0;

  Future<T> withBiometricMutation<T>(
    Future<T> Function(Map<String, Object> sourceTicket) operation,
  ) async {
    _biometricMutations++;
    try {
      if (_epoch == null || _transitionBarrier != null) {
        final admission = _admissionRevision;
        await ensureSession();
        if (admission != _admissionRevision) {
          throw StateError('Source session changed');
        }
      }
      final owner = await invalidate();
      final expected = owner._ticket!;
      _requireTicket(expected);
      try {
        final result = await operation(expected.toPlatformMap());
        complete(owner);
        return result;
      } on BiometricMutationCanceledWithoutChanges {
        complete(owner);
        rethrow;
      }
    } finally {
      _biometricMutations--;
    }
  }

  Future<void> activate({
    required AutoFillSourceTicket expected,
    required void Function() validateSource,
  }) => _serialize(() async {
    _requireTicket(expected);
    if (_owners.any((owner) => !owner._completed)) {
      throw StateError('Source mutation still owns quarantine');
    }
    final completed = Set<AutoFillSourceMutation>.of(_owners);
    validateSource();
    final epoch = await _channel.invokeMethod<int>(
      'activateSource',
      expected.toPlatformMap(),
    );
    _requireTicket(expected);
    validateSource();
    if (epoch != expected.sourceEpoch) {
      throw StateError('Source acknowledgement changed');
    }
    _owners.removeAll(completed);
  });

  void validateTicket(AutoFillSourceTicket ticket) => _requireTicket(ticket);

  void validateAuthority(
    AutoFillSourceTicket ticket,
    MemberSyncSessionAuthority current,
  ) {
    _requireTicket(ticket);
    final admitted = _authority;
    if (admitted == null ||
        admitted.principalId != current.principalId ||
        admitted.organizationId != current.organizationId ||
        admitted.organizationMembershipGeneration !=
            current.organizationMembershipGeneration ||
        admitted.offlinePolicy != current.offlinePolicy ||
        admitted.offlinePolicyVersion != current.offlinePolicyVersion) {
      throw StateError('Source authority changed');
    }
  }

  bool owns(AutoFillSourceTicket ticket) =>
      identical(ticket._identity, _identity) &&
      ticket._revision == _revision &&
      ticket.sessionId == _sessionId &&
      ticket.sourceEpoch == _epoch;

  AutoFillSourceTicket _currentTicket() {
    final session = _sessionId;
    final epoch = _epoch;
    final profile = _profileBinding;
    if (session == null || epoch == null || profile == null) {
      throw StateError('Source session unavailable');
    }
    return AutoFillSourceTicket._(
      session,
      epoch,
      profile,
      _identity,
      _revision,
    );
  }

  void _requireIdentity(Object identity) {
    if (!identical(identity, _identity)) {
      throw StateError('Source session changed');
    }
  }

  void _requireTicket(AutoFillSourceTicket expected) {
    _requireIdentity(expected._identity);
    if (expected._revision != _revision ||
        expected.sourceEpoch != _epoch ||
        expected.sessionId != _sessionId) {
      throw StateError('Source authority changed');
    }
  }
}
