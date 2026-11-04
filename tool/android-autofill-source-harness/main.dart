import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const channel = MethodChannel('io.palladin.mobile/autofill-request');
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
  bool sourceStarted = false;
  String status = 'SOURCE_ENGINE_READY';
  @override
  void initState() {
    super.initState();
    channel.setMethodCallHandler((call) async {
      if (call.method == 'pendingChanged') await poll();
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
          request['usernameOnly'] != false) {
        throw StateError('Unexpected synthetic request');
      }
      // Allow the original owner to stop behind the real Flutter task.
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!sourceStarted) {
        await channel.invokeMethod<int>('beginSourceSession', {
          'principalId': 'synthetic-member',
          'organizationId': 'synthetic-org',
          'organizationMembershipGeneration': 'synthetic-generation',
          'offlinePolicy': 'allowed',
          'offlinePolicyVersion': 1,
          'profileBinding': List.filled(64, 'a').join(),
          'sessionId': 'synthetic-request-session',
        });
        sourceStarted = true;
      }
      final binding = await channel.invokeMethod<String>('bind', {
        'id': request['id'],
        'principalId': 'synthetic-member',
        'organizationId': 'synthetic-org',
        'sessionId': 'synthetic-request-session',
      });
      if (binding == null || binding.isEmpty) {
        throw StateError('Binding failed');
      }
      final valid = await channel.invokeMethod<bool>('validate', {
        'id': request['id'],
        'bindingToken': binding,
        'authorizationToken': 'not-authenticated',
        'selectedHost': 'fixture.invalid',
      });
      if (valid != false) throw StateError('Unauthenticated request accepted');
      // Cancel the real owner through the real channel; no authentication bypass.
      await channel.invokeMethod<void>('cancel', {'id': request['id']});
      if (mounted) setState(() => status = 'SOURCE_CHANNEL_CANCEL_PASS');
    } finally {
      running = false;
    }
  }

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(status)));
}
