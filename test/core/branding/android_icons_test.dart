import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  for (final density in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
    test('$density launcher keeps transparent margins and shield cutout', () {
      final image = img.decodePng(
        File(
          'android/app/src/main/res/mipmap-$density/ic_launcher.png',
        ).readAsBytesSync(),
      )!;
      expect(image.getPixel(0, 0).a, 0);
      expect(
        image.getPixel(image.width ~/ 2, image.height ~/ 2).a,
        greaterThan(0),
      );
      expect(
        image.getPixel(image.width ~/ 2, (image.height * .36).round()).a,
        0,
      );
    });
    test('$density notification is a monochrome alpha silhouette', () {
      final image = img.decodePng(
        File(
          'android/app/src/main/res/drawable-$density/ic_notification.png',
        ).readAsBytesSync(),
      )!;
      expect(image.getPixel(0, 0).a, 0);
      final opaque = image.where((pixel) => pixel.a > 0).toList();
      expect(opaque.length, greaterThan(image.width * image.height * .2));
      expect(opaque.length, lessThan(image.width * image.height * .8));
      expect(
        opaque.every(
          (pixel) => pixel.r == 255 && pixel.g == 255 && pixel.b == 255,
        ),
        true,
      );
    });
  }
}
