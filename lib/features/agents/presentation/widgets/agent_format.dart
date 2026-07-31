/// Presentation-layer helpers for the agents feature.
///
/// Kept as pure functions so they can be unit-tested without a widget
/// tree and reused across the list card, detail page and edit page.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/entities/agent.dart';
import '../../domain/exceptions/agents_exceptions.dart';

String agentColorHex(Color color) {
  final r = (color.r * 255).round();
  final g = (color.g * 255).round();
  final b = (color.b * 255).round();
  return '#${r.toRadixString(16).padLeft(2, '0')}'
      '${g.toRadixString(16).padLeft(2, '0')}'
      '${b.toRadixString(16).padLeft(2, '0')}';
}

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

/// Formats a date as a short month + day (e.g. `Feb 20` / `20 lut`),
/// localized for [locale].
///
/// Used for the agent card subtitle and detail rows where only the
/// calendar day matters. Pass `Localizations.localeOf(context).toString()`
/// from the call site so a Polish user sees `20 lut` instead of `Feb 20`.
String formatAgentDate(DateTime date, String locale) {
  return DateFormat.MMMd(locale).format(date.toLocal());
}

/// Formats a date with time as a short month + day + `HH:mm`
/// (e.g. `Feb 20, 14:32`), localized for [locale].
///
/// Used for detail rows where the exact time is relevant (e.g. first connected).
String formatAgentDateTime(DateTime date, String locale) {
  final d = date.toLocal();
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  return '${formatAgentDate(date, locale)}, $hh:$mm';
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
    return p.length == 1 ? p.toUpperCase() : p.substring(0, 2).toUpperCase();
  }
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

/// The thirteen built-in agent-type wire values, paired with their
/// localized label. Mirrors the `BUILTIN_AGENT_TYPES` list shipped by the
/// web panel so both surfaces offer the same set of presets.
///
/// Order is fixed (alphabetical by label, with "Other" pinned last) so
/// the approve form renders the chips consistently across sessions.
List<({String value, String label})> agentTypeOptions(AppLocalizations l10n) {
  return [
    (value: 'aider', label: l10n.agentTypeAider),
    (value: 'claudeCode', label: l10n.agentTypeClaudeCode),
    (value: 'cline', label: l10n.agentTypeCline),
    (value: 'codex', label: l10n.agentTypeCodex),
    (value: 'copilot', label: l10n.agentTypeCopilot),
    (value: 'cursor', label: l10n.agentTypeCursor),
    (value: 'devin', label: l10n.agentTypeDevin),
    (value: 'gemini', label: l10n.agentTypeGemini),
    (value: 'hermes', label: l10n.agentTypeHermes),
    (value: 'kimiCode', label: l10n.agentTypeKimiCode),
    (value: 'openClaw', label: l10n.agentTypeOpenClaw),
    (value: 'roo', label: l10n.agentTypeRoo),
    (value: 'other', label: l10n.agentTypeOther),
  ];
}

/// Resolves a type wire value to its localized label, or `null` when the
/// value is unknown / unset — used by the detail screen's type badge.
String? agentTypeLabel(AppLocalizations l10n, String? type) {
  if (type == null) return null;
  for (final option in agentTypeOptions(l10n)) {
    if (option.value == type) return option.label;
  }
  return null;
}

/// Material icon names offered in the approve form's icon picker,
/// in display order. Mirrors the web panel's `AGENT_ICON_OPTIONS` so
/// the two surfaces stay visually aligned.
const List<String> agentIconOptions = [
  'smart_toy',
  'memory',
  'hub',
  'token',
  'terminal',
  'psychology',
  'auto_mode',
  'support_agent',
  'dns',
  'code',
  'api',
  'cloud',
  'extension',
  'bolt',
  'developer_mode',
];

