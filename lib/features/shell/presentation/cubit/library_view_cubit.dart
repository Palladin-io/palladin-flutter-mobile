import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/storage/user_preferences.dart';

class LibraryViewCubit extends Cubit<bool> {
  LibraryViewCubit(this._preferences) : super(true) {
    ready = _restore();
  }

  final UserPreferences _preferences;
  late final Future<void> ready;
  Future<void> _pendingWrite = Future.value();
  bool _selected = false;

  String get route => state ? '/entries' : '/vaults';

  Future<void> _restore() async {
    try {
      final entries = await _preferences.libraryEntries;
      if (!isClosed && !_selected) emit(entries);
    } catch (_) {
      // A device preference must not prevent library navigation.
    }
  }

  Future<void> select(bool entries) {
    _selected = true;
    emit(entries);
    return _pendingWrite = _pendingWrite.then((_) async {
      try {
        await _preferences.saveLibraryEntries(entries);
      } catch (_) {
        // Retain the in-session choice when device storage is unavailable.
      }
    });
  }
}
