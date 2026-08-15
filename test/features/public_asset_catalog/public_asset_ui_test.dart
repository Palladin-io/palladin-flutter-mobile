import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/theme/app_colors.dart';
import 'package:mobile_palladin/core/widgets/icon_color_browser_sheet.dart';
import 'package:mobile_palladin/core/widgets/upload_icon_button.dart';
import 'package:mobile_palladin/features/public_asset_catalog/domain/entities/public_asset.dart';
import 'package:mobile_palladin/features/public_asset_catalog/domain/repositories/public_asset_repository.dart';
import 'package:mobile_palladin/features/public_asset_catalog/domain/services/website_icon_service.dart';
import 'package:mobile_palladin/features/public_asset_catalog/presentation/website_icon_auto_resolver.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

void main() {
  test('auto resolver does not overwrite a manual selection', () async {
    final resolver = WebsiteIconAutoResolver(
      service: WebsiteIconService(_Repository()),
      debounce: Duration.zero,
      onReference: (_) {},
      onResolved: (_) => fail('manual selection must win'),
    );
    resolver.resolve('example.com');
    resolver.markManualSelection();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    resolver.dispose();
  });

  test('ensureNow preserves a selection marked before an edit save', () async {
    final repository = _AcquiringRepository();
    final resolver = WebsiteIconAutoResolver(
      service: WebsiteIconService(repository),
      onReference: (_) => fail('persisted selection must win'),
      onResolved: (_) => fail('persisted selection must win'),
    );

    resolver.markManualSelection();
    expect(await resolver.ensureNow('example.com'), isNull);
    expect(repository.calls, 0);
    resolver.dispose();
  });

  test('auto resolver applies only the latest URL result', () async {
    final repository = _DelayedRepository();
    final references = <String>[];
    final resolved = <String>[];
    final resolver = WebsiteIconAutoResolver(
      service: WebsiteIconService(repository),
      debounce: Duration.zero,
      onReference: references.add,
      onResolved: resolved.add,
    );

    resolver.resolve('first.example');
    await Future<void>.delayed(Duration.zero);
    resolver.resolve('second.example');
    await Future<void>.delayed(Duration.zero);

    repository.complete('second.example', _Repository.asset);
    await Future<void>.delayed(Duration.zero);
    repository.complete('first.example', _Repository.asset);
    await Future<void>.delayed(Duration.zero);

    expect(references, [_Repository.asset.reference]);
    expect(resolved, [_Repository.asset.reference]);
    resolver.dispose();
  });

  test(
    'auto resolver clears the previous host when the next has no icon',
    () async {
      final references = <String>[];
      var clears = 0;
      final resolver = WebsiteIconAutoResolver(
        service: WebsiteIconService(_HostSwitchRepository()),
        debounce: Duration.zero,
        onReference: references.add,
        onResolved: (_) {},
        onAutomaticCleared: () => clears++,
      );

      resolver.resolve('first.example');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      resolver.resolve('missing.example');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(references, [_Repository.asset.reference]);
      expect(clears, 1);
      resolver.dispose();
    },
  );

  test('KEY URL resolves https://stripe.com to a public asset', () async {
    final resolved = <String>[];
    final references = <String>[];
    final resolver = WebsiteIconAutoResolver(
      service: WebsiteIconService(_StripeRepository()),
      debounce: Duration.zero,
      onReference: references.add,
      onResolved: resolved.add,
    );

    resolver.resolve('https://stripe.com');
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(references, [_StripeRepository.asset.reference]);
    expect(resolved, [_StripeRepository.asset.reference]);
    resolver.dispose();
  });

  test(
    'missing website icon is reserved in one request without polling',
    () async {
      final repository = _AcquiringRepository();
      final resolved = <String>[];
      final resolver = WebsiteIconAutoResolver(
        service: WebsiteIconService(repository),
        debounce: Duration.zero,
        onReference: (_) {},
        onResolved: resolved.add,
      );

      resolver.resolve('new.example.com');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(repository.calls, 1);
      expect(resolved, [_Repository.asset.reference]);
      resolver.dispose();
    },
  );

  test(
    'auto resolver waits briefly for a pending icon to become ready',
    () async {
      final repository = _PendingThenReadyRepository();
      final resolved = <String>[];
      final resolver = WebsiteIconAutoResolver(
        service: WebsiteIconService(repository, pollInterval: Duration.zero),
        debounce: Duration.zero,
        previewTimeout: const Duration(seconds: 1),
        onReference: (_) {},
        onResolved: resolved.add,
      );

      resolver.resolve('new.example.com');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(repository.calls, 2);
      expect(resolved, [_Repository.asset.reference]);
      resolver.dispose();
    },
  );

  test('auto resolver cancels polling for a stale URL', () async {
    final repository = _AlwaysPendingRepository();
    final resolver = WebsiteIconAutoResolver(
      service: WebsiteIconService(
        repository,
        pollInterval: const Duration(milliseconds: 5),
      ),
      debounce: Duration.zero,
      previewTimeout: const Duration(seconds: 1),
      onReference: (_) {},
      onResolved: (_) {},
    );

    resolver.resolve('first.example.com');
    await Future<void>.delayed(const Duration(milliseconds: 2));
    resolver.resolve('second.example.com');
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(repository.calls['first.example.com'], 1);
    expect(repository.calls['second.example.com'], greaterThan(1));
    resolver.dispose();
  });

  test(
    'ensureNow cancels debounce and returns the reference before save',
    () async {
      final repository = _AcquiringRepository();
      final references = <String>[];
      final resolver = WebsiteIconAutoResolver(
        service: WebsiteIconService(repository),
        debounce: const Duration(seconds: 10),
        onReference: references.add,
        onResolved: (_) {},
      );

      resolver.resolve('new.example.com');
      final reference = await resolver.ensureNow('new.example.com');

      expect(reference, _Repository.asset.reference);
      expect(references, [_Repository.asset.reference]);
      expect(repository.calls, 1);
      resolver.dispose();
    },
  );

  testWidgets('icon browser exposes manual website icon search', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: IconColorBrowserSheet(
            icons: const [],
            colorOptions: const [AppColors.brandRed],
            initialIconKey: null,
            initialColor: AppColors.brandRed,
            title: 'Icons',
            confirmLabel: 'Choose',
            onPickPublicAsset: () async {
              opened = true;
              return 'public-asset:asset-id';
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Search website icons'));
    await tester.pump();
    expect(opened, isTrue);
    expect(find.text('Choose'), findsOneWidget);
  });

  testWidgets('icon browser exposes manual encrypted icon upload', (
    tester,
  ) async {
    var picked = false;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: IconColorBrowserSheet(
            icons: const [],
            colorOptions: const [AppColors.brandRed],
            initialIconKey: null,
            initialColor: AppColors.brandRed,
            title: 'Icons',
            confirmLabel: 'Choose',
            onPickCustom: () async {
              picked = true;
              return 'file:///private/icon.png';
            },
          ),
        ),
      ),
    );

    expect(find.byType(UploadIconButton), findsOneWidget);
    await tester.tap(find.text('Upload custom icon'));
    await tester.pump();
    expect(picked, isTrue);
  });
}

