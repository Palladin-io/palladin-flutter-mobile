import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import 'brand_hero.dart';

typedef AuthLegalLinkLauncher =
    Future<bool> Function(Uri uri, {required LaunchMode mode});

/// Shared Terms and Privacy footer for unauthenticated account screens.
class AuthLegalFooter extends StatefulWidget {
  const AuthLegalFooter({super.key, this.launcher = launchUrl});

  final AuthLegalLinkLauncher launcher;

  @override
  State<AuthLegalFooter> createState() => _AuthLegalFooterState();
}

class _AuthLegalFooterState extends State<AuthLegalFooter> {
  static final Uri _termsUri = Uri.parse('https://palladin.io/terms');
  static final Uri _privacyUri = Uri.parse('https://palladin.io/privacy');
  static final Uri _polishTermsUri = Uri.parse(
    'https://palladin.io/pl/regulamin',
  );
  static final Uri _polishPrivacyUri = Uri.parse(
    'https://palladin.io/pl/polityka-prywatnosci',
  );

  late final TapGestureRecognizer _termsRecognizer;
  late final TapGestureRecognizer _privacyRecognizer;

  @override
  void initState() {
    super.initState();
    _termsRecognizer = TapGestureRecognizer()
      ..onTap = () => _openLegalPage(privacy: false);
    _privacyRecognizer = TapGestureRecognizer()
      ..onTap = () => _openLegalPage(privacy: true);
  }

  @override
  void dispose() {
    _termsRecognizer.dispose();
    _privacyRecognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final baseColor = BrandHero.textColorFor(brightness).withValues(alpha: 0.4);
    final linkColor = BrandHero.textColorFor(brightness).withValues(alpha: 0.7);
    final linkStyle = TextStyle(
      color: linkColor,
      decoration: TextDecoration.underline,
      decorationColor: linkColor,
    );
    return Text.rich(
      TextSpan(
        style: TextStyle(fontSize: 12, color: baseColor),
        children: [
          TextSpan(text: l10n.legalFooterPrefix),
          TextSpan(
            text: l10n.legalTermsLink,
            style: linkStyle,
            recognizer: _termsRecognizer,
          ),
          TextSpan(text: l10n.legalFooterSeparator),
          TextSpan(
            text: l10n.legalPrivacyLink,
            style: linkStyle,
            recognizer: _privacyRecognizer,
          ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }

  Future<void> _openLegalPage({required bool privacy}) async {
    final isPolish = Localizations.localeOf(context).languageCode == 'pl';
    final uri = switch ((isPolish, privacy)) {
      (true, false) => _polishTermsUri,
      (true, true) => _polishPrivacyUri,
      (false, false) => _termsUri,
      (false, true) => _privacyUri,
    };
    var opened = false;
    try {
      opened = await widget.launcher(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Platform channels can throw instead of returning false. Both outcomes
      // use the same localized, non-sensitive user-facing failure path.
    }
    if (!opened && mounted) {
      final messenger = ScaffoldMessenger.of(context);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.legalLinkOpenError),
            backgroundColor: AppColors.brandRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }
}
