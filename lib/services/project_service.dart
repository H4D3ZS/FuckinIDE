import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../models/editor_tab.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import '../utils/highlight_modes.dart';

class ProjectService {
  void openNewTab(Function(String?, CodeController?) callback,
      {String? path, String? content}) {
    final controller = CodeController(
      text: content ?? '',
      language: brainfuckMode,
    );
    callback(path, controller);
  }

  Future<void> openFile(Function(String?, CodeController?) callback) async {
    final result = await FilePicker.platform
        .pickFiles(allowedExtensions: ['bf'], allowMultiple: false);
    if (result != null) {
      final file = File(result.files.single.path!);
      final content = await file.readAsString();
      callback(
          file.path, CodeController(text: content, language: brainfuckMode));
    }
  }

  Future<void> saveFile(List<EditorTab> tabs, int currentTabIndex,
      Function(String) callback, Function(String) compileOOPtoBrainfuck) async {
    if (currentTabIndex < 0 || currentTabIndex >= tabs.length) {
      callback('\x1b[31mNo file selected\x1b[0m\n');
      return;
    }
    final editorTab = tabs[currentTabIndex];
    String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Brainfuck File',
      fileName: editorTab.path.isEmpty
          ? 'untitled.bf'
          : editorTab.path.split('/').last,
      type: FileType.custom,
      allowedExtensions: ['bf'],
    );
    if (outputFile != null) {
      await File(outputFile).writeAsString(editorTab.controller.text);
      editorTab.path = outputFile;
      editorTab.isSaved = true;
      callback('\x1b[32mSaved to $outputFile\x1b[0m\n');
    }
  }

  Future<void> createProject(Function(String, String) callback) async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      final dir = Directory(result);
      await dir.create(recursive: true);
      final projectFile = File('$result/brainfuck.yaml');
      await projectFile.writeAsString(
          'name: Brainfuck Project\nversion: 1.0\nfiles:\n  - main.bf');
      await File('$result/main.bf').writeAsString('Brain Fuck Programming');
      callback(result, '\x1b[32mCreated project: $result\x1b[0m\n');
    }
  }

  Future<void> openProject(Function(String, String) callback) async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      callback(result, '\x1b[32mOpened project: $result\x1b[0m\n');
    }
  }
}
