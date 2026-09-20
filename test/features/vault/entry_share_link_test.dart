import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/config/env_config.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_sharing/entry_share_link_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_share.dart';

void main() {
  final invalid = throwsA(isA<EntryShareException>());
  test('missing, insecure and non-origin configurations fail closed', () {
    for (final origin in [
      '',
      'http://stage.palladin.io',
      'https://stage.palladin.io/share',
      'https://stage.palladin.io?x=1',
      'https://stage.palladin.io#key=secret',
      'https://user@stage.palladin.io',
      ' https://stage.palladin.io',
      'https://stage.palladin.io:444',
      'https://stage.palladin.io.example.test',
      'https://api.stage.palladin.io',
    ]) {
      expect(
        () =>
            EntryShareLinkService(EnvConfig.staging(sharingWebOrigin: origin)),
        invalid,
      );
    }
  });
  test('store identity with staging backend uses staging, not production', () {
    final service = EntryShareLinkService(
      EnvConfig.production(
        useStagingBackend: true,
        sharingWebOrigin: 'https://stage.palladin.io',
      ),
    );
    expect(service.displayOrigin, 'https://stage.palladin.io');
    expect(
      () => EntryShareLinkService(
        EnvConfig.production(
          useStagingBackend: true,
          sharingWebOrigin: 'https://palladin.io',
        ),
      ),
      invalid,
    );
    expect(
      () => EntryShareLinkService(
        EnvConfig.production(sharingWebOrigin: 'https://stage.palladin.io'),
      ),
      invalid,
    );
    expect(
      () => EntryShareLinkService(
        EnvConfig.production(sharingWebOrigin: 'https://example.test'),
      ),
      invalid,
    );
  });
  test('local receiver origin is explicit and permits development HTTP', () {
    final service = EntryShareLinkService(
      EnvConfig.local(sharingWebOrigin: 'http://127.0.0.1:5173'),
    );
    final fragment = '#v=1&key=${'A' * 43}&access=${'A' * 43}';
    final link = service.create(
      shareId: '00112233-4455-4677-8899-aabbccddeeff',
      fragment: fragment,
    );
    expect(
      link,
      'http://127.0.0.1:5173/share/00112233-4455-4677-8899-aabbccddeeff$fragment',
    );
    expect(Uri.parse(link).query, isEmpty);
    expect(Uri.parse(link).fragment, fragment.substring(1));
  });
  test('link composition rejects paths and malformed secret fragments', () {
    final service = EntryShareLinkService(
      EnvConfig.staging(sharingWebOrigin: 'https://stage.palladin.io/'),
    );
    expect(
      () => service.create(
        shareId: '../elsewhere',
        fragment: '#v=1&key=${'A' * 43}&access=${'A' * 43}',
      ),
      invalid,
    );
    for (final fragment in [
      'key=plaintext',
      '#v=1&key=plaintext',
      '#v=1&key=${'A' * 43}&access=${'A' * 43}&extra=1',
    ]) {
      expect(
        () => service.create(
          shareId: '00112233-4455-4677-8899-aabbccddeeff',
          fragment: fragment,
        ),
        invalid,
      );
    }
  });
}
