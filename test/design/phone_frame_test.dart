import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../design/mobile/phone_frame.dart';

void main() {
  testWidgets(
    'desktop preview exposes phone geometry and keeps bottom visible',
    (tester) async {
      tester.view.physicalSize = const Size(1520, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Size? measured;
      Size? media;
      await tester.pumpWidget(
        MaterialApp(
          home: PreviewPhoneFrame(
            child: LayoutBuilder(
              builder: (context, constraints) {
                measured = constraints.biggest;
                media = MediaQuery.sizeOf(context);
                return const Scaffold(
                  bottomNavigationBar: SizedBox(
                    height: 72,
                    child: Text('navbar'),
                  ),
                );
              },
            ),
          ),
        ),
      );
      expect(measured, PreviewPhoneFrame.screenSize);
      expect(media, PreviewPhoneFrame.screenSize);
      expect(tester.getBottomRight(find.text('navbar')).dy, lessThan(900));
      tester.view.physicalSize = const Size(800, 600);
      await tester.pump();
      expect(measured, PreviewPhoneFrame.screenSize);
      expect(media, PreviewPhoneFrame.screenSize);
      expect(
        tester.getBottomRight(find.text('navbar')).dy,
        lessThanOrEqualTo(600),
      );
    },
  );
}
