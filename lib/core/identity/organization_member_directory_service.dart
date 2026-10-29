import 'package:dio/dio.dart';

import '../storage/secure_token_storage.dart';
import '../utils/jwt_claims.dart';

/// An operation-local view of the shared cache and whether misses may be repaired.
final class MemberDirectorySnapshot {
  const MemberDirectorySnapshot(this.names, {required this.canRepair});

  final Map<String, String> names;
  final bool canRepair;
}

/// Memory-only current/former member directory scoped to the active account and tenant.
final class OrganizationMemberDirectoryService {
  OrganizationMemberDirectoryService({
    required Dio dio,
    required SecureTokenStorage tokenStorage,
    this.staleTime = const Duration(minutes: 5),
  }) : _dio = dio,
       _tokenStorage = tokenStorage;

  final Dio _dio;
  final SecureTokenStorage _tokenStorage;
  final Duration staleTime;

  ({String accountId, String organizationId})? _identity;
  DateTime? _fetchedAt;
  Map<String, String> _names = const {};
  final Set<String> _repairAttemptedIds = <String>{};
  Future<bool>? _inFlight;
  int _generation = 0;

  Future<Map<String, String>> resolve(
    Set<String> requiredUserIds, {
    String? expectedAccountId,
    String? expectedOrganizationId,
  }) async => (await _resolve(
    requiredUserIds,
    expectedAccountId: expectedAccountId,
    expectedOrganizationId: expectedOrganizationId,
    repairMissing: true,
  )).names;

  /// Loads the shared snapshot without starting a per-row missing-id repair.
  /// Call [resolve] once with the collected misses when hydration finishes.
  Future<MemberDirectorySnapshot> availableSnapshot({
    required String expectedAccountId,
    required String expectedOrganizationId,
  }) => _resolve(
    null,
    expectedAccountId: expectedAccountId,
    expectedOrganizationId: expectedOrganizationId,
    repairMissing: false,
  );

  Future<MemberDirectorySnapshot> _resolve(
    Set<String>? requiredUserIds, {
    required String? expectedAccountId,
    required String? expectedOrganizationId,
    required bool repairMissing,
  }) async {
    if (requiredUserIds?.isEmpty == true) {
      return const MemberDirectorySnapshot({}, canRepair: false);
    }
    final beforeTokenRead = _generation;
    final identity = await _readIdentity();
    if (beforeTokenRead != _generation) {
      return const MemberDirectorySnapshot({}, canRepair: false);
    }
    if (identity == null) {
      clear();
      return const MemberDirectorySnapshot({}, canRepair: false);
    }
    if ((expectedAccountId != null &&
            identity.accountId != expectedAccountId) ||
        (expectedOrganizationId != null &&
            identity.organizationId != expectedOrganizationId)) {
      return const MemberDirectorySnapshot({}, canRepair: false);
    }
    if (_identity != identity) {
      if (_identity != null) clear();
      _identity = identity;
    }
    final generation = _generation;
    final now = DateTime.now();
    final stale =
        _fetchedAt == null || now.difference(_fetchedAt!) >= staleTime;
    if (stale) {
      final refreshed = await _refresh();
      if (!await _isCurrent(identity, generation)) {
        return const MemberDirectorySnapshot({}, canRepair: false);
      }
      if (!refreshed) {
        return MemberDirectorySnapshot(
          _select(requiredUserIds),
          canRepair: false,
        );
      }
    }

    if (repairMissing && requiredUserIds != null) {
      final missing = requiredUserIds
          .where((id) => !_names.containsKey(id))
          .where((id) => !_repairAttemptedIds.contains(id))
          .toSet();
      if (missing.isNotEmpty) {
        _repairAttemptedIds.addAll(missing);
        await _refresh();
        if (!await _isCurrent(identity, generation)) {
          return const MemberDirectorySnapshot({}, canRepair: false);
        }
      }
    }
    return MemberDirectorySnapshot(_select(requiredUserIds), canRepair: true);
  }

  Map<String, String> _select(Set<String>? requiredUserIds) =>
      requiredUserIds == null
      ? _names
      : Map.unmodifiable({for (final id in requiredUserIds) id: ?_names[id]});

  Future<({String accountId, String organizationId})?> _readIdentity() async {
    try {
      final token = await _tokenStorage.accessToken;
      if (token == null) return null;
      final accountId = JwtClaims.decodePayload(token)['sub'];
      final organizationId = JwtClaims.organizationIdFrom(token);
      if (accountId is! String || accountId.isEmpty || organizationId == null) {
        return null;
      }
      return (accountId: accountId, organizationId: organizationId);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _isCurrent(
    ({String accountId, String organizationId}) identity,
    int generation,
  ) async {
    if (_generation != generation || _identity != identity) return false;
    final current = await _readIdentity();
    if (_generation != generation) return false;
    if (current != identity) {
      clear();
      return false;
    }
    return true;
  }

  void clear() {
    _generation += 1;
    _identity = null;
    _fetchedAt = null;
    _names = const {};
    _repairAttemptedIds.clear();
    _inFlight = null;
  }

  Future<bool> _refresh() async {
    final current = _inFlight;
    if (current != null) return current;
    final request = _load(_identity, _generation);
    _inFlight = request;
    try {
      return await request;
    } finally {
      if (identical(_inFlight, request)) _inFlight = null;
    }
  }

  Future<bool> _load(
    ({String accountId, String organizationId})? identity,
    int generation,
  ) async {
    try {
      final response = await _dio.get<Object?>(
        '/api/organization/member-directory',
      );
      final body = response.data;
      if (body is! Map) return false;
      final rawItems = body['items'];
      if (rawItems is! List) return false;
      final names = <String, String>{};
      for (final raw in rawItems) {
        if (raw is! Map) continue;
        final userId = raw['userId'];
        final displayName = raw['displayName'];
        if (userId is! String || displayName is! String) continue;
        final normalized = displayName.trim();
        if (userId.isNotEmpty && normalized.isNotEmpty) {
          names[userId] = normalized;
        }
      }
      if (_identity == identity && _generation == generation) {
        _names = Map.unmodifiable(names);
        _fetchedAt = DateTime.now();
        return true;
      }
      return false;
    } on DioException {
      return false;
    }
  }
}
