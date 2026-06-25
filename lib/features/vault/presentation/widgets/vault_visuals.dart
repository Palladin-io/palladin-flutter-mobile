import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Mapping helpers between the string identifiers stored on the
/// [VaultEntity] (icon name + `#RRGGBB` color) and Flutter's typed
/// [IconData] / [Color] values.
///
/// The mobile prototype's icon picker uses Material Icon names — the
/// same identifiers the web panel uses — so the vault entity's `icon`
/// field is interpreted as a name like `shield`, `folder`, `cloud`,
/// `code`, `database`, or `key`. Anything else falls back to the
/// shield icon (the create-vault default).
abstract final class VaultVisuals {
  /// Default icon name for newly-created vaults.
  static const String defaultIconName = 'shield';

  /// Default vault accent color, in `#RRGGBB` form. Picked to match
  /// the prototype's first swatch (brand red).
  static const String defaultColorHex = '#FF4F4F';

  /// Picker choices for the icon row — keep in sync with the web /
  /// Astro prototype.
  ///
  /// [paletteColor] drives the icon circle's background tint; the
  /// prototype assigns each icon a distinct hue so the row is
  /// colourful rather than uniformly gray.
  static const List<VaultIconChoice> iconChoices = <VaultIconChoice>[
    VaultIconChoice(name: 'shield',      icon: Icons.shield,            paletteColor: AppColors.brandRed),
    VaultIconChoice(name: 'folder',      icon: Icons.folder,            paletteColor: AppColors.vaultPeach),
    VaultIconChoice(name: 'cloud',       icon: Icons.cloud,             paletteColor: AppColors.vaultBlue),
    VaultIconChoice(name: 'code',        icon: Icons.code,              paletteColor: AppColors.positiveAccent),
    VaultIconChoice(name: 'database',    icon: Icons.storage,           paletteColor: AppColors.vaultSlate),
    VaultIconChoice(name: 'key',         icon: Icons.vpn_key,           paletteColor: AppColors.vaultSlate),
    VaultIconChoice(name: 'lock',        icon: Icons.lock,              paletteColor: AppColors.brandRed),
    VaultIconChoice(name: 'home',        icon: Icons.home,              paletteColor: AppColors.vaultBlue),
    VaultIconChoice(name: 'work',        icon: Icons.work,              paletteColor: AppColors.vaultSlate),
    VaultIconChoice(name: 'language',    icon: Icons.language,          paletteColor: AppColors.vaultBlue),
    VaultIconChoice(name: 'smartphone',  icon: Icons.smartphone,        paletteColor: AppColors.vaultViolet),
    VaultIconChoice(name: 'credit_card', icon: Icons.credit_card,       paletteColor: AppColors.vaultPeach),
    VaultIconChoice(name: 'person',      icon: Icons.person,            paletteColor: AppColors.vaultBlue),
    VaultIconChoice(name: 'email',       icon: Icons.email,             paletteColor: AppColors.vaultBlue),
    VaultIconChoice(name: 'star',        icon: Icons.star,              paletteColor: AppColors.vaultPeach),
    VaultIconChoice(name: 'wifi',        icon: Icons.wifi,              paletteColor: AppColors.vaultBlue),
    VaultIconChoice(name: 'description', icon: Icons.description,       paletteColor: AppColors.vaultSlate),
    VaultIconChoice(name: 'dns',         icon: Icons.dns,               paletteColor: AppColors.vaultSlate),
    VaultIconChoice(name: 'bookmark',    icon: Icons.bookmark,          paletteColor: AppColors.vaultViolet),
    VaultIconChoice(name: 'settings',    icon: Icons.settings,          paletteColor: AppColors.vaultSlate),
    VaultIconChoice(name: 'security',    icon: Icons.security,          paletteColor: AppColors.positiveAccent),
    VaultIconChoice(name: 'payments',    icon: Icons.payments,          paletteColor: AppColors.premiumAmber),
    VaultIconChoice(name: 'computer',    icon: Icons.computer,          paletteColor: AppColors.vaultViolet),
    VaultIconChoice(name: 'label',       icon: Icons.label,             paletteColor: AppColors.vaultPeach),
  ];

