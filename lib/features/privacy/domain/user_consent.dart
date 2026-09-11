class ConsentNotice {
  const ConsentNotice({
    required this.version,
    required this.locale,
    required this.text,
  });
  final String version;
  final String locale;
  final String text;
}

class UserConsent {
  const UserConsent({
    required this.purpose,
    required this.scope,
    required this.status,
    required this.revision,
    required this.activationRevision,
    this.recordedAt,
    this.noticeVersion,
    this.noticeLocale,
    this.currentNotice,
  });
  final String purpose;
  final String scope;
  final String status;
  final int revision;
  final int activationRevision;
  final DateTime? recordedAt;
  final String? noticeVersion;
  final String? noticeLocale;
  final ConsentNotice? currentNotice;
  bool get granted => status == 'granted';
}

class UserConsents {
  const UserConsents(this.consents, this.maxAgeSeconds);
  final List<UserConsent> consents;
  final int maxAgeSeconds;
}

class ConsentDecision {
  const ConsentDecision({
    required this.purpose,
    required this.granted,
    required this.expectedRevision,
    required this.requestId,
    required this.noticeVersion,
    required this.locale,
    required this.source,
  });
  final String purpose;
  final bool granted;
  final int expectedRevision;
  final String requestId;
  final String noticeVersion;
  final String locale;
  final String source;
}

enum ConsentErrorKind { load, save, localStorage, staleSession }
