import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'settings.dart';

class SettingsService extends ChangeNotifier {
  SettingsService() : _settings = Settings();

  Settings _settings;
  Settings get settings => _settings;

  static const _key = 'keepassy_settings';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      _settings = Settings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    }
    notifyListeners();
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_settings.toJson()));
    notifyListeners();
  }

  void update(void Function(Settings s) fn) {
    fn(_settings);
    save();
  }
}