/// Full browsable icon set shown in the icon-browser modal. Mirrors the
/// web panel's `AGENT_ICON_ALL` — superset of [agentIconOptions] plus a
/// handful of extra glyphs available only via "more".
const List<String> agentIconAll = [
  'smart_toy',
  'memory',
  'hub',
  'token',
  'terminal',
  'psychology',
  'auto_mode',
  'support_agent',
  'dns',
  'code',
  'api',
  'extension',
  'computer',
  'bolt',
  'cloud',
  'assistant',
  'data_object',
  'precision_manufacturing',
  'settings_suggest',
  'manage_search',
  'batch_prediction',
  'android',
  'biotech',
  'developer_mode',
];

/// Six selectable accent colors for the agent icon. Mirrors the web
/// panel's `COLOR_OPTIONS` in `agent-icon-picker.tsx` so the two
/// surfaces offer the same palette.
const List<Color> agentColorOptions = [
  AppColors.brandRed,
  AppColors.vaultPeach,
  AppColors.vaultBlue,
  AppColors.positiveAccent,
  AppColors.vaultViolet,
  AppColors.vaultSlate,
];

/// Default selected color in the icon picker — matches the web panel's
/// `DEFAULT_AGENT_COLOR` (teal / `#10B981`).
const Color defaultAgentColor = AppColors.positiveAccent;

/// Per-glyph accent colour used as the unselected tint on the icon
/// picker — mirrors the web panel's `AGENT_ICON_COLORS` map so the same
/// preset reads with the same colour on every surface.
Color agentIconColor(String iconKey) {
  return switch (iconKey) {
    'smart_toy' => AppColors.positiveAccent,
    'terminal' => AppColors.positiveAccent,
    'auto_mode' => AppColors.positiveAccent,
    'code' => AppColors.positiveAccent,
    'api' => AppColors.positiveAccent,
    'developer_mode' => AppColors.positiveAccent,
    'memory' => AppColors.vaultSlate,
    'dns' => AppColors.vaultSlate,
    'hub' => AppColors.vaultBlue,
    'support_agent' => AppColors.vaultBlue,
    'cloud' => AppColors.vaultBlue,
    'token' => AppColors.vaultViolet,
    'psychology' => AppColors.vaultViolet,
    'extension' => AppColors.vaultViolet,
    'assistant' => AppColors.vaultViolet,
    'batch_prediction' => AppColors.vaultViolet,
    'bolt' => AppColors.vaultPeach,
    'precision_manufacturing' => AppColors.vaultPeach,
    'computer' => AppColors.vaultBlue,
    'manage_search' => AppColors.vaultBlue,
    'data_object' => AppColors.positiveAccent,
    'android' => AppColors.positiveAccent,
    'biotech' => AppColors.positiveAccent,
    'settings_suggest' => AppColors.vaultSlate,
    _ => AppColors.vaultSlate,
  };
}

/// Maps a stored [iconKey] to its [IconData].
///
/// Falls back to `smart_toy` for an unknown or `null` key so the UI
/// always has a glyph to render. Covers both [agentIconOptions]
/// (presets) and [agentIconAll] (browser superset).
IconData agentIconData(String? iconKey) {
  return switch (iconKey) {
    'smart_toy' => Icons.smart_toy,
    'memory' => Icons.memory,
    'hub' => Icons.hub,
    'token' => Icons.token,
    'terminal' => Icons.terminal,
    'psychology' => Icons.psychology,
    'auto_mode' => Icons.auto_mode,
    'support_agent' => Icons.support_agent,
    'dns' => Icons.dns,
    'code' => Icons.code,
    'api' => Icons.api,
    'cloud' => Icons.cloud,
    'extension' => Icons.extension,
    'bolt' => Icons.bolt,
    'developer_mode' => Icons.developer_mode,
    // Extra glyphs surfaced only via the icon browser ("more" tile).
    'computer' => Icons.computer,
    'assistant' => Icons.assistant,
    'data_object' => Icons.data_object,
    'precision_manufacturing' => Icons.precision_manufacturing,
    'settings_suggest' => Icons.settings_suggest,
    'manage_search' => Icons.manage_search,
    'batch_prediction' => Icons.batch_prediction,
    'android' => Icons.android,
    'biotech' => Icons.biotech,
    _ => Icons.smart_toy,
  };
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
