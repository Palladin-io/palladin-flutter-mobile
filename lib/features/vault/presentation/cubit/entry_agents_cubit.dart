import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/services/agent_visibility_projector.dart';
import '../../data/services/canonical_entry_detail_service.dart';
import '../../domain/entities/agent_visibility_policy.dart';
import '../../domain/entities/entry_entity.dart';

sealed class EntryAgentsState {
  const EntryAgentsState();
}

final class EntryAgentsInitial extends EntryAgentsState {
  const EntryAgentsInitial();
}

final class EntryAgentsLoading extends EntryAgentsState {
  const EntryAgentsLoading();
}

final class EntryAgentsLoaded extends EntryAgentsState {
  const EntryAgentsLoaded({
    required this.policy,
    required this.agentLabel,
    required this.discoveryPreview,
    required this.allowedAccess,
    this.saving = false,
  });

  final AgentVisibilityPolicy policy;
  final String agentLabel;
  final Map<String, dynamic> discoveryPreview;
  final Map<String, Set<AgentFieldAccess>> allowedAccess;
  final bool saving;

  EntryAgentsLoaded copyWith({
    AgentVisibilityPolicy? policy,
    String? agentLabel,
    Map<String, dynamic>? discoveryPreview,
    Map<String, Set<AgentFieldAccess>>? allowedAccess,
    bool? saving,
  }) => EntryAgentsLoaded(
    policy: policy ?? this.policy,
    agentLabel: agentLabel ?? this.agentLabel,
    discoveryPreview: discoveryPreview ?? this.discoveryPreview,
    allowedAccess: allowedAccess ?? this.allowedAccess,
    saving: saving ?? this.saving,
  );
}

final class EntryAgentsSaved extends EntryAgentsState {
  const EntryAgentsSaved(this.entry);
  final EntryEntity entry;
}

final class EntryAgentsConflict extends EntryAgentsState {
  const EntryAgentsConflict();
}

final class EntryAgentsError extends EntryAgentsState {
  const EntryAgentsError(this.kind);
  final CanonicalEntryDetailError kind;
}

/// Orchestrates the unlocked, in-memory Agent policy editor.
class EntryAgentsCubit extends Cubit<EntryAgentsState> {
  EntryAgentsCubit(this._service) : super(const EntryAgentsInitial());

  final CanonicalEntryDetailService _service;
  CanonicalEntrySnapshot? _snapshot;
  EntryEntity? _entry;

  Future<void> load({
    required EntryEntity entry,
    required Uint8List memberPrivateKey,
  }) async {
    emit(const EntryAgentsLoading());
    try {
      final snapshot = await _service.reveal(
        expected: entry,
        memberPrivateKey: memberPrivateKey,
      );
      final raw = snapshot.secret['agentVisibilityPolicy'];
      if (raw is! Map) throw const FormatException('Missing Agent policy');
      final policy = AgentVisibilityPolicy.fromJson(
        entry.type,
        Map<String, dynamic>.from(raw),
        content: snapshot.payload,
      );
      _snapshot = snapshot;
      _entry = entry;
      emit(_loaded(snapshot, policy));
    } on CanonicalEntryDetailException catch (error) {
      clearSensitiveState();
      emit(EntryAgentsError(error.kind));
    } on FormatException {
      clearSensitiveState();
      emit(const EntryAgentsError(CanonicalEntryDetailError.corrupt));
    } finally {
      memberPrivateKey.fillRange(0, memberPrivateKey.length, 0);
    }
  }

  void setDiscoverable(bool value) {
    final current = state;
    final snapshot = _snapshot;
    if (current is! EntryAgentsLoaded || snapshot == null) return;
    final fields = Map<String, AgentFieldAccess>.from(current.policy.fields);
    fields['agentLabel'] = value
        ? AgentFieldAccess.discovery
        : AgentFieldAccess.never;
    final next = AgentVisibilityPolicy(discoverable: value, fields: fields);
    emit(_loaded(snapshot, next, agentLabel: current.agentLabel));
  }

  void setAgentLabel(String value) {
    final current = state;
    final snapshot = _snapshot;
    if (current is! EntryAgentsLoaded || snapshot == null) return;
    emit(_loaded(snapshot, current.policy, agentLabel: value));
  }

  void setFieldAccess(String fieldId, AgentFieldAccess access) {
    final current = state;
    final snapshot = _snapshot;
    final entry = _entry;
    if (current is! EntryAgentsLoaded || snapshot == null || entry == null) {
      return;
    }
    final fields = Map<String, AgentFieldAccess>.from(current.policy.fields)
      ..[fieldId] = access;
    final next = AgentVisibilityPolicy.fromJson(
      entry.type,
      AgentVisibilityPolicy(
        discoverable: current.policy.discoverable,
        fields: fields,
      ).toJson(),
      content: snapshot.payload,
    );
    emit(_loaded(snapshot, next, agentLabel: current.agentLabel));
  }

  Future<void> save(Uint8List memberPrivateKey) async {
    final current = state;
    final snapshot = _snapshot;
    final entry = _entry;
    if (current is! EntryAgentsLoaded || snapshot == null || entry == null) {
      memberPrivateKey.fillRange(0, memberPrivateKey.length, 0);
      return;
    }
    if (current.agentLabel.trim().isEmpty && current.policy.discoverable) {
      memberPrivateKey.fillRange(0, memberPrivateKey.length, 0);
      emit(const EntryAgentsError(CanonicalEntryDetailError.corrupt));
      return;
    }
    emit(current.copyWith(saving: true));
    try {
      final updated = await _service.update(
        snapshot: snapshot,
        expected: entry,
        label: snapshot.secret['memberLabel'] as String? ?? entry.label,
        description:
            snapshot.secret['description'] as String? ??
            entry.description ??
            '',
        icon: snapshot.secret['iconReference'] as String? ?? entry.icon ?? '',
        type: entry.type,
        content: snapshot.payload,
        memberPrivateKey: memberPrivateKey,
        agentVisibilityPolicy: current.policy,
        agentLabel: current.agentLabel.trim(),
      );
      clearSensitiveState();
      emit(EntryAgentsSaved(updated));
    } on CanonicalEntryDetailException catch (error) {
      if (error.kind == CanonicalEntryDetailError.conflict) {
        clearSensitiveState();
        emit(const EntryAgentsConflict());
      } else {
        emit(EntryAgentsError(error.kind));
      }
    } finally {
      memberPrivateKey.fillRange(0, memberPrivateKey.length, 0);
    }
  }

  void clearSensitiveState() {
    _snapshot?.payload.clear();
    _snapshot?.secret.clear();
    _snapshot = null;
    _entry = null;
    if (!isClosed) emit(const EntryAgentsInitial());
  }

  EntryAgentsLoaded _loaded(
    CanonicalEntrySnapshot snapshot,
    AgentVisibilityPolicy policy, {
    String? agentLabel,
  }) {
    final label = agentLabel ?? snapshot.secret['agentLabel'] as String? ?? '';
    final description = snapshot.secret['description'] as String? ?? '';
    return EntryAgentsLoaded(
      policy: policy,
      agentLabel: label,
      discoveryPreview: AgentVisibilityProjector.discovery(
        type: _entry!.type,
        agentLabel: label,
        description: description,
        content: snapshot.payload,
        policy: policy,
      ),
      allowedAccess: {
        for (final id in policy.fields.keys)
          id: AgentVisibilityPolicy.allowedFor(
            _entry!.type,
            id,
            snapshot.payload,
          ),
      },
    );
  }

  @override
  Future<void> close() {
    clearSensitiveState();
    return super.close();
  }
}
