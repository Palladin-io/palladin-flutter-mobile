import 'package:flutter/material.dart';

import '../../settings/presentation/pages/security_page.dart';
import 'privacy_consent_sheet.dart';

/// Direct links have Security behind the sheet. Menu actions open the sheet in place.
class PrivacySettingsPage extends StatefulWidget {
  const PrivacySettingsPage({super.key, this.onClosed});
  final VoidCallback? onClosed;
  @override
  State<PrivacySettingsPage> createState() => _PrivacySettingsPageState();
}

class _PrivacySettingsPageState extends State<PrivacySettingsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showPrivacyConsentSheet(context, source: 'mobile_settings');
      if (mounted) widget.onClosed?.call();
    });
  }

  @override
  Widget build(BuildContext context) => const SecurityPage();
}
