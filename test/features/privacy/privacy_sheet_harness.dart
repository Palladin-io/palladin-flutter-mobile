import 'package:flutter/material.dart';
import 'package:mobile_palladin/features/privacy/presentation/privacy_consent_sheet.dart';

/// Mounts the production startup sheet without coupling tests to auth routing.
class PrivacySheetHarness extends StatefulWidget {
  const PrivacySheetHarness({super.key, required this.onCompleted});
  final VoidCallback onCompleted;
  @override
  State<PrivacySheetHarness> createState() => _PrivacySheetHarnessState();
}

class _PrivacySheetHarnessState extends State<PrivacySheetHarness> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showPrivacyConsentSheet(context, source: 'mobile_onboarding');
      if (mounted) widget.onCompleted();
    });
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Text('Application'));
}
