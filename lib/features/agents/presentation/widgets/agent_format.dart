/// Presentation-layer helpers for the agents feature.
///
/// Kept as pure functions so they can be unit-tested without a widget
/// tree and reused across the list card, detail page and edit page.
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/entities/agent.dart';
import '../../domain/exceptions/agents_exceptions.dart';

/// Resolves an [AgentsErrorKind] to a localized, user-facing message.
///
/// Lives at the presentation layer — the data/domain layers only ever
/// carry the typed enum, never user-facing text.
String agentsErrorMessage(AppLocalizations l10n, AgentsErrorKind kind) {
  return switch (kind) {
    AgentsErrorKind.notFound => l10n.settingsErrorNotFound,
    AgentsErrorKind.forbidden => l10n.settingsErrorForbidden,
    AgentsErrorKind.validation => l10n.settingsErrorValidation,
    AgentsErrorKind.networkError => l10n.errorCannotConnectToServer,
    AgentsErrorKind.unknown => l10n.settingsErrorUnknown,
  };
}

/// Formats a date as `MMM d` (e.g. `Feb 20`) — locale-neutral and short.
///
/// Used for the agent card subtitle and detail rows where only the
/// calendar day matters.
String formatAgentDate(DateTime date) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final d = date.toLocal();
  return '${months[d.month - 1]} ${d.day}';
}

/// Builds the display name for an agent, falling back to a short id-based
/// label when the agent has not been named yet.
String agentDisplayName(AppLocalizations l10n, Agent agent) {
  final name = agent.name?.trim();
  if (name != null && name.isNotEmpty) return name;
  return l10n.agentsUnnamed;
}

/// Up-to-two-letter initials for the avatar circle.
///
/// Splits on hyphens and spaces so `claude-code-01` → `CC`. Falls back
/// to an empty string when the agent has no usable name — the avatar
/// then renders the `smart_toy` icon instead.
String agentInitials(String? name) {
  final trimmed = name?.trim() ?? '';
  if (trimmed.isEmpty) return '';
  final parts = trimmed
      .split(RegExp(r'[\s\-_]+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '';
  if (parts.length == 1) {
    final p = parts.first;
    return p.length == 1
        ? p.toUpperCase()
        : p.substring(0, 2).toUpperCase();
  }
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

/// Deterministically picks an avatar tint for an agent from a fixed
/// palette, keyed on the agent id so the colour is stable across loads.
Color agentAvatarColor(String agentId) {
  const palette = [
    AppColors.vaultPeach,
    AppColors.vaultBlue,
    AppColors.vaultViolet,
    AppColors.positiveAccent,
    AppColors.strengthFair,
  ];
  if (agentId.isEmpty) return AppColors.vaultSlate;
  final hash = agentId.codeUnits.fold<int>(0, (acc, c) => acc + c);
  return palette[hash % palette.length];
}
