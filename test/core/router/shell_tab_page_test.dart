import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_palladin/core/router/shell_tab_page.dart';

const _paths = ['/vaults', '/agents', '/', '/inbox'];

GoRouter _router() => GoRouter(
  initialLocation: '/vaults',
  routes: [
    ShellRoute(
      builder: (context, state, child) => Scaffold(
        body: child,
        bottomNavigationBar: Row(
          key: const ValueKey('navbar'),
          children: [
            for (var index = 0; index < _paths.length; index++)
              TextButton(
                onPressed: () => context.go(
                  _paths[index],
                  extra: ShellTabDirection.between(
                    _paths.indexOf(state.uri.path),
                    index,
                  ),
                ),
                child: Text('Tab $index'),
              ),
          ],
        ),
      ),
      routes: [
        for (var index = 0; index < _paths.length; index++)
          GoRoute(
            path: _paths[index],
            pageBuilder: (context, state) => ShellTabPage(
              pageKey: state.pageKey,
              direction:
                  state.extra as ShellTabDirection? ?? ShellTabDirection.none,
              disableAnimations: MediaQuery.disableAnimationsOf(context),
              child: Center(child: Text('Page $index')),
            ),
          ),
      ],
    ),
  ],
);

Future<GoRouter> _pumpRouter(
  WidgetTester tester, {
  bool reducedMotion = false,
}) async {
  final router = _router();
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
        child: child!,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets(
    'incoming page follows the tapped side while navbar stays fixed',
    (tester) async {
      await _pumpRouter(tester);
      final center = tester.getCenter(find.text('Page 0')).dx;
      final navbar = tester.getTopLeft(find.byKey(const ValueKey('navbar')));
      await tester.tap(find.text('Tab 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.getCenter(find.text('Page 1')).dx, greaterThan(center));
      expect(tester.getTopLeft(find.byKey(const ValueKey('navbar'))), navbar);
      await tester.pumpAndSettle();
      expect(tester.getCenter(find.text('Page 1')).dx, closeTo(center, 0.1));

      await tester.tap(find.text('Tab 0'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.getCenter(find.text('Page 0')).dx, lessThan(center));
      await tester.pumpAndSettle();
      expect(tester.getCenter(find.text('Page 0')).dx, closeTo(center, 0.1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('rapid reversals settle on the last selected tab', (
    tester,
  ) async {
    final router = await _pumpRouter(tester);
    for (final index in [3, 1, 2, 0]) {
      await tester.tap(find.text('Tab $index'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 35));
    }
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/vaults');
    expect(find.text('Page 0'), findsOneWidget);
    expect(find.text('Page 3'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion switches without moving the page', (
    tester,
  ) async {
    await _pumpRouter(tester, reducedMotion: true);
    final center = tester.getCenter(find.text('Page 0')).dx;
    await tester.tap(find.text('Tab 3'));
    await tester.pump();
    expect(tester.getCenter(find.text('Page 3')).dx, closeTo(center, 0.1));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('direct navigation and reselection have no slide', (
    tester,
  ) async {
    final router = await _pumpRouter(tester);
    final center = tester.getCenter(find.text('Page 0')).dx;
    router.go('/inbox');
    await tester.pump();
    expect(tester.getCenter(find.text('Page 3')).dx, closeTo(center, 0.1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tab 3'));
    await tester.pump();
    expect(tester.getCenter(find.text('Page 3')).dx, closeTo(center, 0.1));
    expect(tester.takeException(), isNull);
  });
}
