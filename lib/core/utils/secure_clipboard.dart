import 'dart:async';

import 'package:flutter/services.dart';

/// Clipboard helper that auto-clears copied secrets after a short delay
/// (CVT-215).
///
/// Passwords, API keys and recovery phrases must not linger on the system
/// clipboard indefinitely (other apps, clipboard history, cloud sync can read
/// it). [copy] writes the value and schedules a wipe; the wipe is skipped if
/// the user has since copied something else, so we never clobber unrelated
/// clipboard content.
///
/// NOTE: Android 13+ exposes a `EXTRA_IS_SENSITIVE` `ClipDescription` flag that
/// keeps the value out of the clipboard-history preview. Flutter's [Clipboard]
/// API does not surface it, so it would require a small platform channel;
/// tracked as a follow-up. The time-boxed auto-clear applies on every platform.
abstract final class SecureClipboard {
  /// Default lifetime of a copied secret before it is wiped.
  static const defaultClearAfter = Duration(seconds: 45);

  /// Copies [value] to the clipboard and schedules an auto-clear.
  static Future<void> copy(
    String value, {
    Duration clearAfter = defaultClearAfter,
  }) async {
    await Clipboard.setData(ClipboardData(text: value));
    _scheduleClear(value, clearAfter);
  }

  static void _scheduleClear(String value, Duration delay) {
    Timer(delay, () async {
      // Only wipe if OUR value is still on the clipboard — never clobber
      // something the user copied in the meantime.
      final current = await Clipboard.getData(Clipboard.kTextPlain);
      if (current?.text == value) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    });
  }
}
