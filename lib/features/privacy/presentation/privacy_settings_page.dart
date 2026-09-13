import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_bar_title.dart';
import '../../../core/widgets/app_screen.dart';
import '../../../core/widgets/fab_registrar.dart';
import '../../../l10n/generated/app_localizations.dart';
import 'privacy_consent_sheet.dart';

/// A settings destination and reopen action, never an inline consent form.
class PrivacySettingsPage extends StatefulWidget {
  const PrivacySettingsPage({super.key});
  @override
  State<PrivacySettingsPage> createState() => _PrivacySettingsPageState();
}

class _PrivacySettingsPageState extends State<PrivacySettingsPage> {
  bool _opening = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _open();
    });
  }

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    await showPrivacyConsentSheet(context, source: 'mobile_settings');
    if (mounted) setState(() => _opening = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AppScreen.appBar(
      floatingActionButton: const FabRegistrar(fab: null),
      appBar: AppBar(
        titleSpacing: 0,
        centerTitle: false,
        title: AppBarTitle(title: l10n.privacyTitle),
      ),
      body: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
          child: OutlinedButton(
            onPressed: _opening ? null : _open,
            child: Text(l10n.privacyManageChoices),
          ),
        ),
      ),
    );
  }
}
