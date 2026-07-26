import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/vault/data/datasources/agent_discovery_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/models/agent_discovery_provisioning.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/agent_discovery_cubit.dart';

class _Remote extends Mock implements AgentDiscoveryRemote {}

void main() {
  blocTest<AgentDiscoveryCubit, AgentDiscoveryState>(
    'publishes current VDK epoch with current and stale Agent statuses',
    build: () {
      final remote = _Remote();
      when(() => remote.currentVdkVersion('vault')).thenAnswer((_) async => 8);
      when(() => remote.list('vault')).thenAnswer(
        (_) async => const [
          AgentDiscoveryProvisioning(
            agentId: 'a-current',
            agentName: 'Builder',
            recipientKeyVersion: 3,
            x25519PublicKey: 'x',
            ed25519PublicKey: 'e',
            status: 'current',
            manifestRevision: '12',
          ),
          AgentDiscoveryProvisioning(
            agentId: 'a-stale',
            recipientKeyVersion: 4,
            x25519PublicKey: 'x',
            ed25519PublicKey: 'e',
            status: 'pending',
            manifestRevision: '11',
          ),
        ],
      );
      return AgentDiscoveryCubit(remote);
    },
    act: (cubit) => cubit.load('vault'),
    expect: () => [
      isA<AgentDiscoveryLoading>(),
      isA<AgentDiscoveryLoaded>()
          .having((state) => state.currentVdkVersion, 'VDK version', 8)
          .having(
            (state) => state.items.map((item) => item.isCurrent).toList(),
            'provisioning status',
            [true, false],
          ),
    ],
  );
}
