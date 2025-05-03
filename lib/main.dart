// lib/main.dart
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/highlight_core.dart' show highlight, Mode;
import 'package:process_run/shell.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:yaml/yaml.dart';
import 'package:xterm/xterm.dart' as xterm;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  highlight.registerLanguage('brainfuck', brainfuckMode);
  runApp(const BrainfuckIDE());
}

class BrainfuckIDE extends StatelessWidget {
  const BrainfuckIDE({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Brainfuck IDE',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
          primary: Colors.indigo,
          secondary: Colors.amber,
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontFamily: 'JetBrainsMono'),
          bodyMedium: TextStyle(fontFamily: 'JetBrainsMono'),
          labelLarge: TextStyle(fontFamily: 'JetBrainsMono'),
        ),
        scaffoldBackgroundColor: Colors.grey[900],
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.indigo,
          foregroundColor: Colors.white,
          elevation: 4,
        ),
      ),
      home: const IDEHomePage(),
    );
  }
}

class IDEHomePage extends StatefulWidget {
  const IDEHomePage({super.key});

  @override
  State<IDEHomePage> createState() => _IDEHomePageState();
}

class _IDEHomePageState extends State<IDEHomePage> {
  final shell = Shell();
  final List<EditorTab> tabs = [];
  int currentTabIndex = -1;
  String projectPath = '';
  String output = '';
  Map<String, dynamic> plugins = {};
  bool isDebugging = false;
  Set<int> breakpoints = {};
  List<int> memory = List.filled(30000, 0);
  int pointer = 0;
  int instructionPointer = 0;
  List<int> loopStack = [];
  String debugInput = '';
  bool isLightTheme = false;
  final terminalController = xterm.Terminal();
  Map<String, dynamic> settings = {'fontSize': 14.0, 'keybindings': {}};
  bool isDragging = false;
  String? gccPath;
  double terminalHeight = 200;
  final FocusNode _editorFocusNode = FocusNode();
  final TextEditingController _terminalInputController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    try {
      loadSettings();
      loadPlugins();
      openNewTab();
      terminalController.write('\x1b[32mBrainfuck IDE Terminal\x1b[0m\n');
      setupGcc();
      terminalController.onInput = (input) {
        terminalController.write('\r\n\x1b[33m> \x1b[0m$input\r\n');
        _terminalInputController.text = '';
        processTerminalCommand(input);
      };
    } catch (e) {
      print('Init error: $e');
      terminalController.write('\x1b[31mInit error: $e\x1b[0m\n');
    }
  }

  Future<void> setupGcc() async {
    try {
      final result = await shell.run('which gcc');
      if (result.first.exitCode == 0 && result.outText.isNotEmpty) {
        setState(() {
          gccPath = result.outText.trim();
          output = 'GCC compiler initialized';
          terminalController.write('\x1b[32mGCC compiler initialized\x1b[0m\n');
        });
      } else {
        throw Exception(
            'GCC not found. Install via Xcode Command Line Tools or Homebrew.');
      }
    } catch (e) {
      setState(() {
        output = '\x1b[31mFailed to initialize GCC: $e\x1b[0m';
        terminalController
            .write('\x1b[31mFailed to initialize GCC: $e\x1b[0m\n');
      });
    }
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      isLightTheme = prefs.getBool('theme') ?? false;
      settings['fontSize'] = prefs.getDouble('fontSize') ?? 14.0;
      settings['keybindings'] =
          jsonDecode(prefs.getString('keybindings') ?? '{}');
    });
  }

  Future<void> saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('theme', isLightTheme);
    await prefs.setDouble('fontSize', settings['fontSize']);
    await prefs.setString('keybindings', jsonEncode(settings['keybindings']));
  }

  Future<void> loadPlugins() async {
    final dir = await getApplicationSupportDirectory();
    final pluginFile = File('${dir.path}/plugins.json');
    if (await pluginFile.exists()) {
      final content = await pluginFile.readAsString();
      setState(() {
        plugins = jsonDecode(content);
      });
    }
  }

  Future<void> installPlugin(String pluginPath) async {
    final file = File(pluginPath);
    final content = jsonDecode(await file.readAsString());
    setState(() {
      plugins[content['id']] = content;
    });
    final dir = await getApplicationSupportDirectory();
    await File('${dir.path}/plugins.json').writeAsString(jsonEncode(plugins));
    setState(() {
      output = '\x1b[32mInstalled plugin: ${content['name']}\x1b[0m';
      terminalController
          .write('\x1b[32mInstalled plugin: ${content['name']}\x1b[0m\n');
    });
  }

  void openNewTab({String? path, String? content}) {
    final controller = CodeController(
      text:
          content ?? 'class HelloWorld { init() { print("Hello, World!"); } }',
      language: brainfuckMode,
    );
    setState(() {
      tabs.add(EditorTab(
          path: path ?? '', controller: controller, isSaved: path == null));
      currentTabIndex = tabs.length - 1;
      _editorFocusNode.requestFocus();
    });
  }

  Future<void> openFile() async {
    final result = await FilePicker.platform
        .pickFiles(allowedExtensions: ['bf'], allowMultiple: false);
    if (result != null) {
      final file = File(result.files.single.path!);
      final content = await file.readAsString();
      openNewTab(path: file.path, content: content);
    }
  }

  Future<void> saveFile() async {
    if (currentTabIndex == -1) return;
    final tab = tabs[currentTabIndex];
    if (tab.path.isEmpty) {
      final result = await FilePicker.platform
          .saveFile(fileName: 'program.bf', allowedExtensions: ['bf']);
      if (result != null)
        tab.path = result;
      else
        return;
    }
    await File(tab.path)
        .writeAsString(compileOOPtoBrainfuck(tab.controller.text));
    setState(() {
      tab.isSaved = true;
      output = '\x1b[32mSaved to ${tab.path}\x1b[0m';
      terminalController.write('\x1b[32mSaved to ${tab.path}\x1b[0m\n');
    });
  }

  Future<void> createProject() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      final dir = Directory(result);
      await dir.create(recursive: true);
      final projectFile = File('$result/brainfuck.yaml');
      await projectFile.writeAsString(
          'name: Brainfuck Project\nversion: 1.0\nfiles:\n  - main.bf');
      await File('$result/main.bf').writeAsString(
          'class HelloWorld { init() { print("Hello, World!"); } }');
      setState(() {
        projectPath = result;
        output = '\x1b[32mCreated project: $projectPath\x1b[0m';
        terminalController
            .write('\x1b[32mCreated project: $projectPath\x1b[0m\n');
        openNewTab(
            path: '$result/main.bf',
            content: 'class HelloWorld { init() { print("Hello, World!"); } }');
      });
    }
  }

  String compileOOPtoBrainfuck(String code) {
    // Simple OOP preprocessor for Brainfuck
    final lines = code.split('\n');
    StringBuffer bfCode = StringBuffer();
    int memoryOffset = 0;

    for (String line in lines) {
      line = line.trim();
      if (line.startsWith('class')) {
        bfCode.write('>'); // Move to next memory cell for class instance
        memoryOffset++;
      } else if (line.contains('init()')) {
        bfCode.write('[-]'); // Clear current cell for object init
        memoryOffset++;
      } else if (line.contains('print(')) {
        String text =
            line.substring(line.indexOf('"') + 1, line.lastIndexOf('"'));
        for (int char in text.codeUnits) {
          bfCode.write('+'.padLeft(char, '+') + '.>'); // Set and print char
          memoryOffset++;
        }
      }
    }
    return bfCode.toString();
  }

  Future<String> compileBrainfuckToC(String bfCode, String outputCPath) async {
    final cCode = StringBuffer();
    cCode.write(
        '#include <stdio.h>\nint main() {\n    char array[30000] = {0};\n    char *ptr = array;\n');
    int indent = 1;
    int i = 0;
    while (i < bfCode.length) {
      final char = bfCode[i];
      if (char == '+' || char == '-') {
        int count = 1;
        while (i + 1 < bfCode.length && bfCode[i + 1] == char) {
          count += char == '+' ? 1 : -1;
          i++;
        }
        cCode.write(' ' * indent * 4 + '*ptr += $count;\n');
      } else if (char == '>' || char == '<') {
        int count = 1;
        while (i + 1 < bfCode.length && bfCode[i + 1] == char) {
          count += char == '>' ? 1 : -1;
          i++;
        }
        cCode.write(' ' * indent * 4 + 'ptr += $count;\n');
      } else {
        switch (char) {
          case '.':
            cCode.write(' ' * indent * 4 + 'putchar(*ptr);\n');
            break;
          case ',':
            cCode.write(' ' * indent * 4 + '*ptr = getchar();\n');
            break;
          case '[':
            cCode.write(' ' * indent * 4 + 'while (*ptr) {\n');
            indent++;
            break;
          case ']':
            indent--;
            cCode.write(' ' * indent * 4 + '}\n');
            break;
        }
      }
      i++;
    }
    cCode.write('    return 0;\n}');
    await File(outputCPath).writeAsString(cCode.toString());
    return outputCPath;
  }

  Future<void> compileToNative(String cPath, String outputPath) async {
    if (gccPath == null) {
      setState(() {
        output = '\x1b[31mGCC compiler not initialized\x1b[0m';
        terminalController
            .write('\x1b[31mGCC compiler not initialized\x1b[0m\n');
      });
      return;
    }
    final args = [cPath, '-o', outputPath];
    try {
      final tempDir = await getTemporaryDirectory();
      final outputFile = File(outputPath);
      if (await outputFile.exists()) await outputFile.delete();
      final result =
          await shell.run('$gccPath ${args.join(' ')}', runInShell: true);
      if (result.first.exitCode != 0)
        throw Exception('GCC compilation failed: ${result.errText}');
      await outputFile.setExecutable(true);
      setState(() {
        output =
            '\x1b[32mCompilation successful: $outputPath\x1b[0m\n${result.outText}';
        terminalController.write(
            '\x1b[32mCompilation successful: $outputPath\x1b[0m\n${result.outText}');
      });
    } catch (e) {
      setState(() {
        output = '\x1b[31mCompilation failed: $e\x1b[0m';
        terminalController.write('\x1b[31mCompilation failed: $e\x1b[0m\n');
      });
    }
  }

  Future<void> runCode() async {
    if (currentTabIndex == -1) return;
    final tempDir = await getTemporaryDirectory();
    final cPath = '${tempDir.path}/temp.c';
    final exePath = '${tempDir.path}/temp';
    await compileBrainfuckToC(
        compileOOPtoBrainfuck(tabs[currentTabIndex].controller.text), cPath);
    await compileToNative(cPath, exePath);
    if (!File(exePath).existsSync()) {
      setState(() {
        output = '\x1b[31mExecutable not found: $exePath\x1b[0m';
        terminalController
            .write('\x1b[31mExecutable not found: $exePath\x1b[0m\n');
      });
      return;
    }
    try {
      final result = await shell.run(exePath);
      setState(() {
        output = result.outText;
        terminalController.write(result.outText);
      });
    } catch (e) {
      setState(() {
        output = '\x1b[31mExecution failed: $e\x1b[0m';
        terminalController.write('\x1b[31mExecution failed: $e\x1b[0m\n');
      });
    }
  }

  void startDebugging() {
    if (currentTabIndex == -1) return;
    setState(() {
      isDebugging = true;
      memory = List.filled(30000, 0);
      pointer = 0;
      instructionPointer = 0;
      loopStack = [];
      debugInput = '';
      output = '\x1b[32mDebugging started\x1b[0m';
      terminalController.write('\x1b[32mDebugging started\x1b[0m\n');
    });
  }

  void stepDebug() {
    if (!isDebugging || currentTabIndex == -1) return;
    final code = compileOOPtoBrainfuck(tabs[currentTabIndex].controller.text);
    if (instructionPointer >= code.length) {
      setState(() {
        isDebugging = false;
        output = '\x1b[32mDebugging finished\x1b[0m';
        terminalController.write('\x1b[32mDebugging finished\x1b[0m\n');
      });
      return;
    }
    if (breakpoints.contains(instructionPointer)) {
      setState(() {
        output =
            '\x1b[33mHit breakpoint at instruction $instructionPointer\x1b[0m';
        terminalController.write(
            '\x1b[33mHit breakpoint at instruction $instructionPointer\x1b[0m\n');
      });
      return;
    }
    final char = code[instructionPointer];
    switch (char) {
      case '>':
        pointer++;
        break;
      case '<':
        pointer--;
        break;
      case '+':
        memory[pointer]++;
        break;
      case '-':
        memory[pointer]--;
        break;
      case '.':
        output += String.fromCharCode(memory[pointer]);
        terminalController.write(String.fromCharCode(memory[pointer]));
        break;
      case ',':
        if (debugInput.isEmpty) {
          setState(() {
            output = '\x1b[33mWaiting for input\x1b[0m';
            terminalController.write('\x1b[33mWaiting for input\x1b[0m\n');
          });
          return;
        }
        memory[pointer] = debugInput.codeUnitAt(0);
        debugInput = debugInput.substring(1);
        break;
      case '[':
        loopStack.add(instructionPointer);
        if (memory[pointer] == 0) {
          int depth = 1;
          while (depth > 0 && instructionPointer < code.length - 1) {
            instructionPointer++;
            if (code[instructionPointer] == '[') depth++;
            if (code[instructionPointer] == ']') depth--;
          }
        }
        break;
      case ']':
        if (memory[pointer] != 0)
          instructionPointer = loopStack.last;
        else
          loopStack.removeLast();
        break;
    }
    instructionPointer++;
    setState(() {
      output =
          '\x1b[36mStepped: ptr=$pointer, mem[$pointer]=${memory[pointer]}\x1b[0m';
      terminalController.write(
          '\x1b[36mStepped: ptr=$pointer, mem[$pointer]=${memory[pointer]}\x1b[0m\n');
    });
  }

  void processTerminalCommand(String command) {
    if (command == 'clear') {
      terminalController.clear();
      terminalController.write('\x1b[32mBrainfuck IDE Terminal\x1b[0m\n');
    } else if (command == 'help') {
      terminalController.write(
          '\x1b[33mAvailable commands:\n- clear: Clear terminal\n- help: Show this message\x1b[0m\n');
    } else {
      terminalController.write('\x1b[31mUnknown command: $command\x1b[0m\n');
    }
  }

  Future<void> gitCommit() async {
    if (projectPath.isEmpty) {
      setState(() {
        output = '\x1b[31mNo project opened\x1b[0m';
        terminalController.write('\x1b[31mNo project opened\x1b[0m\n');
      });
      return;
    }
    try {
      final shell = Shell(workingDirectory: projectPath);
      await shell.run('git add .');
      await shell.run('git commit -m "Auto-commit from IDE"');
      setState(() {
        output = '\x1b[32mCommitted changes\x1b[0m';
        terminalController.write('\x1b[32mCommitted changes\x1b[0m\n');
      });
    } catch (e) {
      setState(() {
        output = '\x1b[31mGit commit failed: $e\x1b[0m';
        terminalController.write('\x1b[31mGit commit failed: $e\x1b[0m\n');
      });
    }
  }

  Future<void> gitPush() async {
    if (projectPath.isEmpty) return;
    try {
      final shell = Shell(workingDirectory: projectPath);
      await shell.run('git push origin main');
      setState(() {
        output = '\x1b[32mPushed to remote\x1b[0m';
        terminalController.write('\x1b[32mPushed to remote\x1b[0m\n');
      });
    } catch (e) {
      setState(() {
        output = '\x1b[31mGit push failed: $e\x1b[0m';
        terminalController.write('\x1b[31mGit push failed: $e\x1b[0m\n');
      });
    }
  }

  Future<void> gitPull() async {
    if (projectPath.isEmpty) return;
    try {
      final shell = Shell(workingDirectory: projectPath);
      await shell.run('git pull origin main');
      setState(() {
        output = '\x1b[32mPulled from remote\x1b[0m';
        terminalController.write('\x1b[32mPulled from remote\x1b[0m\n');
      });
    } catch (e) {
      setState(() {
        output = '\x1b[31mGit pull failed: $e\x1b[0m';
        terminalController.write('\x1b[31mGit pull failed: $e\x1b[0m\n');
      });
    }
  }

  Future<void> openProject() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      setState(() {
        projectPath = result;
        output = '\x1b[32mOpened project: $projectPath\x1b[0m';
        terminalController
            .write('\x1b[32mOpened project: $projectPath\x1b[0m\n');
      });
    }
  }

  void lintCode(String code) {
    int depth = 0;
    for (var char in code.runes) {
      if (char == '['.codeUnitAt(0)) depth++;
      if (char == ']'.codeUnitAt(0)) depth--;
      if (depth < 0) {
        setState(() {
          output = '\x1b[31mLint error: Unmatched ]\x1b[0m';
          terminalController.write('\x1b[31mLint error: Unmatched ]\x1b[0m\n');
        });
        return;
      }
    }
    if (depth != 0) {
      setState(() {
        output = '\x1b[31mLint error: Unmatched [\x1b[0m';
        terminalController.write('\x1b[31mLint error: Unmatched [\x1b[0m\n');
      });
    } else {
      setState(() {
        output = '\x1b[32mLint: No errors\x1b[0m';
        terminalController.write('\x1b[32mLint: No errors\x1b[0m\n');
      });
    }
  }

  int getCurrentLine(CodeController controller) {
    final text = controller.text;
    final offset = controller.selection.baseOffset;
    int line = 1;
    for (int i = 0; i < offset && i < text.length; i++) {
      if (text[i] == '\n') line++;
    }
    return line;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: isLightTheme
          ? ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.indigo,
                brightness: Brightness.light,
                primary: Colors.indigo,
                secondary: Colors.amber,
              ),
              textTheme: const TextTheme(
                bodyLarge: TextStyle(fontFamily: 'JetBrainsMono'),
                bodyMedium: TextStyle(fontFamily: 'JetBrainsMono'),
                labelLarge: TextStyle(fontFamily: 'JetBrainsMono'),
              ),
              scaffoldBackgroundColor: Colors.grey[100],
              appBarTheme: const AppBarTheme(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                elevation: 4,
              ),
            )
          : Theme.of(context),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Brainfuck IDE'),
          actions: [
            IconButton(
              icon: Icon(isLightTheme ? Icons.dark_mode : Icons.light_mode),
              onPressed: () {
                setState(() {
                  isLightTheme = !isLightTheme;
                  saveSettings();
                });
              },
              tooltip: isLightTheme ? 'Dark Theme' : 'Light Theme',
            ),
          ],
        ),
        body: DropTarget(
          onDragEntered: (_) => setState(() => isDragging = true),
          onDragExited: (_) => setState(() => isDragging = false),
          onDragDone: (details) {
            final file = File(details.files.first.path);
            if (file.path.endsWith('.bf')) {
              openNewTab(path: file.path, content: file.readAsStringSync());
            } else if (file.path.endsWith('.json')) {
              installPlugin(file.path);
            }
            setState(() => isDragging = false);
          },
          child: Container(
            color: isDragging ? Colors.indigo.withOpacity(0.2) : null,
            child: Column(
              children: [
                Material(
                  elevation: 4,
                  child: Container(
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        TextButton(
                            onPressed: createProject,
                            child: const Text('New Project')),
                        TextButton(
                            onPressed: openProject,
                            child: const Text('Open Project')),
                        TextButton(
                            onPressed: saveFile, child: const Text('Save')),
                        TextButton(
                            onPressed: runCode, child: const Text('Run')),
                        TextButton(
                            onPressed: startDebugging,
                            child: const Text('Debug')),
                        TextButton(
                            onPressed: gitCommit, child: const Text('Commit')),
                        TextButton(
                            onPressed: gitPush, child: const Text('Push')),
                        TextButton(
                            onPressed: gitPull, child: const Text('Pull')),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      Material(
                        elevation: 8,
                        child: Container(
                          width: 60,
                          color: Theme.of(context).colorScheme.surfaceVariant,
                          child: Column(
                            children: [
                              IconButton(
                                  icon: const Icon(Icons.folder_open),
                                  onPressed: openProject,
                                  tooltip: 'Open Project',
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                  hoverColor: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withOpacity(0.2)),
                              IconButton(
                                  icon: const Icon(Icons.save),
                                  onPressed: saveFile,
                                  tooltip: 'Save',
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                  hoverColor: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withOpacity(0.2)),
                              IconButton(
                                  icon: const Icon(Icons.play_arrow),
                                  onPressed: runCode,
                                  tooltip: 'Run',
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                  hoverColor: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withOpacity(0.2)),
                              IconButton(
                                  icon: const Icon(Icons.bug_report),
                                  onPressed: startDebugging,
                                  tooltip: 'Debug',
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                  hoverColor: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withOpacity(0.2)),
                              IconButton(
                                  icon: const Icon(Icons.commit),
                                  onPressed: gitCommit,
                                  tooltip: 'Git Commit',
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                  hoverColor: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withOpacity(0.2)),
                            ],
                          ),
                        ),
                      ),
                      Material(
                        elevation: 4,
                        child: Container(
                          width: 200,
                          color: Theme.of(context).colorScheme.surface,
                          child: projectPath.isEmpty
                              ? const Center(
                                  child: Text('No project opened',
                                      style: TextStyle(color: Colors.white70)))
                              : FileExplorer(
                                  path: projectPath,
                                  onFileSelected: (path) {
                                    openNewTab(
                                        path: path,
                                        content: File(path).readAsStringSync());
                                  }),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            if (tabs.isNotEmpty)
                              Material(
                                elevation: 2,
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: List.generate(
                                        tabs.length,
                                        (index) => Container(
                                              decoration: BoxDecoration(
                                                color: index == currentTabIndex
                                                    ? Theme.of(context)
                                                        .colorScheme
                                                        .primaryContainer
                                                    : Theme.of(context)
                                                        .colorScheme
                                                        .surface,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              margin:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 4,
                                                      vertical: 2),
                                              child: TabButton(
                                                title: tabs[index].path.isEmpty
                                                    ? 'Untitled'
                                                    : tabs[index]
                                                        .path
                                                        .split('/')
                                                        .last,
                                                isActive:
                                                    index == currentTabIndex,
                                                isSaved: tabs[index].isSaved,
                                                onTap: () {
                                                  setState(() {
                                                    currentTabIndex = index;
                                                    lintCode(
                                                        tabs[currentTabIndex]
                                                            .controller
                                                            .text);
                                                    _editorFocusNode
                                                        .requestFocus();
                                                  });
                                                },
                                                onClose: () {
                                                  setState(() {
                                                    tabs.removeAt(index);
                                                    if (currentTabIndex >=
                                                        tabs.length)
                                                      currentTabIndex =
                                                          tabs.length - 1;
                                                  });
                                                },
                                              ),
                                            )),
                                  ),
                                ),
                              ),
                            Expanded(
                              child: currentTabIndex == -1
                                  ? const Center(child: Text('No file opened'))
                                  : Focus(
                                      focusNode: _editorFocusNode,
                                      child: CodeField(
                                        controller:
                                            tabs[currentTabIndex].controller,
                                        gutterStyle: const GutterStyle(),
                                        textStyle: TextStyle(
                                            fontSize: settings['fontSize'],
                                            color: Colors.white),
                                        background: Colors.grey[900],
                                        minLines: null,
                                        maxLines: null,
                                        expands: true,
                                        readOnly: false,
                                        onChanged: (value) {
                                          print('Text changed: $value');
                                          lintCode(value);
                                        },
                                      ),
                                    ),
                            ),
                            Container(
                              height: terminalHeight,
                              decoration: BoxDecoration(
                                border: Border(
                                    top: BorderSide(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        width: 1)),
                              ),
                              child: Column(
                                children: [
                                  Expanded(
                                    child: xterm.TerminalView(
                                      terminalController,
                                      theme: isLightTheme
                                          ? lightTerminalTheme
                                          : darkTerminalTheme,
                                      // maxLines: 1000,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.all(4),
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceVariant,
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller:
                                                _terminalInputController,
                                            decoration: InputDecoration(
                                              hintText: 'Enter command...',
                                              border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(4)),
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8),
                                            ),
                                            onSubmitted: (value) {
                                              terminalController.write(
                                                  '\r\n\x1b[33m> \x1b[0m$value\r\n');
                                              processTerminalCommand(value);
                                              _terminalInputController.clear();
                                            },
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.send),
                                          onPressed: () {
                                            terminalController.write(
                                                '\r\n\x1b[33m> \x1b[0m${_terminalInputController.text}\r\n');
                                            processTerminalCommand(
                                                _terminalInputController.text);
                                            _terminalInputController.clear();
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Material(
                  elevation: 2,
                  child: Container(
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        Text(currentTabIndex == -1
                            ? ''
                            : 'Line ${getCurrentLine(tabs[currentTabIndex].controller)}'),
                        const Spacer(),
                        Text(projectPath.isEmpty ? 'No project' : projectPath),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class EditorTab {
  String path;
  CodeController controller;
  bool isSaved;

  EditorTab(
      {required this.path, required this.controller, required this.isSaved});
}

class FileExplorer extends StatelessWidget {
  final String path;
  final Function(String) onFileSelected;

  const FileExplorer(
      {super.key, required this.path, required this.onFileSelected});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<FileSystemEntity>>(
      future: Directory(path)
          .list(recursive: false)
          .where((f) => f.path.endsWith('.bf'))
          .toList(),
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final files = snapshot.data!;
        return ListView.builder(
          itemCount: files.length,
          itemBuilder: (context, index) => ListTile(
            title: Text(files[index].path.split('/').last,
                style: Theme.of(context).textTheme.bodyMedium),
            onTap: () => onFileSelected(files[index].path),
            hoverColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
          ),
        );
      },
    );
  }
}

class TabButton extends StatelessWidget {
  final String title;
  final bool isActive;
  final bool isSaved;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const TabButton(
      {super.key,
      required this.title,
      required this.isActive,
      required this.isSaved,
      required this.onTap,
      required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        children: [
          GestureDetector(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(isSaved ? title : '$title *',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: isActive
                            ? Theme.of(context).colorScheme.onPrimaryContainer
                            : Theme.of(context).colorScheme.onSurface,
                      )),
            ),
          ),
          IconButton(
              icon: const Icon(Icons.close, size: 16),
              onPressed: onClose,
              color: Theme.of(context).colorScheme.onSurface,
              hoverColor: Theme.of(context).colorScheme.error.withOpacity(0.2)),
        ],
      ),
    );
  }
}

final brainfuckMode = Mode(
  contains: [
    Mode(className: 'keyword', begin: r'[+\-<>[\].,]'),
    Mode(className: 'comment', begin: r'[^+\-<>[\].,]'),
    Mode(className: 'class', begin: r'class\s+\w+'),
    Mode(className: 'method', begin: r'\w+\(\)'),
  ],
);

const monokaiTheme = {
  'keyword': TextStyle(color: Colors.purple),
  'comment': TextStyle(color: Colors.grey),
  'class': TextStyle(color: Colors.blue),
  'method': TextStyle(color: Colors.green),
  'root': TextStyle(backgroundColor: Colors.grey, color: Colors.white),
};

const Color magenta = Color(0xFFFF00FF);

final lightTerminalTheme = xterm.TerminalTheme(
  foreground: Colors.black,
  background: Colors.white,
  cursor: Colors.black,
  selection: Colors.grey.withOpacity(0.3),
  black: Colors.black,
  red: Colors.red,
  green: Colors.green,
  yellow: Colors.yellow,
  blue: Colors.blue,
  magenta: magenta,
  cyan: Colors.cyan,
  white: Colors.white,
  brightBlack: Colors.grey,
  brightRed: Colors.redAccent,
  brightGreen: Colors.greenAccent,
  brightYellow: Colors.yellowAccent,
  brightBlue: Colors.blueAccent,
  brightMagenta: Colors.pinkAccent,
  brightCyan: Colors.cyanAccent,
  brightWhite: Colors.white70,
  searchHitBackground: Colors.yellow.withOpacity(0.4),
  searchHitBackgroundCurrent: Colors.yellow.withOpacity(0.7),
  searchHitForeground: Colors.black,
);

final darkTerminalTheme = xterm.TerminalTheme(
  foreground: Colors.white,
  background: Colors.black,
  cursor: Colors.white,
  selection: Colors.white.withOpacity(0.3),
  black: Colors.black,
  red: Colors.red,
  green: Colors.green,
  yellow: Colors.yellow,
  blue: Colors.blue,
  magenta: magenta,
  cyan: Colors.cyan,
  white: Colors.white,
  brightBlack: Colors.grey,
  brightRed: Colors.redAccent,
  brightGreen: Colors.greenAccent,
  brightYellow: Colors.yellowAccent,
  brightBlue: Colors.blueAccent,
  brightMagenta: Colors.pinkAccent,
  brightCyan: Colors.cyanAccent,
  brightWhite: Colors.white70,
  searchHitBackground: Colors.yellow.withOpacity(0.4),
  searchHitBackgroundCurrent: Colors.yellow.withOpacity(0.7),
  searchHitForeground: Colors.black,
);

class BreakpointPainter extends CustomPainter {
  final Set<int> breakpoints;
  final double lineHeight;
  final CodeController controller;

  BreakpointPainter(
      {required this.breakpoints,
      required this.lineHeight,
      required this.controller});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;
    for (var line in breakpoints) {
      final y = (line - 1) * lineHeight;
      canvas.drawCircle(Offset(5, y + lineHeight / 2), 4, paint);
    }
  }

  @override
  bool shouldRepaint(BreakpointPainter oldDelegate) =>
      breakpoints != oldDelegate.breakpoints ||
      lineHeight != oldDelegate.lineHeight;
}

extension FileExtension on File {
  Future<void> setExecutable(bool executable) async {
    final path = this.path;
    try {
      await Process.run('chmod', [executable ? '+x' : '-x', path]);
    } catch (e) {
      print('Failed to set executable: $e');
    }
  }
}
