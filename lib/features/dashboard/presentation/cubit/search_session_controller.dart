import 'search_cubit.dart';

/// Clears every mounted global-search view on a security transition.
final class SearchSessionController {
  final Set<SearchCubit> _active = {};
  final Set<void Function()> _viewClearers = {};

  void attach(SearchCubit cubit) => _active.add(cubit);

  void detach(SearchCubit cubit) => _active.remove(cubit);

  void attachView(void Function() clear) => _viewClearers.add(clear);

  void detachView(void Function() clear) => _viewClearers.remove(clear);

  void lock() {
    for (final cubit in List<SearchCubit>.of(_active)) {
      cubit.securityReset();
    }
    for (final clear in List<void Function()>.of(_viewClearers)) {
      clear();
    }
  }
}
