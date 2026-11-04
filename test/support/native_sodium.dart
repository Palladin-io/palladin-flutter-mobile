import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

/// libsodium 1.0.22 built for the test host by sodium's native-asset hook.
Future<SodiumSumo> loadTestSodium() async => SodiumSumoInit.init();

Map<String, dynamic> readJsonFixture(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

Uint8List hexBytes(String value) => Uint8List.fromList([
  for (var i = 0; i < value.length; i += 2)
    int.parse(value.substring(i, i + 2), radix: 16),
]);

String toHex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

Uint8List b64urlBytes(String value) =>
    Uint8List.fromList(base64Url.decode(base64Url.normalize(value)));

String b64url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
