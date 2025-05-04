import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../models/editor_tab.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/highlight.dart' show Mode;

// Define EasyBF language mode (same as in ide_home_page.dart)
final Mode easybf = Mode(
  ref: 'easybf',
  aliases: ['easybf', 'eb'],
  contains: [
    Mode(
      className: 'keyword',
      begin:
          r'\+(CLASS|METHOD|VAR|OBJ|LOOP|-END)|CALL|SET|OUT|OUTVAR|func|if|while|writeFile|readFile|sendRequest|runCommand|print',
      relevance: 10,
    ),
    Mode(
      className: 'variable',
      begin: r'(?<=[\s\(])\w+(?=\.|[\s\)]|$)',
      relevance: 0,
    ),
    Mode(
      className: 'number',
      begin: r'\b\d+\b',
      relevance: 0,
    ),
    Mode(
      className: 'string',
      begin: r'"[^"]*"',
      relevance: 0,
    ),
    Mode(
      className: 'comment',
      begin: r'#',
      end: r'$',
      relevance: 0,
    ),
  ],
);

class ProjectService {
  void openNewTab(Function(String?, CodeController?) callback,
      {String? path, String? content}) {
    final controller = CodeController(
      text: content ?? '',
      language: easybf, // Use EasyBF language mode
    );
    callback(path, controller);
  }

  Future<void> openFile(Function(String?, CodeController?) callback) async {
    final result = await FilePicker.platform
        .pickFiles(allowedExtensions: ['easybf', 'bf'], allowMultiple: false);
    if (result != null) {
      final file = File(result.files.single.path!);
      final content = await file.readAsString();
      callback(file.path, CodeController(text: content, language: easybf));
    }
  }

  Future<void> saveFile(List<EditorTab> tabs, int currentTabIndex,
      Function(String) callback) async {
    if (currentTabIndex < 0 || currentTabIndex >= tabs.length) {
      callback('\x1b[31mNo file selected\x1b[0m\n');
      return;
    }
    final editorTab = tabs[currentTabIndex];
    String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: 'Save EasyBF File',
      fileName: editorTab.path.isEmpty
          ? 'untitled.easybf'
          : editorTab.path.split('/').last,
      type: FileType.custom,
      allowedExtensions: ['easybf', 'bf'],
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
          'name: EasyBF Project\nversion: 1.0\nfiles:\n  - main.easybf');
      await File('$result/main.easybf').writeAsString(
          '+CLASS Hello\n  +METHOD init\n    print("Hello, World!")\n  -END\n-END\n+OBJ Hello hello\nCALL hello.init');
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
