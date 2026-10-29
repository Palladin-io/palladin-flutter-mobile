import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/config/env_config.dart';
import 'package:mobile_palladin/core/di/injection.dart';
import 'package:mobile_palladin/features/agents/presentation/widgets/agent_avatar.dart';

const _assetId = '11111111-1111-4111-8111-111111111111';

void main() {
  setUp(() {
    getIt.registerSingleton<EnvConfig>(
      EnvConfig.staging(apiBaseUrl: 'https://stage.example.test'),
    );
  });
  tearDown(() => getIt.reset());

  Future<void> pumpAvatar(WidgetTester tester, String iconKey) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AgentAvatar(agentId: 'a1', name: 'Agent', iconKey: iconKey),
          ),
        ),
      );

  testWidgets('uploaded icon loads only from the configured asset origin', (
    tester,
  ) async {
    final embedded = Uri.encodeComponent('https://untrusted.example/x.png');
    await pumpAvatar(tester, 'public-asset:$_assetId|1|$embedded');
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as NetworkImage).url,
      'https://stage.example.test/api/public-assets/$_assetId/revisions/1/content',
    );
  });

  for (final iconKey in [
    'https://untrusted.example/track.png',
    'http://untrusted.example/track.png',
    'http://127.0.0.1:8080/track.png?viewer=peer',
    'file:///data/user/0/io.palladin.mobile/avatar.png',
  ]) {
    testWidgets('server-supplied URL renders the letter avatar: $iconKey', (
      tester,
    ) async {
      await pumpAvatar(tester, iconKey);
      await tester.pump();

      // No Image means no NetworkImage/FileImage provider and no fetch.
      expect(find.byType(Image), findsNothing);
      expect(find.text('AG'), findsOneWidget);
    });
  }
}
