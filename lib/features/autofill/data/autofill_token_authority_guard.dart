import '../../vault/data/services/member_sync_service.dart';
import '../../vault/data/services/member_sync_session_authority_provider.dart';
import 'autofill_source_access_service.dart';

/// Runs inside token serialization before changed claims become readable. It must
/// not bootstrap or read token storage, which would wait on its own mutation.
Future<void> guardAutoFillTokenReplacement({
  required String? previous,
  required String next,
  required AutoFillSourceAccessService source,
}) async {
  try {
    final before = MemberSyncSessionAuthorityProvider.fromAccessToken(previous);
    final after = MemberSyncSessionAuthorityProvider.fromAccessToken(next);
    if (_scope(before) == _scope(after)) return;
  } on FormatException {
    // Unknown authority cannot preserve access to an existing protected source.
  }
  await source.transitionSession();
}

(String, String, String, String, int) _scope(
  MemberSyncSessionAuthority value,
) => (
  value.principalId,
  value.organizationId,
  value.organizationMembershipGeneration,
  value.offlinePolicy,
  value.offlinePolicyVersion,
);
