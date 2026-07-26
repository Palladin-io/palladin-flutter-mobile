import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/vault/data/export/protected_export_staging.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/protected-export');
  late MethodChannelProtectedExportStaging staging;
  late List<MethodCall> calls;

  setUp(() {
    staging = MethodChannelProtectedExportStaging(channel: channel);
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'createExport' => 'opaque-id',
            'finishExport' => '/private/export.json',
            'deleteExport' => true,
            'sweepStaleExports' => 3,
            'cleanupExports' => 2,
            _ => null,
          };
        });
  });

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test('streams only opaque handle plus bounded byte chunks', () async {
    final sink = await staging.create(fileExtension: '.JSON');
    await sink.append(Uint8List.fromList([1, 2, 3]));
    expect(await sink.finish(), '/private/export.json');
    expect(calls.map((call) => call.method), [
      'createExport',
      'appendExport',
      'finishExport',
    ]);
    expect(calls[1].arguments, {'id': 'opaque-id', 'bytes': isA<Uint8List>()});
  });

  test('rejects extensions that could escape staging', () async {
    await expectLater(
      staging.create(fileExtension: '../json'),
      throwsFormatException,
    );
    expect(calls, isEmpty);
  });

  test('reports deletion and stale sweep honestly', () async {
    expect(await staging.delete('/private/export.json'), isTrue);
    expect(await staging.sweepStaleExports(), 3);
    expect(await staging.cleanupExports(), 2);
  });
}
