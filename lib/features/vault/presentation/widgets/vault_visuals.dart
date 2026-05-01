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
  static const List<VaultIconChoice> iconChoices = <VaultIconChoice>[
    VaultIconChoice(name: 'shield', icon: Icons.shield),
    VaultIconChoice(name: 'folder', icon: Icons.folder),
    VaultIconChoice(name: 'cloud', icon: Icons.cloud),
    VaultIconChoice(name: 'code', icon: Icons.code),
    VaultIconChoice(name: 'database', icon: Icons.storage),
    VaultIconChoice(name: 'key', icon: Icons.vpn_key),
  ];

  /// Picker choices for the color row — keep in sync with the web /
  /// Astro prototype.
  static const List<String> colorChoices = <String>[
    '#FF4F4F', // brand red
    '#FFAB87', // peach
    '#60A5FA', // sky
    '#2EC4B6', // teal
    '#A78BFA', // violet
    '#8A95A6', // slate
  ];

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
      'lock' => Icons.lock,
      'key' || 'vpn_key' => Icons.vpn_key,
      'storage' || 'database' => Icons.storage,
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

/// One entry in the vault icon picker.
class VaultIconChoice {
  const VaultIconChoice({required this.name, required this.icon});

  final String name;
  final IconData icon;
}
