import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/widgets/auth_brand_layout.dart';
import 'emergency_kit_step.dart';

/// Full-screen, non-dismissable host for [EmergencyKitStep] in registration,
/// the security upgrade and account recovery.
class EmergencyKitStepScreen extends StatelessWidget {
  const EmergencyKitStepScreen({
    super.key,
    required this.email,
    required this.accountId,
    required this.accountSecret,
    required this.onContinue,
  });

  final String email;
  final String accountId;
  final Uint8List accountSecret;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: AuthBrandBackground(
      child: SafeArea(
        child: EmergencyKitStep(
          email: email,
          accountId: accountId,
          accountSecret: accountSecret,
          onContinue: onContinue,
        ),
      ),
    ),
  );
}
