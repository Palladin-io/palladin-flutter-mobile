import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _projectId = 'palladin';
const _projectNumber = '1006466869105';

const _androidApps = {
  'io.palladin.mobile.local': '1:1006466869105:android:d78fce556c7b0cfe2eb8d0',
  'io.palladin.mobile.staging':
      '1:1006466869105:android:571a5da21ec5611b2eb8d0',
  'io.palladin.mobile': '1:1006466869105:android:fc9c8cdff82ea1422eb8d0',
};

const _iosApps = {
  'local': (
    bundleId: 'io.palladin.mobile.local',
    appId: '1:1006466869105:ios:8f5fa72d54da87382eb8d0',
  ),
  'staging': (
    bundleId: 'io.palladin.mobile.staging',
    appId: '1:1006466869105:ios:864a6a8b0101cd932eb8d0',
  ),
  'production': (
    bundleId: 'io.palladin.mobile',
    appId: '1:1006466869105:ios:45a631020b77e0d12eb8d0',
  ),
};

void main() {
  group('Firebase client configuration', () {
    for (final flavor in ['local', 'staging', 'production']) {
      test('Android $flavor config contains every registered flavor', () {
        final file = File('android/app/src/$flavor/google-services.json');
        final config =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        final projectInfo = config['project_info'] as Map<String, dynamic>;
        final clients = config['client'] as List<dynamic>;
        final configuredApps = <String, String>{
          for (final client in clients.cast<Map<String, dynamic>>())
            ((client['client_info']
                            as Map<String, dynamic>)['android_client_info']
                        as Map<String, dynamic>)['package_name']
                    as String:
                (client['client_info']
                        as Map<String, dynamic>)['mobilesdk_app_id']
                    as String,
        };

        expect(projectInfo['project_id'], _projectId);
        expect(projectInfo['project_number'], _projectNumber);
        expect(configuredApps, _androidApps);
      });
    }

    for (final MapEntry(key: flavor, value: expected) in _iosApps.entries) {
      test('iOS $flavor config identifies the registered flavor', () {
        final config = File(
          'ios/config/$flavor/GoogleService-Info.plist',
        ).readAsStringSync();

        expect(_plistValue(config, 'PROJECT_ID'), _projectId);
        expect(_plistValue(config, 'GCM_SENDER_ID'), _projectNumber);
        expect(_plistValue(config, 'BUNDLE_ID'), expected.bundleId);
        expect(_plistValue(config, 'GOOGLE_APP_ID'), expected.appId);
      });
    }
  });
}

String _plistValue(String contents, String key) {
  final match = RegExp(
    '<key>$key</key>\\s*<string>([^<]+)</string>',
  ).firstMatch(contents);
  return match?.group(1) ?? '';
}
