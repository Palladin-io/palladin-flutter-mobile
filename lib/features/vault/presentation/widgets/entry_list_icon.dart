import 'package:flutter/material.dart';

import '../../../public_asset_catalog/presentation/widgets/public_asset_image.dart';
import '../../data/services/encrypted_presentation_asset_service.dart';
import '../../domain/entities/entry_entity.dart';
import 'encrypted_asset_image.dart';
import 'vault_visuals.dart';

/// Authenticated encrypted/custom or immutable public icon with a local glyph fallback.
class EntryListIcon extends StatelessWidget {
  const EntryListIcon({super.key, required this.entry});

  final EntryEntity entry;

  @override
  Widget build(BuildContext context) {
    final icon = entry.icon;

    if (icon?.startsWith('asset:') ?? false) {
      return SizedBox(
        width: 40,
        height: 40,
        child: ClipOval(
          child: EncryptedAssetImage(
            reference: icon!,
            target: PresentationAssetTarget.entry,
            vaultId: entry.vaultId,
            entryId: entry.id,
            width: 40,
            height: 40,
            fallback: _presetIcon(null),
          ),
        ),
      );
    }

    if (icon?.startsWith('public-asset:') ?? false) {
      return SizedBox(
        width: 40,
        height: 40,
        child: ClipOval(
          child: PublicAssetImage(
            reference: icon!,
            width: 40,
            height: 40,
            fallback: _presetIcon(null),
          ),
        ),
      );
    }

    if (!EntryVisuals.isCustomUrl(icon)) {
      return _presetIcon(icon);
    }

    return _presetIcon(null);
  }

  Widget _presetIcon(String? name) {
    final choices = EntryVisuals.iconChoices;
    final fallbackName = switch (entry.type) {
      EntryType.key => choices.first.name,
      EntryType.credential => 'lock',
      EntryType.script => 'terminal',
      EntryType.creditCard => 'credit_card',
    };
    final choice = choices.firstWhere(
      (c) => c.name == (name ?? fallbackName),
      orElse: () => choices.firstWhere(
        (c) => c.name == fallbackName,
        orElse: () => choices.first,
      ),
    );
    final iconColor = choice.paletteColor;
    final iconBg = iconColor.withValues(alpha: 0.15);
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: iconBg),
      child: Icon(choice.icon, size: 20, color: iconColor),
    );
  }
}
