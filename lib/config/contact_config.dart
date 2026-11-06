/// Explicit public contact destination supplied by the app distributor.
abstract final class ContactConfig {
  static const email = String.fromEnvironment('PALLADIN_CONTACT_EMAIL');

  static Uri providerSuggestionUri(String subject) => Uri(
    scheme: 'mailto',
    path: email,
    query: 'subject=${Uri.encodeComponent(subject)}',
  );
}
