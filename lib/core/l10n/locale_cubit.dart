import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../storage/user_preferences.dart';

class LocaleCubit extends Cubit<Locale> {
  LocaleCubit(this._prefs, {Locale initial = const Locale('en')}) : super(initial);

  final UserPreferences _prefs;

  void setLocale(Locale locale) {
    emit(locale);
    _prefs.saveLocale(locale);
  }
}