  /// Picker choices for the color row — keep in sync with the web /
  /// Astro prototype.
  static const List<String> colorChoices = <String>[
    '#FF4F4F', // brand red
    '#FFAB87', // peach
    '#60A5FA', // sky
    '#16A34A', // teal
    '#A78BFA', // violet
    '#8A95A6', // slate
  ];

  /// Returns true when [icon] is a remote or local file URL (uploaded
  /// custom icon) rather than a named preset. Accepts both https:// and
  /// http:// (used by LocalStack in local dev).
  static bool isCustomUrl(String? icon) =>
      icon != null &&
      (icon.startsWith('https://') ||
       icon.startsWith('http://') ||
       icon.startsWith('file://'));

  /// Resolve a stored icon name to its [IconData]. Falls back to
  /// [Icons.shield] when the name is missing or unknown — older vaults
  /// that still store an emoji also land in the fallback bucket.
  static IconData iconFor(String? name) {
    if (name == null || name.isEmpty) return Icons.shield;
    for (final choice in iconChoices) {
      if (choice.name == name) return choice.icon;
    }
    // Compatibility shims for icon names that exist on the web side
    // but aren't in the mobile picker yet.
    return switch (name) {
      'lock'        => Icons.lock,
      'key' || 'vpn_key' => Icons.vpn_key,
      'storage' || 'database' => Icons.storage,
      'home'        => Icons.home,
      'work'        => Icons.work,
      'language'    => Icons.language,
      'smartphone'  => Icons.smartphone,
      'credit_card' => Icons.credit_card,
      'person'      => Icons.person,
      'email'       => Icons.email,
      'star'        => Icons.star,
      'wifi'        => Icons.wifi,
      'description' => Icons.description,
      'dns'         => Icons.dns,
      'bookmark'    => Icons.bookmark,
      'settings'    => Icons.settings,
      _ => Icons.shield,
    };
  }

  /// Resolve a `#RRGGBB` color hint to a Flutter [Color]. Falls back
  /// to [AppColors.brandRed] (the picker default) for malformed input.
  static Color colorFor(String? hex) {
    if (hex == null || hex.isEmpty) return AppColors.brandRed;
    final cleaned = hex.startsWith('#') ? hex.substring(1) : hex;
    if (cleaned.length != 6) return AppColors.brandRed;
    final value = int.tryParse(cleaned, radix: 16);
    if (value == null) return AppColors.brandRed;
    return Color(0xFF000000 | value);
  }
}

/// Entry-specific visual constants — icons and colors mirroring the web
/// panel's `ENTRY_ICON_OPTIONS` and `ENTRY_ICON_COLORS`.
abstract final class EntryVisuals {
  static const String defaultIconName = 'vpn_key';
  static const String defaultColorHex = '#16A34A';