class _Repository implements PublicAssetRepository {
  static final asset = PublicAsset(
    id: 'asset-id',
    type: 'website-icon',
    name: 'Example',
    revision: 1,
    deliveryUrl: Uri.parse('https://assets.palladin.io/example.webp'),
  );

  @override
  Future<PublicAsset?> getById(String assetId, {int? revision}) async => asset;

  @override
  Future<WebsiteIconEnsureResult> ensureWebsiteIcons(
    Iterable<String> hostnames,
  ) async => _ready({'example.com': asset});

  @override
  Future<List<PublicAsset>> searchWebsiteIcons(String query) async => [asset];
}

class _DelayedRepository implements PublicAssetRepository {
  final _resolutions = <String, Completer<WebsiteIconEnsureResult>>{};

  void complete(String hostname, PublicAsset asset) {
    _resolutions[hostname]!.complete(_ready({hostname: asset}));
  }

  @override
  Future<PublicAsset?> getById(String assetId, {int? revision}) async => null;

  @override
  Future<WebsiteIconEnsureResult> ensureWebsiteIcons(
    Iterable<String> hostnames,
  ) {
    final hostname = hostnames.single;
    return (_resolutions[hostname] ??= Completer<WebsiteIconEnsureResult>())
        .future;
  }

  @override
  Future<List<PublicAsset>> searchWebsiteIcons(String query) async => const [];
}

