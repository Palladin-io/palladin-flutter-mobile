import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/widgets/app_search_field.dart';

void main() {
  testWidgets('search keeps Teams geometry with and without filters', (
    tester,
  ) async {
    final controllers = List.generate(2, (_) => TextEditingController());
    addTearDown(() {
      for (final controller in controllers) {
        controller.dispose();
      }
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 390,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  AppSearchField(controller: controllers[0], hint: 'Entries'),
                  AppSearchField(
                    controller: controllers[1],
                    hint: 'Teams',
                    onToggleFilter: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final fields = find.byType(TextField);
    expect(tester.getSize(fields.at(0)), tester.getSize(fields.at(1)));
    expect(tester.getSize(fields.at(0)).width, 350);
    expect(tester.getSize(fields.at(0)).height, greaterThanOrEqualTo(44));
  });
}
