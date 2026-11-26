import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../design/mobile/preview_binding.dart';

class _LifecycleObserver extends WidgetsBindingObserver {
  final states = <AppLifecycleState>[];

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => states.add(state);
}

void main() {
  final binding = PreviewBinding();

  test(
    'moving focus between preview frames does not suspend or reload fixtures',
    () {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final observer = _LifecycleObserver();
      binding.addObserver(observer);
      addTearDown(() => binding.removeObserver(observer));

      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.resumed,
      ]) {
        binding.handleAppLifecycleStateChanged(state);
      }

      expect(binding.lifecycleState, AppLifecycleState.resumed);
      expect(observer.states, isEmpty);
    },
  );
}
