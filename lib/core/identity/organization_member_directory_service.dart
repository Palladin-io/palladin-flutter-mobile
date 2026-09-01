import 'package:dio/dio.dart';

import '../storage/secure_token_storage.dart';
import '../utils/jwt_claims.dart';

/// Memory-only current/former member directory scoped to the active tenant.
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

  String? _organizationId;
  DateTime? _fetchedAt;
  Map<String, String> _names = const {};
  final Set<String> _repairAttemptedIds = <String>{};
  Future<void>? _inFlight;
  int _generation = 0;

  Future<Map<String, String>> resolve(Set<String> requiredUserIds) async {
    if (requiredUserIds.isEmpty) return const {};
    String? token;
    try {
      token = await _tokenStorage.accessToken;
    } catch (_) {
      clear();
      return const {};
    }
    final organizationId = token == null
        ? null
        : JwtClaims.organizationIdFrom(token);
    if (organizationId == null) {
      clear();
      return const {};
    }
    if (_organizationId != organizationId) {
      clear();
      _organizationId = organizationId;
    }

    final now = DateTime.now();
    final stale =
        _fetchedAt == null || now.difference(_fetchedAt!) >= staleTime;
    if (stale) await _refresh();

    final missing = requiredUserIds
        .where((id) => !_names.containsKey(id))
        .where((id) => !_repairAttemptedIds.contains(id))
        .toSet();
    if (missing.isNotEmpty) {
      _repairAttemptedIds.addAll(missing);
      await _refresh();
    }
    return Map.unmodifiable({
      for (final id in requiredUserIds) id: ?_names[id],
    });
  }

  void clear() {
    _generation += 1;
    _organizationId = null;
    _fetchedAt = null;
    _names = const {};
    _repairAttemptedIds.clear();
    _inFlight = null;
  }

  Future<void> _refresh() async {
    final current = _inFlight;
    if (current != null) return current;
    final request = _load(_organizationId, _generation);
    _inFlight = request;
    try {
      await request;
    } finally {
      if (identical(_inFlight, request)) _inFlight = null;
    }
  }

  Future<void> _load(String? organizationId, int generation) async {
    try {
      final response = await _dio.get<Object?>(
        '/api/organization/member-directory',
      );
      final body = response.data;
      if (body is! Map) return;
      final rawItems = body['items'];
      if (rawItems is! List) return;
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
      if (_organizationId == organizationId && _generation == generation) {
        _names = Map.unmodifiable(names);
        _fetchedAt = DateTime.now();
      }
    } on DioException {
      return;
    }
  }
}
