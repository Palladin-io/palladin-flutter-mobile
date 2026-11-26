import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/public_asset_catalog/domain/services/website_icon_service.dart';
import 'package:mobile_palladin/features/public_asset_catalog/presentation/widgets/public_asset_image.dart';
import 'package:mobile_palladin/features/vault/domain/entities/sign_in_method.dart';

import '../../design/mobile/asset_adapters.dart';

void main() {
  test(
    'catalog supplies local image routes and unknown sites terminate',
    () async {
      final catalog = PreviewPublicAssetRepository();
      final icons = WebsiteIconService(catalog);
      final result = await icons.ensureBatchUntilResolved([
        'github.com',
        'google.com',
        'notion.so',
        'figma.com',
        'missing.example',
      ]);
      expect(result.length, 4);
      for (final asset in result.values) {
        final uri = publicAssetContentUrl(
          'http://localhost:4444',
          asset.id,
          asset.revision,
        )!;
        expect(uri.origin, 'http://localhost:4444');
        final bytes = File('design/mobile/public${uri.path}').readAsBytesSync();
        expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
        expect((await catalog.getById(asset.id))?.reference, asset.reference);
      }
      expect((await icons.search('GitHub')).single.name, 'GitHub');
    },
  );

  test(
    'provider choices stay scoped and serialize through actual field parser',
    () async {
      final candidates = PreviewSignInCandidates();
      final google = await candidates.candidates(
        provider: SignInProvider.google,
        vaultIds: ['vault-personal'],
        memberPrivateKey: Uint8List(32),
      );
      expect(google.single.label, 'Google');
      final value = SignInMethodBinding(
        provider: SignInProvider.google,
        account: google.single.account,
        entry: google.single.reference,
      ).toValue();
      expect(
        SignInMethodField.parseValue(value)?.entry,
        google.single.reference,
      );
      expect(
        await candidates.candidates(
          provider: SignInProvider.google,
          vaultIds: ['vault-work'],
          memberPrivateKey: Uint8List(32),
        ),
        isEmpty,
      );
    },
  );
}
