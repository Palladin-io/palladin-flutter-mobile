import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/config/env_config.dart';
import 'package:mobile_palladin/core/di/injection.dart';
import 'package:mobile_palladin/features/public_asset_catalog/presentation/widgets/public_asset_image.dart';

import 'package:mobile_palladin/features/vault/domain/entities/vault_entity.dart';
import 'package:mobile_palladin/features/vault/presentation/widgets/vault_card.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

const assetId = '11111111-1111-4111-8111-111111111111';

void main() {
  tearDown(() => getIt.reset());

  for (final config in [
    EnvConfig.staging(apiBaseUrl: 'https://stage.example.test'),
    EnvConfig.production(
      useStagingBackend: true,
      apiBaseUrl: 'https://stage.example.test',
    ),
  ]) {
    testWidgets('loads the published revision from staging for ${config.flavor}', (
      tester,
    ) async {
      getIt.registerSingleton<EnvConfig>(config);
      final icon =
          'public-asset:$assetId|1|${Uri.encodeComponent('https://untrusted.example/tracker.png')}';
      await tester.pumpWidget(
        MaterialApp(
          home: PublicAssetImage(reference: icon, fallback: const SizedBox()),
        ),
      );
      await tester.pump();
      final image = tester.widget<Image>(find.byType(Image));
      expect(
        (image.image as NetworkImage).url,
        'https://stage.example.test/api/public-assets/$assetId/revisions/1/content',
      );
    });
  }

  testWidgets('Vault cards render their public catalog icon', (tester) async {
    getIt.registerSingleton<EnvConfig>(
      EnvConfig.staging(apiBaseUrl: 'https://stage.example.test'),
    );
    final icon =
        'public-asset:$assetId|1|${Uri.encodeComponent('https://old-cdn.example/icon.png')}';
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: VaultCard(
            vault: VaultEntity(
              id: 'vault-id',
              name: 'Synthetic vault',
              icon: icon,
              grantMode: GrantMode.granular,
              createdAt: DateTime.utc(2026),
              updatedAt: DateTime.utc(2026),
              entryCount: 0,
              activeGrantCount: 0,
              memberCount: 1,
            ),
            onTap: () {},
          ),
        ),
      ),
    );
    expect(find.byType(PublicAssetImage), findsOneWidget);
    await tester.pump();
    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as NetworkImage).url,
      'https://stage.example.test/api/public-assets/$assetId/revisions/1/content',
    );
  });

  test('self-hosted API path is preserved independently of a CDN host', () {
    final config = EnvConfig.staging(
      apiBaseUrl: 'https://vault.example/palladin/',
    );
    expect(
      publicAssetContentUrl(config.apiBaseUrl, assetId, 2).toString(),
      'https://vault.example/palladin/api/public-assets/$assetId/revisions/2/content',
    );
  });

  test('a decrypted reference cannot inject another route', () {
    expect(
      publicAssetContentUrl('https://vault.example', '../../track', 1),
      isNull,
    );
    expect(publicAssetContentUrl('https://vault.example', assetId, 0), isNull);
  });
}
