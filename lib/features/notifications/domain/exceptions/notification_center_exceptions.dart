enum NotificationCenterErrorKind {
  forbidden,
  networkError,
  serverError,
  unknown,
}

class NotificationCenterException implements Exception {
  const NotificationCenterException(this.kind);

  final NotificationCenterErrorKind kind;
}
