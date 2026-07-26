import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/audit/domain/entities/audit_log_entry.dart';
import 'package:mobile_palladin/features/audit/presentation/audit_log_format.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

AuditLogEntry _entry(
  AuditEventType type, {
  AuditActorType actorType = AuditActorType.user,
  String? actorName,
  String? agentName,
  String? agentId,
  String? userId,
  String? entryId,
  String? entryLabel,
  String? resolvedObjectName,
  bool localPresentationOnly = false,
  Map<String, String> metadata = const {},
}) {
  return AuditLogEntry(
    id: 'log',
    eventType: type,
    rawEventType: type.wire,
    actorType: actorType,
    createdAt: DateTime(2026, 6, 1),
    actorName: actorName,
    agentName: agentName,
    agentId: agentId,
    userId: userId,
    entryId: entryId,
    entryLabel: entryLabel,
    resolvedObjectName: resolvedObjectName,
    localPresentationOnly: localPresentationOnly,
    metadata: metadata,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppLocalizations en;

  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
  });

  String plain(List<AuditSentenceSpan> spans) =>
      spans.map((s) => s.text).join();
  List<String> bold(List<AuditSentenceSpan> spans) =>
      spans.where((s) => s.bold).map((s) => s.text.trim()).toList();

  group('auditEventSentence — who + action + object', () {
    test('vault.created with a name reads actor + action + bold object', () {
      final spans = auditEventSentence(
        en,
        _entry(
          AuditEventType.vaultCreated,
          actorName: 'Patryk',
          metadata: const {'name': 'Production'},
        ),
        const {},
      )!;
      expect(plain(spans), 'Patryk created vault Production');
      expect(bold(spans), ['Patryk', 'Production']);
    });

    test('vault.created without a name uses a generic, non-id fallback', () {
      final spans = auditEventSentence(
        en,
        _entry(AuditEventType.vaultCreated, actorName: 'Patryk'),
        const {},
      )!;
      expect(plain(spans), 'Patryk created a vault');
      expect(bold(spans), ['Patryk']);
    });

    test('entry.created uses the entry label as the object', () {
      final spans = auditEventSentence(
        en,
        _entry(
          AuditEventType.entryCreated,
          actorName: 'Patryk',
          entryLabel: 'Stripe Key',
        ),
        const {},
      )!;
      expect(plain(spans), 'Patryk created entry Stripe Key');
      expect(bold(spans), ['Patryk', 'Stripe Key']);
    });

    test('Vault log ignores server names and safely shortens purged ids', () {
      final spans = auditEventSentence(
        en,
        _entry(
          AuditEventType.entryDeleted,
          actorName: 'Server User',
          userId: 'user-1234567890-opaque',
          entryId: 'entry-1234567890-purged',
          entryLabel: 'Server Entry',
          metadata: const {'name': 'Server Metadata'},
          localPresentationOnly: true,
        ),
        const {},
      )!;

      expect(plain(spans), 'user-123…opaque deleted entry entry-12…purged');
      expect(plain(spans), isNot(contains('Server')));
    });

    test('org.created reads from metadata.name', () {
      final spans = auditEventSentence(
        en,
        _entry(
          AuditEventType.orgCreated,
          actorName: 'Patryk',
          metadata: const {'name': 'Acme'},
        ),
        const {},
      )!;
      expect(plain(spans), 'Patryk created organization Acme');
    });

    test('apikey.revoked reads from metadata.keyName', () {
      final spans = auditEventSentence(
        en,
        _entry(
          AuditEventType.apikeyRevoked,
          actorName: 'Patryk',
          metadata: const {'keyName': 'CI deploy'},
        ),
        const {},
      )!;
      expect(plain(spans), 'Patryk revoked API key CI deploy');
      expect(bold(spans), ['Patryk', 'CI deploy']);
    });

    test('agent.blocked names actor and the affected agent', () {
      final spans = auditEventSentence(
        en,
        _entry(
          AuditEventType.agentBlocked,
          actorName: 'Patryk',
          agentName: 'claude-code-01',
          agentId: 'a-1',
        ),
        const {},
      )!;
      expect(plain(spans), 'Patryk blocked agent claude-code-01');
      expect(bold(spans), ['Patryk', 'claude-code-01']);
    });

    test('agent.enrolled subject is the agent', () {
      final spans = auditEventSentence(
        en,
        _entry(
          AuditEventType.agentEnrolled,
          actorType: AuditActorType.agent,
          agentName: 'github-copilot',
          agentId: 'a-2',
        ),
        const {},
      )!;
      expect(plain(spans), 'github-copilot enrolled in the system');
      expect(bold(spans), ['github-copilot']);
    });

    test('user.signed-up is a single-actor sentence', () {
      final spans = auditEventSentence(
        en,
        _entry(AuditEventType.userSignedUp, actorName: 'Patryk'),
        const {},
      )!;
      expect(plain(spans), 'Patryk signed up');
      expect(bold(spans), ['Patryk']);
    });

    test('unknown actor falls back to a localized label, never an id', () {
      final spans = auditEventSentence(
        en,
        _entry(AuditEventType.vaultUpdated, metadata: const {'name': 'Prod'}),
        const {},
      )!;
      expect(plain(spans), 'Unknown user updated vault Prod');
      expect(bold(spans), ['Unknown user', 'Prod']);
    });

    test(
      'a name containing the bold sentinel does not break span alignment',
      () {
        // Defensive: hostile backend input with a NUL control char inside a name
        // must not mis-align the bold-run split.
        final nul = String.fromCharCode(0);
        final spans = auditEventSentence(
          en,
          _entry(
            AuditEventType.vaultCreated,
            actorName: 'Pa${nul}tryk',
            metadata: {'name': 'Pro${nul}d'},
          ),
          const {},
        )!;
        expect(plain(spans), 'Patryk created vault Prod');
        expect(bold(spans), ['Patryk', 'Prod']);
      },
    );

    test('actor falls back to the cached agent name when no actorName', () {
      final spans = auditEventSentence(
        en,
        _entry(
          AuditEventType.entryUpdated,
          actorType: AuditActorType.agent,
          agentId: 'a-9',
          entryLabel: 'Token',
        ),
        const {'a-9': 'cursor-ai'},
      )!;
      expect(plain(spans), 'cursor-ai updated entry Token');
    });

    test(
      'grant.* / credential.* / unknown keep the legacy rendering (null)',
      () {
        for (final type in [
          AuditEventType.grantCreated,
          AuditEventType.grantApproved,
          AuditEventType.credentialAccessed,
          AuditEventType.credentialAccessDenied,
          AuditEventType.unknown,
        ]) {
          expect(
            auditEventSentence(en, _entry(type, actorName: 'X'), const {}),
            isNull,
            reason: '$type',
          );
        }
      },
    );
  });
}
