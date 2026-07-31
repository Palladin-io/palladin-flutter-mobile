import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/datasources/agent_discovery_remote_datasource.dart';
import '../../data/models/agent_discovery_provisioning.dart';

sealed class AgentDiscoveryState {
  const AgentDiscoveryState();
}

final class AgentDiscoveryLoading extends AgentDiscoveryState {
  const AgentDiscoveryLoading();
}

final class AgentDiscoveryLoaded extends AgentDiscoveryState {
  const AgentDiscoveryLoaded(this.items, {required this.currentVdkVersion});
  final List<AgentDiscoveryProvisioning> items;
  final int currentVdkVersion;
}

final class AgentDiscoveryError extends AgentDiscoveryState {
  const AgentDiscoveryError();
}

final class AgentDiscoveryCubit extends Cubit<AgentDiscoveryState> {
  AgentDiscoveryCubit(this._remote) : super(const AgentDiscoveryLoading());
  final AgentDiscoveryRemote _remote;

  Future<void> load(String vaultId) async {
    emit(const AgentDiscoveryLoading());
    try {
      final results = await Future.wait<Object>([
        _remote.list(vaultId),
        _remote.currentVdkVersion(vaultId),
      ]);
      emit(
        AgentDiscoveryLoaded(
          results[0] as List<AgentDiscoveryProvisioning>,
          currentVdkVersion: results[1] as int,
        ),
      );
    } catch (_) {
      emit(const AgentDiscoveryError());
    }
  }
}
