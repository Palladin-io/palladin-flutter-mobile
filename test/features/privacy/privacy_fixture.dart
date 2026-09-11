import 'dart:async';
import 'package:dio/dio.dart';
import 'package:mobile_palladin/features/privacy/data/consent_activation_store.dart';
import 'package:mobile_palladin/features/privacy/data/consent_remote_datasource.dart';
import 'package:mobile_palladin/features/privacy/domain/user_consent.dart';

UserConsent consent({
  String status = 'unknown',
  int revision = 0,
  int activationRevision = 0,
}) => UserConsent(
  purpose: 'product_analytics',
  scope: 'palladin_web_mobile',
  status: status,
  revision: revision,
  activationRevision: activationRevision,
  noticeVersion: revision == 0 ? null : 'test-v1',
  noticeLocale: revision == 0 ? null : 'en',
  currentNotice: const ConsentNotice(
    version: 'test-v1',
    locale: 'en',
    text: 'Test analytics notice',
  ),
);

class Remote extends ConsentRemoteDataSource {
  Remote() : super(Dio());
  UserConsent current = consent();
  final List<ConsentDecision> decisions = [];
  Completer<UserConsent>? pending;
  Completer<UserConsents>? pendingRead;
  bool networkFails = false;
  @override
  Future<UserConsents> get(String locale, {CancelToken? cancelToken}) async {
    if (networkFails) throw StateError('network');
    return pendingRead == null
        ? UserConsents([current], 60)
        : pendingRead!.future;
  }

  @override
  Future<UserConsent> decide(
    ConsentDecision decision, {
    CancelToken? cancelToken,
  }) async {
    decisions.add(decision);
    if (networkFails) throw StateError('network');
    if (pending != null) return pending!.future;
    current = consent(
      status: decision.granted ? 'granted' : 'withdrawn',
      revision: decision.expectedRevision + 1,
      activationRevision: decision.granted ? decision.expectedRevision + 1 : 0,
    );
    return current;
  }
}

class FailingStore extends ConsentActivationStore {
  @override
  Future<ConsentActivation?> read(String userId) async => null;

  @override
  Future<void> write(String userId, ConsentActivation? activation) async =>
      throw StateError('storage');
}

class MemoryActivationStore extends ConsentActivationStore {
  final _values = <String, ConsentActivation>{};
  @override
  Future<ConsentActivation?> read(String userId) async => _values[userId];
  @override
  Future<void> write(String userId, ConsentActivation? activation) async {
    if (activation == null) {
      _values.remove(userId);
    } else {
      _values[userId] = activation;
    }
  }
}
