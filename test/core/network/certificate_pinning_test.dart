import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/network/certificate_pinning.dart';

void main() {
  // A self-signed RSA-2048 certificate (openssl) and the base64 SHA-256 of its
  // SPKI, computed independently with:
  //   openssl x509 -in c.pem -pubkey -noout | openssl pkey -pubin -outform der \
  //     | openssl dgst -sha256 -binary | openssl enc -base64
  const certDerBase64 =
      'MIIDFzCCAf+gAwIBAgIUKE9dQb1ydVcX6Zb/5E2eSzakBz4wDQYJKoZIhvcNAQELBQAwGzEZMBcGA1UEAwwQdGVzdC5wYWxsYWRpbi5pbzAeFw0yNjA3MDMxMjQwMDVaFw0zNjA2MzAxMjQwMDVaMBsxGTAXBgNVBAMMEHRlc3QucGFsbGFkaW4uaW8wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDMqoTSuL3/jbUvL+UMNsO0xHQxMUprxZYtNXGfZq07Jy5XIz7aQ8c7fbLvaFdlaKnmm5fvJmJdwryCNlwnezjWVk1Snksri2MN/wmj8XrEDaS+GHeL+SMLjoHfyzoJCBUjj/G9mf0voB0UIoWjtxYk+GDwBs/qZuc5ne3cDq9vEKK07Ta4JrH23r2ygqah6n80YIYqfod8hRKV7Ejrdb3pK4ZPMCARqjDM8gMqZPGSDzjspMns2r0bggC0AuUOSyaNb134Xg5TfEbqMkP7KNtSCHHwPYmTg+q3mOWezkkfHazruvBtD0gebIeTJrQuqXSJPdqDyuNDrpl+AUDWWY1HAgMBAAGjUzBRMB0GA1UdDgQWBBSGkCAiqDwzgu+h7e+VG5HLd0Vl2zAfBgNVHSMEGDAWgBSGkCAiqDwzgu+h7e+VG5HLd0Vl2zAPBgNVHRMBAf8EBTADAQH/MA0GCSqGSIb3DQEBCwUAA4IBAQBSf9oGqLQ798jrcOeKZMg3D9IkqxRh3oyS+D+4RenQpmfVyxpGar2xH1pHLPQu4MkY2Fj1tAvZ2TkV82LhkCjtfXmsJ30hsBMJVcppI84Ck0JqWbgblpooba5Qjr6WnIy+C9jlkqvgZauAuQg08VB8c5zwZvfoPzvR2Hra/rMssOTR0J2qFt9OZMjkmCywKweiawp1KfABavj5cJOE5YSd6CkIhyQUie/uBuNweTH29EJ6CRtSn7rMu8HWaVaAszYvJSKlEbBrAtScEqI57pXTXYY/M4sMx1PqlbrmKKU6StDmLijjU1TaAOX9c2IXJxzCJMERnaLEje0a6FXTh58D';
  const expectedPin = 'CUb9qIvhPnIVVc7phZfQ6F+POQC+fN62zT6ufB+RBpo=';

  group('CertificatePinningService.spkiSha256Base64', () {
    test('extracts SPKI and matches the openssl-computed pin', () {
      final der = base64.decode(certDerBase64);
      expect(CertificatePinningService.spkiSha256Base64(der), expectedPin);
    });
  });

  group('CertificatePinningService (no cert)', () {
    test('is a no-op when no pins are configured', () {
      const service = CertificatePinningService([]);
      expect(service.isEnabled, isFalse);
      // Even a null certificate is accepted when pinning is disabled.
      expect(service.validateLeaf(null, 'api.palladin.io'), isTrue);
    });

    test('fails closed on a null certificate when pins are configured', () {
      const service = CertificatePinningService([expectedPin]);
      expect(service.isEnabled, isTrue);
      expect(service.validateLeaf(null, 'api.palladin.io'), isFalse);
    });
  });
}
