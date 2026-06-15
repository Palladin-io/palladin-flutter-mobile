import '../../domain/entities/notification_preference.dart';

/// JSON ⇄ entity mapper for a `PreferenceItem` from the frozen contract:
/// `{ type, category, inboxEnabled, signalREnabled, pushEnabled, mandatory }`.
class NotificationPreferenceModel {
  const NotificationPreferenceModel({
    required this.type,
    required this.category,
    required this.inboxEnabled,
    required this.signalREnabled,
    required this.pushEnabled,
    required this.mandatory,
  });

  final String type;
  final String category;
  final bool inboxEnabled;
  final bool signalREnabled;
  final bool pushEnabled;
  final bool mandatory;

  factory NotificationPreferenceModel.fromJson(Map<String, dynamic> json) {
    return NotificationPreferenceModel(
      type: json['type'] as String? ?? '',
      category: json['category'] as String? ?? '',
      inboxEnabled: json['inboxEnabled'] as bool? ?? true,
      signalREnabled: json['signalREnabled'] as bool? ?? true,
      pushEnabled: json['pushEnabled'] as bool? ?? false,
      mandatory: json['mandatory'] as bool? ?? false,
    );
  }

  NotificationPreference toEntity() => NotificationPreference(
    type: type,
    category: category,
    inboxEnabled: inboxEnabled,
    signalREnabled: signalREnabled,
    pushEnabled: pushEnabled,
    mandatory: mandatory,
  );
}
