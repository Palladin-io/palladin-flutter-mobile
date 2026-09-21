import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/theme/app_spacing.dart';
import 'package:mobile_palladin/core/theme/app_colors.dart';
import 'package:mobile_palladin/core/widgets/app_fab.dart';
import 'package:mobile_palladin/core/widgets/app_fab_toast.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('close restores FAB and toast follows $brightness', (
      tester,
    ) async {
      final key = GlobalKey<AppFabToastState>();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
            floatingActionButton: AppFabToast(
              key: key,
              fab: AppFab.shell(onPressed: () {}, tooltip: 'Add'),
            ),
          ),
        ),
      );
      key.currentState!.show('Library hint');
      await tester.pumpAndSettle();
      expect(
        tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
        AppColors.modalBackground(brightness),
      );
      expect(
        tester.widget<Text>(find.text('Library hint')).style!.color,
        AppColors.onSurface(brightness),
      );
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byTooltip('Add'), findsOneWidget);
      key.currentState!.show('Next hint');
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Next hint'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('toast replaces FAB in place, then returns the current action', (
    tester,
  ) async {
    final key = GlobalKey<AppFabToastState>();
    var taps = 0;
    Widget frame({bool enabled = true, String label = 'Add'}) => MaterialApp(
      home: Scaffold(
        bottomNavigationBar: const SizedBox(height: 58),
        floatingActionButton: AppFabToast(
          key: key,
          enabled: enabled,
          fab: AppFab.shell(onPressed: () => taps++, tooltip: label),
        ),
      ),
    );
    await tester.pumpWidget(frame());
    final original = tester.getRect(find.byType(FloatingActionButton));
    key.currentState!.show('All entries across vaults');
    await tester.pump();
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('All entries across vaults'), findsNothing);
    await tester.pump(const Duration(milliseconds: 160));
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsNothing);
    final toast = tester.getRect(find.byType(SnackBar));
    expect(toast.overlaps(original), isTrue);
    expect(toast.right, original.right);
    expect(toast.bottom, original.bottom);
    await tester.pumpWidget(frame(label: 'Add vault'));
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byTooltip('Add vault'), findsOneWidget);
    expect(tester.getRect(find.byType(FloatingActionButton)), original);
    await tester.tap(find.byType(FloatingActionButton));
    expect(taps, 1);
    key.currentState!.show('New hint');
    await tester.pumpAndSettle();
    await tester.pumpWidget(frame(enabled: false));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('latest hint wins and reduced motion skips fades', (
    tester,
  ) async {
    final key = GlobalKey<AppFabToastState>();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            disableAnimations: true,
          ),
          child: Scaffold(
            floatingActionButton: AppFabToast(
              key: key,
              fab: AppFab.shell(onPressed: () {}, tooltip: 'Add'),
            ),
          ),
        ),
      ),
    );
    key.currentState!.show('Entries');
    key.currentState!.show('Vaults');
    await tester.pump();
    expect(find.text('Vaults'), findsOneWidget);
    expect(find.text('Entries'), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shell FAB matches established screen inset', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              AppFab.shell(onPressed: () {}, tooltip: 'Library'),
              Padding(
                padding: const EdgeInsets.only(
                  right: AppSpacing.xs,
                  bottom: AppSpacing.innerGap,
                ),
                child: AppFab(onPressed: () {}, tooltip: 'Existing screen'),
              ),
            ],
          ),
        ),
      ),
    );
    final buttons = find.byType(FloatingActionButton);
    expect(tester.getSize(buttons.first), tester.getSize(buttons.last));
    expect(
      tester.getTopLeft(buttons.first).dy,
      tester.getTopLeft(buttons.last).dy,
    );
  });
}
