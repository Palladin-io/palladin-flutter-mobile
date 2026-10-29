import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../public_asset_catalog/presentation/widgets/public_asset_image.dart';
import 'agent_format.dart';

/// Coloured circular avatar for an agent.
///
/// When [iconKey] is set the avatar renders the corresponding Material icon
/// tinted with [agentIconColor], or an uploaded `public-asset:` icon loaded
/// from the configured API. Otherwise — including any raw URL — it falls back
/// to up-to-two-letter initials derived from [name], or a `smart_toy` glyph
/// when unnamed.
/// The tint for initials/fallback is deterministic per [agentId].
class AgentAvatar extends StatelessWidget {
  const AgentAvatar({
    super.key,
    required this.agentId,
    required this.name,
    this.iconKey,
    this.iconColor,
    this.size = 40,
  });

  /// Server-issued id — seeds the deterministic tint for the initials avatar.
  final String agentId;

  /// Agent display name, or `null` when unnamed.
  final String? name;

  /// Material icon name chosen for the agent, e.g. `"terminal"`. When set
  /// the icon is rendered instead of initials.
  final String? iconKey;

  /// Hex color string (e.g. `"#10B981"`) for the icon tint. Overrides
  /// [agentIconColor]'s deterministic per-icon color when set.
  final String? iconColor;

  /// Diameter of the circle in logical pixels.
  final double size;

  static Color? _parseHex(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    final cleaned = hex.startsWith('#') ? hex.substring(1) : hex;
    final value = int.tryParse(cleaned, radix: 16);
    if (value == null) return null;
    return Color(cleaned.length == 6 ? 0xFF000000 | value : value);
  }

  @override
  Widget build(BuildContext context) {
    final key = iconKey ?? '';
    if (key.startsWith('public-asset:')) {
      return ClipOval(
        child: PublicAssetImage(
          reference: key,
          width: size,
          height: size,
          fallback: _initialsAvatar(),
        ),
      );
    }
    // A server-supplied URL must not make viewers fetch arbitrary hosts or
    // read local files; icon keys are plain glyph names.
    if (key.isNotEmpty && !key.contains(':')) {
      final color = _parseHex(iconColor) ?? agentIconColor(key);
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.18),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Icon(agentIconData(key), size: size * 0.5, color: color),
      );
    }
    return _initialsAvatar();
  }

  Widget _initialsAvatar() {
    final color = agentAvatarColor(agentId);
    final initials = agentInitials(name);

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.18),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: initials.isEmpty
          ? Icon(Icons.smart_toy_outlined, size: size * 0.5, color: color)
          : Text(
              initials,
              style: TextStyle(
                color: color,
                fontSize: size * 0.36,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
    );
  }
}

/// Small status dot — green for active, amber for pending, slate for
/// deactivated. Used on the agent list card.
class AgentStatusDot extends StatelessWidget {
  const AgentStatusDot({super.key, required this.color, this.size = 8});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

/// Resolves the semantic colour for an agent status.
///
/// Shared by [AgentStatusDot] and the status badge so the dot and pill
/// never drift apart.
Color agentStatusColor(bool isActive, bool isPending) {
  if (isActive) return AppColors.positiveAccent;
  if (isPending) return AppColors.strengthFair;
  return AppColors.vaultSlate;
}
