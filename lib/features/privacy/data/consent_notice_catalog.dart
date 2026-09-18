import '../../../l10n/generated/app_localizations_en.dart';
import '../../../l10n/generated/app_localizations_pl.dart';
import '../domain/user_consent.dart';

const consentNoticeVersion = '2026-09-18T00:00:00Z';

ConsentNotice? consentNotice(String purpose, String locale) {
  final strings = locale == 'pl' ? AppLocalizationsPl() : AppLocalizationsEn();
  final text = switch (purpose) {
    'product_analytics' => strings.privacyAnalyticsNotice,
    'email_marketing' => strings.privacyMarketingNotice,
    _ => null,
  };
  if (text == null) return null;
  return ConsentNotice(
    version: consentNoticeVersion,
    locale: locale,
    text: text,
  );
}
