import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import 'agent_format.dart';

/// Coloured circular avatar for an agent.
///
/// Renders up-to-two-letter initials derived from the agent name. When
/// the agent has no usable name it falls back to a `smart_toy` glyph.
/// The tint is deterministic per agent id so the avatar stays stable
/// across reloads.
class AgentAvatar extends StatelessWidget {
  const AgentAvatar({
    super.key,
    required this.agentId,
    required this.name,
    this.size = 40,
  });

  /// Server-issued id — seeds the deterministic tint.
  final String agentId;

  /// Agent display name, or `null` when unnamed.
  final String? name;

  /// Diameter of the circle in logical pixels.
  final double size;

  @override
  Widget build(BuildContext context) {
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
