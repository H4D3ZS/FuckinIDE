import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  Future<void> loadSettings(
      Function(bool, Map<String, dynamic>) callback) async {
    final prefs = await SharedPreferences.getInstance();
    final isLightTheme = prefs.getBool('theme') ?? false;
    final settings = {
      'fontSize': prefs.getDouble('fontSize') ?? 14.0,
      'keybindings': jsonDecode(prefs.getString('keybindings') ?? '{}'),
    };
    callback(isLightTheme, settings);
  }

  Future<void> saveSettings(
      bool isLightTheme, Map<String, dynamic> settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('theme', isLightTheme);
    await prefs.setDouble('fontSize', settings['fontSize']);
    await prefs.setString('keybindings', jsonEncode(settings['keybindings']));
  }
}
