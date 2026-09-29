import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';

class GeneratedPasswordSummary {
  const GeneratedPasswordSummary({
    required this.id,
    required this.domain,
    required this.createdAt,
  });

  final String id;
  final String domain;
  final DateTime createdAt;
}

class GeneratedPasswordHistoryBridge {
  GeneratedPasswordHistoryBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('io.palladin.mobile/autofill');

  final MethodChannel _channel;

  Future<String> activate(String principalId) async {
    await _requireSupportedDevice();
    final token = await _channel.invokeMethod<String>(
      'activateGeneratedPasswordHistory',
      {'principalId': principalId},
    );
    if (token == null || token.isEmpty) {
      throw const FormatException('Missing generated-password session token');
    }
    return token;
  }

  Future<void> revoke(String token) async {
    await _requireSupportedDevice();
    await _channel.invokeMethod<void>('revokeGeneratedPasswordHistory', {
      'token': token,
    });
  }

  Future<void> revokeAllSessions() async {
    await _requireSupportedDevice();
    await _channel.invokeMethod<void>('revokeAllGeneratedPasswordSessions');
  }

  Future<List<GeneratedPasswordSummary>> list(
    String principalId, {
    required String biometricPrompt,
  }) async {
    await _requireSupportedDevice();
    final result = await _channel.invokeMethod<List<dynamic>>(
      'listGeneratedPasswords',
      {'principalId': principalId, 'prompt': biometricPrompt},
    );
    return (result ?? const [])
        .map((value) {
          final raw = Map<String, dynamic>.from(value as Map);
          return GeneratedPasswordSummary(
            id: raw['id'] as String,
            domain: raw['domain'] as String,
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              raw['createdAtMillis'] as int,
            ),
          );
        })
        .toList(growable: false);
  }

  Future<String> reveal(
    String principalId,
    String id, {
    required String biometricPrompt,
  }) async {
    await _requireSupportedDevice();
    final password = await _channel.invokeMethod<String>(
      'revealGeneratedPassword',
      {'principalId': principalId, 'id': id, 'prompt': biometricPrompt},
    );
    if (password == null) throw const FormatException('Missing password');
    return password;
  }

  Future<void> delete(
    String principalId,
    String id, {
    required String biometricPrompt,
  }) async {
    await _requireSupportedDevice();
    await _channel.invokeMethod<void>('deleteGeneratedPassword', {
      'principalId': principalId,
      'id': id,
      'prompt': biometricPrompt,
    });
  }

  Future<void> clear(
    String principalId, {
    required String biometricPrompt,
  }) async {
    await _requireSupportedDevice();
    await _channel.invokeMethod<void>('clearGeneratedPasswords', {
      'principalId': principalId,
      'prompt': biometricPrompt,
    });
  }

  Future<String> generateForEntry(
    String principalId,
    String domain, {
    required String biometricPrompt,
  }) async {
    await _requireSupportedDevice();
    final password = await _channel.invokeMethod<String>(
      'generatePasswordForEntry',
      {'principalId': principalId, 'domain': domain, 'prompt': biometricPrompt},
    );
    if (password == null) throw const FormatException('Missing password');
    return password;
  }

  Future<void> _requireSupportedDevice() async {
    if (!Platform.isIOS) return;
    if (!(await DeviceInfoPlugin().iosInfo).isPhysicalDevice) {
      throw MissingPluginException(
        'Generated password history requires a device',
      );
    }
  }
}
