import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/vault/data/datasources/entry_sharing_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/services/canonical_entry_detail_service.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_sharing/entry_share_crypto_service.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_sharing/entry_share_secrets.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_share.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_share_creation.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_share_list.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/entry_share_creation_cubit.dart';
import 'package:sodium/sodium_sumo.dart' as sodium_ffi;
import 'package:sodium_libs/sodium_libs_sumo.dart';

class _Remote extends Mock implements EntrySharingRemoteDatasource {}

const _shareId = '00112233-4455-4677-8899-aabbccddeeff';
const _organizationId = '11112233-4455-4677-8899-aabbccddeeff';
const _vaultId = '22112233-4455-4677-8899-aabbccddeeff';
const _entryId = '33112233-4455-4677-8899-aabbccddeeff';
const _revision = '9007199254740993';
const _session = (
  principalId: 'member',
  organizationId: _organizationId,
  authorizationGeneration: '1',
  keyGeneration: 1,
);
const _challenge = EntryShareCreationChallenge(
  shareId: _shareId,
  sourceRevision: _revision,
  expiresAt: '2026-09-20T12:05:00Z',
);
final _now = DateTime.utc(2026, 9, 20, 12);
final _expected = EntryEntity(
  id: _entryId,
  vaultId: _vaultId,
  label: 'index-label',
  type: EntryType.credential,
  createdAt: _now,
  updatedAt: _now,
  currentRevision: _revision,
);
CanonicalEntrySnapshot _source([Map<String, dynamic> changes = const {}]) =>
    CanonicalEntrySnapshot(
      entry: {
        'id': _entryId,
        'vaultId': _vaultId,
        'organizationId': _organizationId,
        'currentRevision': _revision,
        ...changes,
      },
      secret: {'entryType': 1, 'memberLabel': 'verified title'},
      payload: {
        'username': 'synthetic-user',
        'password': 'synthetic-secret',
        'notes': 'private-note',
      },
    );
final _options = EntryShareCreationOptions.fromInput(
  recipientEmail: 'recipient@example.test',
  protection: EntryShareProtection.pin,
  protectionSecret: '012345',
  lifetimeHours: 1,
  notifyOnFirstReceipt: true,
);