class _HostSwitchRepository implements PublicAssetRepository {
  @override
  Future<PublicAsset?> getById(String assetId, {int? revision}) async => null;

  @override
  Future<WebsiteIconEnsureResult> ensureWebsiteIcons(
    Iterable<String> hostnames,
  ) async {
    final hostname = hostnames.single;
    return hostname == 'first.example'
        ? _ready({hostname: _Repository.asset})
        : WebsiteIconEnsureResult(
            assets: const {},
            statuses: {hostname: WebsiteIconEnsureStatus.failed},
          );
  }

  @override
  Future<List<PublicAsset>> searchWebsiteIcons(String query) async => const [];
}

class _AcquiringRepository implements PublicAssetRepository {
  int calls = 0;

  @override
  Future<PublicAsset?> getById(String assetId, {int? revision}) async => null;

  @override
  Future<WebsiteIconEnsureResult> ensureWebsiteIcons(
    Iterable<String> hostnames,
  ) async {
    calls++;
    return _ready({hostnames.single: _Repository.asset});
  }

  @override
  Future<List<PublicAsset>> searchWebsiteIcons(String query) async => const [];
}

class _PendingThenReadyRepository implements PublicAssetRepository {
  int calls = 0;

  @override
  Future<PublicAsset?> getById(String assetId, {int? revision}) async => null;

  @override
  Future<WebsiteIconEnsureResult> ensureWebsiteIcons(
    Iterable<String> hostnames,
  ) async {
    calls++;
    final hostname = hostnames.single;
    if (calls == 1) {
      return WebsiteIconEnsureResult(
        assets: const {},
        statuses: {hostname: WebsiteIconEnsureStatus.pending},
      );
    }
    return _ready({hostname: _Repository.asset});
  }

  @override
  Future<List<PublicAsset>> searchWebsiteIcons(String query) async => const [];
}

class _AlwaysPendingRepository implements PublicAssetRepository {
  final calls = <String, int>{};

  @override
  Future<PublicAsset?> getById(String assetId, {int? revision}) async => null;

  @override
  Future<WebsiteIconEnsureResult> ensureWebsiteIcons(
    Iterable<String> hostnames,
  ) async {
    final hostname = hostnames.single;
    calls.update(hostname, (value) => value + 1, ifAbsent: () => 1);
    return WebsiteIconEnsureResult(
      assets: const {},
      statuses: {hostname: WebsiteIconEnsureStatus.pending},
    );
  }

  @override
  Future<List<PublicAsset>> searchWebsiteIcons(String query) async => const [];
}

class _StripeRepository implements PublicAssetRepository {
  static final asset = PublicAsset(
    id: 'stripe-icon',
    type: 'website-icon',
    name: 'Stripe',
    revision: 1,
    deliveryUrl: Uri.parse('https://assets.palladin.io/stripe.webp'),
  );

  @override
  Future<PublicAsset?> getById(String assetId, {int? revision}) async => asset;

  @override
  Future<WebsiteIconEnsureResult> ensureWebsiteIcons(
    Iterable<String> hostnames,
  ) async {
    expect(hostnames, ['stripe.com']);
    return _ready({'stripe.com': asset});
  }

  @override
  Future<List<PublicAsset>> searchWebsiteIcons(String query) async => const [];
}

WebsiteIconEnsureResult _ready(Map<String, PublicAsset> assets) =>
    WebsiteIconEnsureResult(
      assets: assets,
      statuses: {
        for (final hostname in assets.keys)
          hostname: WebsiteIconEnsureStatus.ready,
      },
    );
