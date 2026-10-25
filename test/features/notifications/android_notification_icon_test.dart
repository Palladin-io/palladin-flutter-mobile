import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/notifications/data/datasources/push_token_remote_datasource.dart';
import 'package:mobile_palladin/features/notifications/data/services/push_notification_service.dart';

class _Messaging extends Mock implements FirebaseMessaging {}

class _Datasource extends Mock implements PushTokenRemoteDatasource {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Android initialization and foreground banners use the alpha small icon',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      const channel = MethodChannel(
        'dexterous.com/flutter/local_notifications',
      );
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return call.method == 'initialize' ? true : null;
          });
      final messaging = _Messaging();
      when(
        () => messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        ),
      ).thenAnswer((_) async {});
      final service = PushNotificationService(
        datasource: _Datasource(),
        secureStorage: const FlutterSecureStorage(),
        messaging: messaging,
      );
      addTearDown(() async {
        await service.dispose();
        debugDefaultTargetPlatformOverride = null;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      await service.init();
      service.showLocalNotification(title: 'Test');
      await Future<void>.delayed(Duration.zero);
      expect(
        (calls.singleWhere((call) => call.method == 'initialize').arguments
            as Map)['defaultIcon'],
        'ic_notification',
      );
      final shown =
          calls.singleWhere((call) => call.method == 'show').arguments as Map;
      expect((shown['platformSpecifics'] as Map)['icon'], 'ic_notification');
    },
  );
}
