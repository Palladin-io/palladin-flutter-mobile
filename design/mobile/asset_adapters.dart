import 'dart:typed_data';

import 'package:mobile_palladin/core/di/injection.dart';
import 'package:mobile_palladin/features/public_asset_catalog/domain/entities/public_asset.dart';
import 'package:mobile_palladin/features/public_asset_catalog/domain/repositories/public_asset_repository.dart';
import 'package:mobile_palladin/features/public_asset_catalog/domain/services/website_icon_service.dart';
import 'package:mobile_palladin/features/vault/data/services/sign_in_candidate_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';
import 'package:mobile_palladin/features/vault/domain/entities/member_index_entry.dart';
import 'package:mobile_palladin/features/vault/domain/entities/sign_in_method.dart';

import 'vault_adapters.dart';

/// IDs address bundled PNGs through the production PublicAssetImage route.
final previewPublicAssets = <String, PublicAsset>{
  for (final item in [
    ('github.com', 'GitHub', '10000000-0000-4000-8000-000000000001'),
    ('google.com', 'Google', '10000000-0000-4000-8000-000000000002'),
    ('notion.so', 'Notion', '10000000-0000-4000-8000-000000000003'),
    ('figma.com', 'Figma', '10000000-0000-4000-8000-000000000004'),
  ])
    item.$1: PublicAsset(
      id: item.$3,
      type: 'websiteIcon',
      name: item.$2,
      revision: 1,
      deliveryUrl: Uri.parse(
        '/api/public-assets/${item.$3}/revisions/1/content',
      ),
    ),
};

class PreviewPublicAssetRepository implements PublicAssetRepository {
  @override
  Future<List<PublicAsset>> searchWebsiteIcons(String query) async {
    final normalized = query.trim().toLowerCase();
    return previewPublicAssets.entries
        .where(
          (entry) =>
              entry.key.contains(normalized) ||
              entry.value.name.toLowerCase().contains(normalized),
        )
        .map((entry) => entry.value)
        .toList();
  }

  @override
  Future<WebsiteIconEnsureResult> ensureWebsiteIcons(
    Iterable<String> hostnames,
  ) async {
    final requested = hostnames.toSet();
    return WebsiteIconEnsureResult(
      assets: {for (final host in requested) host: ?previewPublicAssets[host]},
      statuses: {
        for (final host in requested)
          host: previewPublicAssets.containsKey(host)
              ? WebsiteIconEnsureStatus.ready
              : WebsiteIconEnsureStatus.failed,
      },
    );
  }

  @override
  Future<PublicAsset?> getById(String assetId, {int? revision}) async =>
      revision != null && revision != 1
      ? null
      : previewPublicAssets.values
            .where((asset) => asset.id == assetId)
            .firstOrNull;
}

// Linked sign-in fields use canonical UUID syntax even though preview routes
// retain human-readable fixture IDs. These aliases never leave this process.
const previewSignInReferences = <String, SignInEntryReference>{
  'entry-google': SignInEntryReference(
    vaultId: '20000000-0000-4000-8000-000000000001',
    entryId: '30000000-0000-4000-8000-000000000001',
  ),
  'entry-github': SignInEntryReference(
    vaultId: '20000000-0000-4000-8000-000000000002',
    entryId: '30000000-0000-4000-8000-000000000002',
  ),
};

class PreviewSignInCandidates implements SignInCandidateService {
  @override
  Future<List<SignInProviderCandidate>> candidates({
    required SignInProvider provider,
    required List<String> vaultIds,
    SignInEntryReference? exclude,
    required Uint8List memberPrivateKey,
  }) async {
    return vaultPreview.records.values
        .where(
          (entry) =>
              previewSignInReferences.containsKey(entry.id) &&
              vaultIds.contains(entry.vaultId) &&
              entry.type == EntryType.credential &&
              entry.lifecycleState == MemberEntryState.active &&
              provider.ownsHost(entry.urlDomain ?? '') &&
              entry.username?.isNotEmpty == true &&
              !(exclude?.vaultId == entry.vaultId &&
                  exclude?.entryId == entry.id),
        )
        .map(
          (entry) => SignInProviderCandidate(
            reference: previewSignInReferences[entry.id]!,
            label: entry.label,
            account: entry.username!,
          ),
        )
        .toList();
  }
}

Future<void> registerAssetPreview() async {
  Future<void> replace<T extends Object>(T instance) async {
    if (getIt.isRegistered<T>()) await getIt.unregister<T>();
    getIt.registerSingleton<T>(instance);
  }

  final catalog = PreviewPublicAssetRepository();
  await replace<PublicAssetRepository>(catalog);
  await replace<WebsiteIconService>(WebsiteIconService(catalog));
  await replace<SignInCandidateService>(PreviewSignInCandidates());
  for (final entry in vaultPreview.records.values.toList()) {
    final asset = previewPublicAssets[entry.urlDomain];
    if (asset != null) {
      vaultPreview.records[entry.id] = entry.copyWith(icon: asset.reference);
    }
  }
}
