/// Formatting helpers for the API-keys feature.
///
/// Kept as pure functions so they can be unit-tested without a widget
/// tree and reused across the list card and the detail screen.
library;

/// Formats a date as `YYYY-MM-DD` — locale-neutral and stable.
///
/// API-key timestamps are shown as plain calendar dates; the exact
/// time-of-day carries no value to the user, so we drop it.
String formatApiKeyDate(DateTime date) {
  final d = date.toLocal();
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}
