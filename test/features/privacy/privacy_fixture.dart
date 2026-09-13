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
  Completer<void>? readStarted;
  bool networkFails = false;
  int? writeStatus;
  bool failReadAfterWrite = false;
  @override
  Future<UserConsents> get(String locale, {CancelToken? cancelToken}) async {
    if (networkFails) throw StateError('network');
    readStarted?.complete();
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
    if (writeStatus case final status?) throw consentHttpError(status);
    if (failReadAfterWrite) networkFails = true;
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

DioException consentHttpError(int status) {
  final options = RequestOptions(
    path: '/api/account/consents/product_analytics',
  );
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response(requestOptions: options, statusCode: status),
  );
}

class ControlledActivationStore extends MemoryActivationStore {
  bool failDelete = false;
  bool failActivation = false;
  Completer<ConsentActivation?>? pendingRead;
  Completer<void>? readStarted;
  Completer<void>? pendingActivation;
  Completer<void>? activationStarted;
  @override
  Future<ConsentActivation?> read(String userId) async {
    readStarted?.complete();
    return pendingRead == null ? super.read(userId) : pendingRead!.future;
  }

  @override
  Future<void> write(String userId, ConsentActivation? activation) async {
    if (activation == null && failDelete) throw StateError('delete');
    if (activation != null) {
      if (failActivation) throw StateError('activation');
      activationStarted?.complete();
      await pendingActivation?.future;
    }
    await super.write(userId, activation);
  }
}
