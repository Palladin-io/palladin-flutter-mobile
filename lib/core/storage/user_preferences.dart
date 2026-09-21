import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists UI preferences (theme mode, locale) between app sessions
/// using [FlutterSecureStorage].
class UserPreferences {
  const UserPreferences(this._storage);

  final FlutterSecureStorage _storage;

  static const _themeKey = 'ui_theme_mode';
  static const _localeKey = 'ui_locale';
  static const _libraryKey = 'ui_library_view';

  Future<bool> get libraryEntries async =>
      await _storage.read(key: _libraryKey) != 'vaults';

  Future<void> saveLibraryEntries(bool entries) =>
      _storage.write(key: _libraryKey, value: entries ? 'entries' : 'vaults');

  Future<ThemeMode> get themeMode async {
    final value = await _storage.read(key: _themeKey);
    return value == 'light' ? ThemeMode.light : ThemeMode.dark;
  }

  Future<void> saveThemeMode(ThemeMode mode) => _storage.write(
    key: _themeKey,
    value: mode == ThemeMode.light ? 'light' : 'dark',
  );

  Future<Locale> get locale async {
    final value = await _storage.read(key: _localeKey);
    return value != null ? Locale(value) : const Locale('en');
  }

  Future<void> saveLocale(Locale locale) =>
      _storage.write(key: _localeKey, value: locale.languageCode);
}
