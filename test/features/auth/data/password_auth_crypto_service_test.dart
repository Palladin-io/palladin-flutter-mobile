import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/unlock/data/services/identity_kdf_service.dart';

void main() {
  test('password authentication accepts only the frozen v1 profile', () {
    expect(IdentityKdfProfile.securityVersion, 1);
    expect(IdentityKdfProfile.id, 'identity-argon2id-password-v1');
    expect(IdentityKdfProfile.memoryKiB, 32768);
    expect(IdentityKdfProfile.iterations, 2);
    expect(IdentityKdfProfile.parallelism, 1);
    expect(IdentityKdfProfile.outputBytes, 32);
  });
}
