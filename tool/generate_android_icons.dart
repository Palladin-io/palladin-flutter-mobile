import 'dart:io';

import 'package:image/image.dart' as img;

// Derive Android artwork from the approved transparent T02 mark, without
// flattening its negative-space hex or changing the iOS launcher source.
void main() {
  final logo = img.decodePng(File('assets/images/logo.png').readAsBytesSync())!;
  img.Image framed(int size, {bool monochrome = false}) {
    final mark = img.copyResize(
      logo,
      width: (size * 5 / 6).round(),
      interpolation: img.Interpolation.average,
    );
    final canvas = img.Image(width: size, height: size, numChannels: 4);
    img.compositeImage(canvas, mark, center: true);
    if (monochrome) {
      for (final pixel in canvas) {
        pixel
          ..r = 255
          ..g = 255
          ..b = 255;
      }
    }
    return canvas;
  }

  void write(String path, img.Image image) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(img.encodePng(image));
  }

  write('assets/images/icon_android.png', framed(1024));
  const densities = {
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
  };
  for (final entry in densities.entries) {
    final root = 'android/app/src/main/res';
    write('$root/mipmap-${entry.key}/ic_launcher.png', framed(entry.value));
    write(
      '$root/drawable-${entry.key}/ic_notification.png',
      framed(entry.value ~/ 2, monochrome: true),
    );
  }
  final store = img.decodePng(
    File('assets/images/icon_light.png').readAsBytesSync(),
  )!;
  write(
    'assets/store/google-play-icon.png',
    img.copyResize(
      store,
      width: 512,
      height: 512,
      interpolation: img.Interpolation.average,
    ),
  );
}