  static const List<VaultIconChoice> iconChoices = <VaultIconChoice>[
    VaultIconChoice(name: 'vpn_key',      icon: Icons.vpn_key,        paletteColor: AppColors.positiveAccent),
    VaultIconChoice(name: 'language',     icon: Icons.language,        paletteColor: AppColors.vaultBlue),
    VaultIconChoice(name: 'person',       icon: Icons.person,          paletteColor: AppColors.vaultViolet),
    VaultIconChoice(name: 'email',        icon: Icons.email,           paletteColor: AppColors.vaultBlue),
    VaultIconChoice(name: 'database',     icon: Icons.storage,         paletteColor: AppColors.vaultSlate),
    VaultIconChoice(name: 'cloud',        icon: Icons.cloud,           paletteColor: AppColors.vaultBlue),
    VaultIconChoice(name: 'credit_card',  icon: Icons.credit_card,     paletteColor: AppColors.vaultPeach),
    VaultIconChoice(name: 'badge',        icon: Icons.badge,           paletteColor: AppColors.vaultViolet),
    VaultIconChoice(name: 'lock',         icon: Icons.lock,            paletteColor: AppColors.brandRed),
    VaultIconChoice(name: 'smartphone',   icon: Icons.smartphone,      paletteColor: AppColors.vaultSlate),
    VaultIconChoice(name: 'fingerprint',  icon: Icons.fingerprint,     paletteColor: AppColors.positiveAccent),
    VaultIconChoice(name: 'wifi',         icon: Icons.wifi,            paletteColor: AppColors.vaultBlue),
    VaultIconChoice(name: 'computer',     icon: Icons.computer,        paletteColor: AppColors.vaultBlue),
    VaultIconChoice(name: 'dns',          icon: Icons.dns,             paletteColor: AppColors.vaultSlate),
    VaultIconChoice(name: 'bookmark',     icon: Icons.bookmark,        paletteColor: AppColors.vaultViolet),
    VaultIconChoice(name: 'shield',       icon: Icons.shield,          paletteColor: AppColors.brandRed),
    VaultIconChoice(name: 'link',         icon: Icons.link,            paletteColor: AppColors.vaultBlue),
    VaultIconChoice(name: 'home',         icon: Icons.home,            paletteColor: AppColors.vaultBlue),
    VaultIconChoice(name: 'star',         icon: Icons.star,            paletteColor: AppColors.vaultPeach),
    VaultIconChoice(name: 'description',  icon: Icons.description,     paletteColor: AppColors.vaultSlate),
    VaultIconChoice(name: 'api',          icon: Icons.api,             paletteColor: AppColors.positiveAccent),
    VaultIconChoice(name: 'token',        icon: Icons.token,           paletteColor: AppColors.vaultViolet),
    VaultIconChoice(name: 'terminal',     icon: Icons.terminal,        paletteColor: AppColors.positiveAccent),
    VaultIconChoice(name: 'work',         icon: Icons.work,            paletteColor: AppColors.vaultSlate),
  ];

  static bool isCustomUrl(String? icon) =>
      icon != null &&
      (icon.startsWith('https://') ||
       icon.startsWith('http://') ||
       icon.startsWith('file://'));

  static IconData iconFor(String? name) {
    if (name == null || name.isEmpty) return Icons.vpn_key;
    for (final choice in iconChoices) {
      if (choice.name == name) return choice.icon;
    }
    return switch (name) {
      'vpn_key' || 'key' => Icons.vpn_key,
      'language'    => Icons.language,
      'person'      => Icons.person,
      'email'       => Icons.email,
      'database' || 'storage' => Icons.storage,
      'cloud'       => Icons.cloud,
      'credit_card' => Icons.credit_card,
      'badge'       => Icons.badge,
      'lock'        => Icons.lock,
      'smartphone'  => Icons.smartphone,
      'fingerprint' => Icons.fingerprint,
      'wifi'        => Icons.wifi,
      'computer'    => Icons.computer,
      'dns'         => Icons.dns,
      'bookmark'    => Icons.bookmark,
      'shield'      => Icons.shield,
      'link'        => Icons.link,
      'home'        => Icons.home,
      'star'        => Icons.star,
      'description' => Icons.description,
      'api'         => Icons.api,
      'token'       => Icons.token,
      'terminal'    => Icons.terminal,
      'work'        => Icons.work,
      _ => Icons.vpn_key,
    };
  }
}

/// One entry in the vault icon picker.
class VaultIconChoice {
  const VaultIconChoice({
    required this.name,
    required this.icon,
    required this.paletteColor,
  });

  final String name;
  final IconData icon;

  /// Background tint for the icon circle — distinct per icon so the
  /// picker row is colourful rather than uniformly gray.
  final Color paletteColor;
}
