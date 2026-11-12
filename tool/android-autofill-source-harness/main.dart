import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const channel = MethodChannel('io.palladin.mobile/autofill-request');
final expectedProfile = <String, Object>{
  'principalId': 'synthetic-member',
  'organizationId': 'synthetic-org',
  'organizationMembershipGeneration': 'synthetic-generation',
  'offlinePolicy': 'allowed',
  'offlinePolicyVersion': 1,
  'profileBinding': List.filled(64, 'a').join(),
};
const accountUnlock = <String, Object>{
  'accountId': 'synthetic-member',
  'encryptedPrivateKey': 'synthetic-ciphertext',
  'kdf': <String, Object>{
    'securityVersion': 2,
    'minimumSecurityVersion': 1,
    'profileId': 'synthetic-kdf',
    'kdfSalt': 'synthetic-salt',
    'credentialRevision': 4,
    'privateKeyWrapRevision': 3,
  },
};
void main() {
  if (!kDebugMode) throw StateError('Debug fixture only');
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: SourceFixture()));
}

class SourceFixture extends StatefulWidget {
  const SourceFixture({super.key});
  @override
  State<SourceFixture> createState() => _SourceFixtureState();
}

class _SourceFixtureState extends State<SourceFixture> {
  bool running = false;
  int? sourceEpoch;
  String? sourceChangedId;
  String status = 'SOURCE_ENGINE_READY';
  @override
  void initState() {
    super.initState();
    channel.setMethodCallHandler((call) async {
      if (call.method == 'pendingChanged') await poll();
      if (call.method == 'sourceChanged') {
        sourceChangedId = call.arguments as String;
      }
    });
    poll();
  }

  Future<void> poll() async {
    if (running) return;
    running = true;
    try {
      final request = await channel.invokeMapMethod<String, dynamic>('pending');
      if (request == null) return;
      if (request['mode'] != 'MANUAL_NATIVE' ||
          request['usernameOnly'] is! bool) {
        throw StateError('Unexpected synthetic request');
      }
      // Allow the original owner to stop behind the real Flutter task.
      await Future<void>.delayed(const Duration(seconds: 1));
      sourceEpoch ??= await channel.invokeMethod<int>('beginSourceSession', {
        ...expectedProfile,
        'accountUnlock': accountUnlock,
        'sessionId': 'synthetic-request-session',
      });
      final binding = await channel.invokeMethod<String>('bind', {
        'id': request['id'],
        'principalId': 'synthetic-member',
        'organizationId': 'synthetic-org',
        'sessionId': 'synthetic-request-session',
      });
      if (binding == null || binding.isEmpty) {
        throw StateError('Binding failed');
      }
      sourceChangedId = null;
      sourceEpoch = await channel.invokeMethod<int>('invalidateSource', {
        'sessionId': 'synthetic-request-session',
        'sourceEpoch': sourceEpoch,
        'profileBinding': expectedProfile['profileBinding'],
      });
      await Future<void>.delayed(Duration.zero);
      final retained = await channel.invokeMapMethod<String, dynamic>(
        'pending',
      );
      if (sourceChangedId != request['id'] ||
          retained?['id'] != request['id']) {
        throw StateError('Routine source change did not retain its request');
      }
      final valid = await channel.invokeMethod<bool>('validate', {
        'id': request['id'],
        'bindingToken': binding,
        'authorizationToken': 'not-authenticated',
        'sourceEpoch': sourceEpoch,
        'selectedHost': 'fixture.invalid',
      });
      if (valid != false) throw StateError('Unauthenticated request accepted');
      // Cancel the real owner through the real channel; no authentication bypass.
      await channel.invokeMethod<void>('cancel', {'id': request['id']});
      if (mounted) {
        setState(
          () => status = request['usernameOnly'] == true
              ? 'SOURCE_CHANNEL_USERNAME_CANCEL_PASS'
              : 'SOURCE_CHANNEL_CANCEL_PASS',
        );
      }
    } finally {
      running = false;
    }
  }

  Future<void> verifyHardRepair() async {
    try {
      final next = await channel.invokeMethod<int>('revokeSourceSession', {
        'sessionId': 'synthetic-request-session',
        'sourceEpoch': sourceEpoch,
        'profileBinding': List.filled(64, 'a').join(),
      });
      await channel.invokeMethod<int>('activateSource', {
        'sessionId': 'synthetic-request-session',
        'sourceEpoch': next,
      });
      sourceEpoch = next;
      if (mounted) setState(() => status = 'SOURCE_HARD_REPAIR_PASS');
    } on PlatformException {
      if (mounted) setState(() => status = 'SOURCE_HARD_REPAIR_FAIL');
    }
  }

  Future<void> verifyProtectedBootstrap() async {
    try {
      final cached = await channel.invokeMapMethod<String, dynamic>(
        'sourceConfiguration',
        expectedProfile,
      );
      final wrong = await channel.invokeMapMethod<String, dynamic>(
        'sourceConfiguration',
        {...expectedProfile, 'organizationId': 'different-org'},
      );
      if (cached?['accountUnlock'] is! Map ||
          (cached!['accountUnlock'] as Map)['encryptedPrivateKey'] !=
              'synthetic-ciphertext' ||
          wrong != null) {
        throw StateError('Protected configuration mismatch');
      }
      await channel.invokeMethod<int>('beginSourceSession', {
        ...expectedProfile,
        'sessionId': 'synthetic-adopted',
        'accountUnlock': cached['accountUnlock'],
        'forceQuarantine': false,
      });
      if (await channel.invokeMapMethod<String, dynamic>(
            'sourceConfiguration',
            expectedProfile,
          ) ==
          null) {
        throw StateError('Exact active configuration not adopted');
      }
      await channel.invokeMethod<int>('beginSourceSession', {
        ...expectedProfile,
        'sessionId': 'synthetic-quarantined',
        'accountUnlock': cached['accountUnlock'],
        'forceQuarantine': true,
      });
      if (await channel.invokeMapMethod<String, dynamic>(
            'sourceConfiguration',
            expectedProfile,
          ) !=
          null) {
        throw StateError('Forced quarantine allowed configuration');
      }
      if (mounted) setState(() => status = 'SOURCE_BOOTSTRAP_PASS');
    } catch (_) {
      if (mounted) setState(() => status = 'SOURCE_BOOTSTRAP_FAIL');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(status),
          TextButton(
            onPressed: verifyProtectedBootstrap,
            child: const Text('Verify protected bootstrap'),
          ),
          TextButton(
            onPressed: verifyHardRepair,
            child: const Text('Verify hard revoke repair'),
          ),
        ],
      ),
    ),
  );
}