void main() {
  late SodiumSumo sodium;
  late _Remote remote;
  late EntrySharingSession? current;
  late Future<CanonicalEntrySnapshot> Function() sourceReader;
  late Future<SodiumSumo> Function() sodiumReader;
  late EntryShareCreationCubit cubit;
  final requests = <EntryShareCreationRequest>[];
  setUpAll(() async {
    registerFallbackValue(CancelToken());
    registerFallbackValue(
      EntryShareCreationRequest(
        shareId: _shareId,
        sourceRevision: _revision,
        expiresAt: _challenge.expiresAt,
        options: _options,
        accessToken: 'synthetic',
        packet: const EntryShareCiphertext(
          nonce: 'synthetic',
          ciphertext: 'synthetic',
        ),
      ),
    );
    final configured = Platform.environment['PALLADIN_LIBSODIUM_PATH'];
    sodium = configured != null || Platform.isLinux
        ? await sodium_ffi.SodiumSumoInit.init(
            () => DynamicLibrary.open(configured ?? 'libsodium.so'),
          )
        : await SodiumSumoInit.init();
  });
  EntryShareCreationCubit build({DateTime Function()? now}) =>
      EntryShareCreationCubit(
        remote: remote,
        crypto: EntryShareCryptoService(sodiumLoader: () => sodiumReader()),
        expected: _expected,
        sessionReader: () async => current,
        sourceReader: () => sourceReader(),
        now: now ?? () => _now,
      );
  setUp(() {
    current = _session;
    remote = _Remote();
    requests.clear();
    sourceReader = () async => _source();
    sodiumReader = () async => sodium;
    when(
      () => remote.challenge(
        any(),
        any(),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async => _challenge);
    when(
      () => remote.create(
        any(),
        any(),
        any(),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((invocation) async {
      requests.add(
        invocation.positionalArguments[2] as EntryShareCreationRequest,
      );
    });
    cubit = build();
  });
  tearDown(() => cubit.close());
  Future<void> create() =>
      cubit.create(options: _options, selectedIds: ['credential.password']);

  test(
    'opens authoritative selection and clears original plaintext maps',
    () async {
      final source = _source();
      sourceReader = () async => source;
      await cubit.load();
      expect(cubit.state.phase, EntryShareCreationPhase.ready);
      expect(cubit.state.selection!.title, 'verified title');
      expect(source.entry, isEmpty);
      expect(source.secret, isEmpty);
      expect(source.payload, isEmpty);
      verifyNever(
        () => remote.challenge(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
        ),
      );
    },
  );

  test(
    'creates fresh decryptable snapshot using independently bound scope',
    () async {
      await cubit.load();
      await create();
      expect(cubit.state.phase, EntryShareCreationPhase.created);
      expect(cubit.state.selection, isNull);
      expect(cubit.state.shareId, _shareId);
      final request = requests.single;
      expect(request.expiresAt, '2026-09-20T13:00:00.000Z');
      expect(request.sourceRevision, _revision);
      final secrets = EntryShareSecrets.fromFragment(cubit.state.fragment!);
      try {
        final snapshot =
            await EntryShareCryptoService(
              sodiumLoader: () async => sodium,
            ).open(
              packet: request.packet,
              authority: EntryShareScope(
                shareId: _shareId,
                organizationId: _organizationId,
                vaultId: _vaultId,
                entryId: _entryId,
                sourceRevision: _revision,
                expiresAt: request.expiresAt,
              ),
              requestedShareId: _shareId,
              key: secrets.key,
            );
        expect(snapshot.title, 'verified title');
        expect(snapshot.fields.single.id, 'credential.password');
        expect(snapshot.fields.single.value, 'synthetic-secret');
      } finally {
        secrets.dispose();
      }
      await create();
      await cubit.retry();
      expect(requests, hasLength(1));
    },
  );

  test(
    'ambiguous failure freezes exact request; retry neither challenges nor encrypts again',
    () async {
      var preparations = 0;
      sodiumReader = () async {
        preparations++;
        return sodium;
      };
      when(
        () => remote.create(
          any(),
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((invocation) async {
        requests.add(
          invocation.positionalArguments[2] as EntryShareCreationRequest,
        );
        if (requests.length == 1) throw const EntrySharingRequestException();
      });
      await cubit.load();
      await create();
      expect(cubit.state.phase, EntryShareCreationPhase.retry);
      expect(cubit.state.selection, isNull);
      await cubit.create(
        options: EntryShareCreationOptions.fromInput(
          recipientMode: EntryShareRecipientMode.anyoneWithLink,
        ),
        selectedIds: ['notes'],
      );
      expect(requests, hasLength(1));
      await cubit.retry();
      expect(cubit.state.phase, EntryShareCreationPhase.created);
      expect(requests, hasLength(2));
      expect(requests.last, same(requests.first));
      expect(preparations, 1);
      verify(
        () => remote.challenge(
          _vaultId,
          _entryId,
          cancelToken: any(named: 'cancelToken'),
        ),
      ).called(1);
    },
  );

  test('mismatched source challenge stops before crypto or POST', () async {
    when(
      () => remote.challenge(
        any(),
        any(),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer(
      (_) async => const EntryShareCreationChallenge(
        shareId: _shareId,
        sourceRevision: '9007199254740994',
        expiresAt: '2026-09-20T12:05:00Z',
      ),
    );
    sodiumReader = () => throw StateError('Must not encrypt');
    await cubit.load();
    await create();
    expect(cubit.state.phase, EntryShareCreationPhase.unavailable);
    expect(cubit.state.failure, EntryShareCreationFailure.sourceChanged);
    expect(cubit.state.selection, isNull);
    expect(requests, isEmpty);
  });

  for (final change in <Map<String, dynamic>>[
    {'id': _shareId},
    {'vaultId': _shareId},
    {'organizationId': _shareId},
    {'currentRevision': '1'},
  ]) {
    test(
      'source binding rejects ${change.keys.single} substitution and clears maps',
      () async {
        final source = _source(change);
        sourceReader = () async => source;
        await cubit.load();
        expect(cubit.state.phase, EntryShareCreationPhase.unavailable);
        expect(source.payload, isEmpty);
        expect(requests, isEmpty);
      },
    );
  }

  test('clear during source read cannot restore secret choices', () async {
    final pending = Completer<CanonicalEntrySnapshot>();
    final source = _source();
    sourceReader = () => pending.future;
    final loading = cubit.load();
    await Future<void>.delayed(Duration.zero);
    cubit.clear();
    pending.complete(source);
    await loading;
    expect(cubit.state.phase, EntryShareCreationPhase.unavailable);
    expect(cubit.state.selection, isNull);
    expect(source.payload, isEmpty);
  });

  test(
    'clear during challenge cancels token and rejects late response',
    () async {
      final pending = Completer<EntryShareCreationChallenge>();
      CancelToken? token;
      when(
        () => remote.challenge(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((invocation) {
        token = invocation.namedArguments[#cancelToken] as CancelToken;
        return pending.future;
      });
      await cubit.load();
      final creating = create();
      await untilCalled(
        () => remote.challenge(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
        ),
      );
      cubit.clear();
      expect(token!.isCancelled, isTrue);
      pending.complete(_challenge);
      await creating;
      expect(requests, isEmpty);
      expect(cubit.state.fragment, isNull);
    },
  );

  test(
    'clear while sodium starts disposes late material instead of publishing',
    () async {
      final pending = Completer<SodiumSumo>();
      final entered = Completer<void>();
      sodiumReader = () {
        entered.complete();
        return pending.future;
      };
      await cubit.load();
      final creating = create();
      await entered.future;
      cubit.clear();
      pending.complete(sodium);
      await creating;
      expect(requests, isEmpty);
      expect(cubit.state.phase, EntryShareCreationPhase.unavailable);
      expect(cubit.state.fragment, isNull);
    },
  );

  for (final fails in [false, true]) {
    test(
      'session replacement during POST cannot publish ${fails ? 'retry' : 'link'}',
      () async {
        final pending = Completer<void>();
        when(
          () => remote.create(
            any(),
            any(),
            any(),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer((_) => pending.future);
        await cubit.load();
        final creating = create();
        await untilCalled(
          () => remote.create(
            any(),
            any(),
            any(),
            cancelToken: any(named: 'cancelToken'),
          ),
        );
        current = (
          principalId: 'replacement',
          organizationId: _organizationId,
          authorizationGeneration: '1',
          keyGeneration: 1,
        );
        if (fails) {
          pending.completeError(const EntrySharingRequestException());
        } else {
          pending.complete();
        }
        await creating;
        expect(cubit.state.phase, EntryShareCreationPhase.unavailable);
        expect(cubit.state.fragment, isNull);
        expect(cubit.state.selection, isNull);
      },
    );
  }

  test(
    'session replacement on source failure does not restore initial retry state',
    () async {
      final pending = Completer<CanonicalEntrySnapshot>();
      sourceReader = () => pending.future;
      final loading = cubit.load();
      await Future<void>.delayed(Duration.zero);
      current = null;
      pending.completeError(StateError('source failed'));
      await loading;
      expect(cubit.state.phase, EntryShareCreationPhase.unavailable);
    },
  );

  test(
    'concurrent taps send one operation and invalid selection makes no request',
    () async {
      await cubit.load();
      await cubit.create(options: _options, selectedIds: ['notes', 'notes']);
      expect(cubit.state.failure, EntryShareCreationFailure.invalidSelection);
      await Future.wait([create(), create()]);
      expect(requests, hasLength(1));
    },
  );

  test(
    'expiry drops the returned fragment and pending retry material',
    () async {
      await cubit.close();
      for (final fails in [false, true]) {
        fakeAsync((clock) {
          when(
            () => remote.create(
              any(),
              any(),
              any(),
              cancelToken: any(named: 'cancelToken'),
            ),
          ).thenAnswer((_) async {
            if (fails) throw const EntrySharingRequestException();
          });
          final timed = build(now: () => _now.add(clock.elapsed));
          unawaited(timed.load());
          clock.flushMicrotasks();
          unawaited(
            timed.create(
              options: _options,
              selectedIds: ['credential.password'],
            ),
          );
          clock.flushMicrotasks();
          expect(
            timed.state.phase,
            fails
                ? EntryShareCreationPhase.retry
                : EntryShareCreationPhase.created,
          );
          clock.elapse(const Duration(hours: 1));
          expect(timed.state.phase, EntryShareCreationPhase.unavailable);
          expect(timed.state.fragment, isNull);
          unawaited(timed.close());
          clock.flushMicrotasks();
        });
      }
    },
  );
}
