import 'dart:async';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/core/widgets/app_action_footer.dart';
import 'package:mobile_palladin/core/widgets/app_fab.dart';
import 'package:mobile_palladin/core/widgets/primary_button.dart';
import 'package:mobile_palladin/features/agents/domain/entities/agent.dart';
import 'package:mobile_palladin/features/agents/domain/exceptions/agents_exceptions.dart';
import 'package:mobile_palladin/features/agents/domain/repositories/agents_repository.dart';
import 'package:mobile_palladin/features/agents/presentation/bloc/agents_cubit.dart';
import 'package:mobile_palladin/features/agents/presentation/widgets/agent_detail_body.dart';
import 'package:mobile_palladin/features/agents/presentation/widgets/agent_edit_form.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';
import '../../design/mobile/bootstrap.dart';

class _Repository extends Mock implements AgentsRepository {}

class _Auth extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

void main() {
  testWidgets(
    'root Agent editor preserves failed draft and reacts to permission loss',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.padding = const FakeViewPadding(bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(bottom: 34);
      addTearDown(tester.view.reset);
      final agent = Agent(
        agentId: 'a',
        name: 'Agent',
        status: AgentStatus.active,
        publicKeySuffix: 'abcd',
        createdAt: DateTime.utc(2026),
      );
      final repo = _Repository();
      when(() => repo.listAgents()).thenAnswer((_) async => [agent]);
      when(
        () => repo.updateAgent(
          any(),
          name: any(named: 'name'),
          description: any(named: 'description'),
          type: any(named: 'type'),
          iconKey: any(named: 'iconKey'),
          iconColor: any(named: 'iconColor'),
        ),
      ).thenThrow(const AgentsException(AgentsErrorKind.networkError));
      final cubit = AgentsCubit(repository: repo);
      await cubit.load();
      addTearDown(cubit.close);
      final auth = _Auth();
      final authStates = StreamController<AuthState>();
      whenListen(auth, authStates.stream, initialState: demoSession());
      addTearDown(authStates.close);
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<AgentsCubit>.value(value: cubit),
            BlocProvider<AuthBloc>.value(value: auth),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: BlocListener<AgentsCubit, AgentsState>(
              listener: (_, state) {
                if (state.mutationError != null) {
                  cubit.acknowledgeMutationError();
                }
              },
              child: Scaffold(
                body: AgentDetailBody(
                  agent: agent,
                  isMutating: false,
                  onApprove: () {},
                  onDeactivate: () {},
                  onReactivate: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(AppFab));
      await tester.pumpAndSettle();
      expect(tester.getBottomRight(find.byType(AppActionFooter)).dy, 844);
      await tester.enterText(find.byType(TextField).first, 'Retained draft');
      await tester.pump();
      await tester.tap(find.byType(PrimaryButton));
      await tester.pumpAndSettle();
      expect(find.byType(AgentEditForm), findsOneWidget);
      expect(find.text('Retained draft'), findsOneWidget);
      when(() => repo.listAgents()).thenAnswer(
        (_) async => [
          Agent(
            agentId: 'a',
            name: 'Agent',
            status: AgentStatus.deactivated,
            publicKeySuffix: 'abcd',
            createdAt: DateTime.utc(2026),
          ),
        ],
      );
      await cubit.load();
      await tester.pumpAndSettle();
      expect(
        tester.widget<AgentEditForm>(find.byType(AgentEditForm)).canEdit,
        isFalse,
      );
      when(() => repo.listAgents()).thenAnswer((_) async => [agent]);
      await cubit.load();
      await tester.pumpAndSettle();
      expect(
        tester.widget<AgentEditForm>(find.byType(AgentEditForm)).canEdit,
        isTrue,
      );
      authStates.add(const AuthUnauthenticated());
      await tester.pumpAndSettle();
      expect(
        tester.widget<AgentEditForm>(find.byType(AgentEditForm)).canEdit,
        isFalse,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
