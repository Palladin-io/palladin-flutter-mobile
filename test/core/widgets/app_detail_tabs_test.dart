import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/widgets/app_detail_tabs.dart';

void main() {
  testWidgets('disabled destination preserves externally selected tab', (
    tester,
  ) async {
    int? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: DefaultTabController(
          length: 3,
          initialIndex: 1,
          child: Scaffold(
            body: AppDetailTabs(
              tabs: const [
                Tab(text: 'Details'),
                Tab(text: 'Grants'),
                Tab(text: 'Logs'),
              ],
              disabledIndices: const {2},
              onSelected: (value) => selected = value,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Logs'));
    await tester.pumpAndSettle();
    final controller = DefaultTabController.of(
      tester.element(find.byType(AppDetailTabs)),
    );
    expect(controller.index, 1);
    expect(selected, isNull);
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(controller.index, 0);
    expect(selected, 0);
  });

  testWidgets('fills available width and scrolls long translated labels', (
    tester,
  ) async {
    Future<void> show(List<Tab> tabs) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: DefaultTabController(
                length: tabs.length,
                child: AppDetailTabs(tabs: tabs),
              ),
            ),
          ),
        ),
      ),
    );
    await show(const [Tab(text: 'Details'), Tab(text: 'Logs')]);
    expect(tester.getSize(find.byType(AppDetailTabs)).width, 320);
    expect(tester.widget<TabBar>(find.byType(TabBar)).isScrollable, isFalse);
    await tester.tap(find.text('Logs'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await show(const [
      Tab(text: 'Szczegóły'),
      Tab(text: 'Uprawnienia agentów'),
      Tab(text: 'Dziennik zdarzeń'),
      Tab(text: 'Udostępnianie'),
    ]);
    expect(tester.widget<TabBar>(find.byType(TabBar)).isScrollable, isTrue);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    await tester.drag(find.byType(TabBar), const Offset(-900, 0));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    await tester.tap(find.text('Udostępnianie'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
