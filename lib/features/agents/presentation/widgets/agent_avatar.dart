import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import 'agent_format.dart';

/// Coloured circular avatar for an agent.
///
/// When [iconKey] is set the avatar renders the corresponding Material icon
/// tinted with [agentIconColor]. Otherwise it falls back to up-to-two-letter
/// initials derived from [name], or a `smart_toy` glyph when unnamed.
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

  static bool _isImageUrl(String key) =>
      key.startsWith('https://') ||
      key.startsWith('http://') ||
      key.startsWith('file://');

  @override
  Widget build(BuildContext context) {
    if (iconKey != null && iconKey!.isNotEmpty) {
      if (_isImageUrl(iconKey!)) {
        return _ImageAvatar(url: iconKey!, size: size);
      }
      final color = _parseHex(iconColor) ?? agentIconColor(iconKey!);
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.18),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Icon(
          agentIconData(iconKey!),
          size: size * 0.5,
          color: color,
        ),
      );
    }

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
          ? Icon(
              Icons.smart_toy_outlined,
              size: size * 0.5,
              color: color,
            )
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

/// Circular avatar that renders an image from an https://, http://, or
/// file:// URL. Falls back to a `smart_toy` icon on load error.
class _ImageAvatar extends StatelessWidget {
  const _ImageAvatar({required this.url, required this.size});

  final String url;
  final double size;

  ImageProvider _provider() {
    if (url.startsWith('file://')) {
      return FileImage(File(url.replaceFirst('file://', '')));
    }
    return NetworkImage(url);
  }

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Image(
        image: _provider(),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.vaultSlate.withValues(alpha: 0.18),
            border: Border.all(color: AppColors.vaultSlate.withValues(alpha: 0.45)),
          ),
          child: Icon(Icons.smart_toy_outlined, size: size * 0.5, color: AppColors.vaultSlate),
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
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
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
