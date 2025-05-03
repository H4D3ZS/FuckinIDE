import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class PluginService {
  Future<void> loadPlugins(Function(Map<String, dynamic>) callback) async {
    final dir = await getApplicationSupportDirectory();
    final pluginFile = File('${dir.path}/plugins.json');
    if (await pluginFile.exists()) {
      final content = await pluginFile.readAsString();
      callback(jsonDecode(content));
    }
  }

  Future<void> installPlugin(
      String pluginPath, Function(String) callback) async {
    final file = File(pluginPath);
    final content = jsonDecode(await file.readAsString());
    Map<String, dynamic> plugins = {};
    plugins[content['id']] = content;
    final dir = await getApplicationSupportDirectory();
    await File('${dir.path}/plugins.json').writeAsString(jsonEncode(plugins));
    callback('\x1b[32mInstalled plugin: ${content['name']}\x1b[0m\n');
  }
}
