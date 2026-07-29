import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_fingerprint.dart';

void main() {
  group('VaultPublicKeyKind.parseWire', () {
    test('accepts the backend JSON enum and native numeric representation', () {
      expect(
        VaultPublicKeyKind.parseWire('memberX25519'),
        VaultPublicKeyKind.memberX25519,
      );
      expect(VaultPublicKeyKind.parseWire(5), VaultPublicKeyKind.memberX25519);
    });

    test(
      'fails closed for unknown names, numbers, and loose numeric strings',
      () {
        expect(
          () => VaultPublicKeyKind.parseWire('MemberX25519'),
          throwsFormatException,
        );
        expect(() => VaultPublicKeyKind.parseWire('5'), throwsFormatException);
        expect(() => VaultPublicKeyKind.parseWire(99), throwsFormatException);
        expect(() => VaultPublicKeyKind.parseWire(null), throwsFormatException);
      },
    );
  });
}
