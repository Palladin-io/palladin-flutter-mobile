import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

/// Application-wide logger utility.
///
/// Wraps the `logger` package with a static API for convenient tagged logging.
/// In debug builds, uses [PrettyPrinter] with colors and method info.
/// In release builds, all logging is suppressed via [ProductionFilter].
class AppLogger {
  AppLogger._();

  static final Logger _logger = Logger(
    filter: kDebugMode ? DevelopmentFilter() : ProductionFilter(),
    printer: PrettyPrinter(
      methodCount: 1,
      lineLength: 80,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
  );

  /// Logs a debug-level message.
  ///
  /// [tag] identifies the module/component (e.g. 'Auth', 'HTTP').
  static void d(String tag, String message) =>
      _logger.d('[$tag] $message');

  /// Logs an info-level message.
  static void i(String tag, String message) =>
      _logger.i('[$tag] $message');

  /// Logs a warning-level message.
  static void w(String tag, String message) =>
      _logger.w('[$tag] $message');

  /// Logs an error-level message with optional [error] and [stackTrace].
  static void e(
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) =>
      _logger.e('[$tag] $message', error: error, stackTrace: stackTrace);
}
