import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/widgets/action_zone.dart';
import 'package:mobile_palladin/features/vault/presentation/widgets/entry_field_row.dart';

void main() {
  testWidgets('copy and danger actions respond outside the visible glyph', (
    tester,
  ) async {
    var copied = 0;
    var deleted = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              EntrySmallIconButton(
                icon: Icons.content_copy,
                tooltip: 'Copy',
                onPressed: () => copied++,
              ),
              CompactDangerZone(
                title: 'Danger Zone',
                heading: 'Delete',
                onPressed: () => deleted++,
              ),
            ],
          ),
        ),
      ),
    );
    final copyCenter = tester.getCenter(find.byType(EntrySmallIconButton));
    await tester.tapAt(copyCenter + const Offset(18, 0));
    expect(copied, 1);
    final deleteCenter = tester.getCenter(find.byIcon(Icons.delete_outline));
    await tester.tapAt(deleteCenter + const Offset(18, 0));
    expect(deleted, 1);
  });
}
