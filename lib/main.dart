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
import 'package:flutter/services.dart' show rootBundle;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Register Brainfuck language for syntax highlighting
  highlight.registerLanguage('brainfuck', brainfuckMode);
  runApp(const BrainfuckIDE());
}

class BrainfuckIDE extends StatelessWidget {
  const BrainfuckIDE({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Brainfuck IDE',
      theme: ThemeData.dark(),
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
  Map<String, dynamic> settings = {};
  bool isDragging = false;
  String? tccPath;

  @override
  void initState() {
    super.initState();
    loadSettings();
    loadPlugins();
    openNewTab();
    terminalController.write('Brainfuck IDE Terminal\n');
    setupTCC();
  }

  // Setup TCC compiler
  Future<void> setupTCC() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final tccDir = Directory('${tempDir.path}/tcc');
      await tccDir.create(recursive: true);

      const tccAssetPath = 'assets/tcc/tcc_macos';
      const tccBinaryName = 'tcc';

      // Extract TCC binary
      final tccBytes = await rootBundle.load(tccAssetPath);
      final tccFile = File('${tccDir.path}/$tccBinaryName');
      await tccFile.writeAsBytes(tccBytes.buffer.asUint8List());
      await Process.run('chmod', ['+x', tccFile.path]);

      // Extract TCC include files
      const includeFiles = [
        'lib/include/stddef.h',
        'lib/include/stdarg.h',
        'lib/include/stdio.h'
      ];
      for (var file in includeFiles) {
        final bytes = await rootBundle.load('assets/tcc/$file');
        final outFile = File('${tccDir.path}/$file');
        await outFile.create(recursive: true);
        await outFile.writeAsBytes(bytes.buffer.asUint8List());
      }

      setState(() {
        tccPath = tccFile.path;
        output = 'TCC compiler initialized';
        terminalController.write('TCC compiler initialized\n');
      });
    } catch (e) {
      setState(() {
        output = 'Failed to initialize TCC: $e';
        terminalController.write('Failed to initialize TCC: $e\n');
      });
    }
  }

  // Load settings
  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      isLightTheme = prefs.getBool('theme') ?? false;
      settings = {
        'fontSize': prefs.getDouble('fontSize') ?? 14.0,
        'keybindings': jsonDecode(prefs.getString('keybindings') ?? '{}'),
      };
    });
  }

  // Save settings
  Future<void> saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('theme', isLightTheme);
    await prefs.setDouble('fontSize', settings['fontSize']);
    await prefs.setString('keybindings', jsonEncode(settings['keybindings']));
  }

  // Load plugins
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

  // Install plugin
  Future<void> installPlugin(String pluginPath) async {
    final file = File(pluginPath);
    final content = jsonDecode(await file.readAsString());
    setState(() {
      plugins[content['id']] = content;
    });
    final dir = await getApplicationSupportDirectory();
    await File('${dir.path}/plugins.json').writeAsString(jsonEncode(plugins));
    setState(() {
      output = 'Installed plugin: ${content['name']}';
      terminalController.write('Installed plugin: ${content['name']}\n');
    });
  }

  // Open new editor tab
  void openNewTab({String? path, String? content}) {
    final controller = CodeController(
      text: content ?? '++++++[>++++++<-]>.',
      language: brainfuckMode,
    );
    setState(() {
      tabs.add(EditorTab(
        path: path ?? '',
        controller: controller,
        isSaved: path == null,
      ));
      currentTabIndex = tabs.length - 1;
    });
  }

  // Open file
  Future<void> openFile() async {
    final result = await FilePicker.platform.pickFiles(
      allowedExtensions: ['bf'],
      allowMultiple: false,
    );
    if (result != null) {
      final file = File(result.files.single.path!);
      final content = await file.readAsString();
      openNewTab(path: file.path, content: content);
    }
  }

  // Save file
  Future<void> saveFile() async {
    if (currentTabIndex == -1) return;
    final tab = tabs[currentTabIndex];
    if (tab.path.isEmpty) {
      final result = await FilePicker.platform.saveFile(
        fileName: 'program.bf',
        allowedExtensions: ['bf'],
      );
      if (result != null) {
        tab.path = result;
      } else {
        return;
      }
    }
    await File(tab.path).writeAsString(tab.controller.text);
    setState(() {
      tab.isSaved = true;
      output = 'Saved to ${tab.path}';
      terminalController.write('Saved to ${tab.path}\n');
    });
  }

  // Create new project
  Future<void> createProject() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      final dir = Directory(result);
      await dir.create(recursive: true);
      final projectFile = File('$result/brainfuck.yaml');
      await projectFile.writeAsString('''
name: Brainfuck Project
version: 1.0
files:
  - main.bf
''');
      await File('$result/main.bf').writeAsString('++++++[>++++++<-]>.');
      setState(() {
        projectPath = result;
        output = 'Created project: $projectPath';
        terminalController.write('Created project: $projectPath\n');
        openNewTab(path: '$result/main.bf', content: '++++++[>++++++<-]>.');
      });
    }
  }

  // Brainfuck to C compiler with optimization
  Future<String> compileBrainfuckToC(String bfCode, String outputCPath) async {
    final cCode = StringBuffer();
    cCode.writeln('#include <stdio.h>');
    cCode.writeln('int main() {');
    cCode.writeln('    char array[30000] = {0};');
    cCode.writeln('    char *ptr = array;');

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
        cCode.writeln('    ' * indent + '*ptr += $count;');
      } else if (char == '>' || char == '<') {
        int count = 1;
        while (i + 1 < bfCode.length && bfCode[i + 1] == char) {
          count += char == '>' ? 1 : -1;
          i++;
        }
        cCode.writeln('    ' * indent + 'ptr += $count;');
      } else {
        switch (char) {
          case '.':
            cCode.writeln('    ' * indent + 'putchar(*ptr);');
            break;
          case ',':
            cCode.writeln('    ' * indent + '*ptr = getchar();');
            break;
          case '[':
            cCode.writeln('    ' * indent + 'while (*ptr) {');
            indent++;
            break;
          case ']':
            indent--;
            cCode.writeln('    ' * indent + '}');
            break;
        }
      }
      i++;
    }

    cCode.writeln('    return 0;');
    cCode.writeln('}');

    await File(outputCPath).writeAsString(cCode.toString());
    return outputCPath;
  }

  // Compile to native executable using TCC
  Future<void> compileToNative(String cPath, String outputPath) async {
    if (tccPath == null) {
      setState(() {
        output = 'TCC compiler not initialized';
        terminalController.write('TCC compiler not initialized\n');
      });
      return;
    }

    final tccDir = Directory(tccPath!).parent;
    final args = [
      '-I${tccDir.path}/lib/include',
      cPath,
      '-o',
      outputPath,
    ];

    try {
      final result = await shell.run('$tccPath ${args.join(' ')}');
      setState(() {
        output = 'Compilation successful: $outputPath\n${result.outText}';
        terminalController
            .write('Compilation successful: $outputPath\n${result.outText}');
      });
    } catch (e) {
      setState(() {
        output = 'Compilation failed: $e';
        terminalController.write('Compilation failed: $e\n');
      });
    }
  }

  // Run code
  Future<void> runCode() async {
    if (currentTabIndex == -1) return;
    final tempDir = await getTemporaryDirectory();
    final cPath = '${tempDir.path}/temp.c';
    final exePath = '${tempDir.path}/temp';

    await compileBrainfuckToC(tabs[currentTabIndex].controller.text, cPath);
    await compileToNative(cPath, exePath);

    try {
      final result = await shell.run('./$exePath');
      setState(() {
        output = result.outText;
        terminalController.write(result.outText);
      });
    } catch (e) {
      setState(() {
        output = 'Execution failed: $e';
        terminalController.write('Execution failed: $e\n');
      });
    }
  }

  // Debug code
  void startDebugging() {
    if (currentTabIndex == -1) return;
    setState(() {
      isDebugging = true;
      memory = List.filled(30000, 0);
      pointer = 0;
      instructionPointer = 0;
      loopStack = [];
      debugInput = '';
      output = 'Debugging started';
      terminalController.write('Debugging started\n');
    });
  }

  void stepDebug() {
    if (!isDebugging || currentTabIndex == -1) return;
    final code = tabs[currentTabIndex].controller.text;
    if (instructionPointer >= code.length) {
      setState(() {
        isDebugging = false;
        output = 'Debugging finished';
        terminalController.write('Debugging finished\n');
      });
      return;
    }

    if (breakpoints.contains(instructionPointer)) {
      setState(() {
        output = 'Hit breakpoint at instruction $instructionPointer';
        terminalController
            .write('Hit breakpoint at instruction $instructionPointer\n');
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
            output = 'Waiting for input';
            terminalController.write('Waiting for input\n');
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
        if (memory[pointer] != 0) {
          instructionPointer = loopStack.last;
        } else {
          loopStack.removeLast();
        }
        break;
    }
    instructionPointer++;
    setState(() {
      output = 'Stepped: ptr=$pointer, mem[$pointer]=${memory[pointer]}';
      terminalController
          .write('Stepped: ptr=$pointer, mem[$pointer]=${memory[pointer]}\n');
    });
  }

  // Git operations
  Future<void> gitCommit() async {
    if (projectPath.isEmpty) {
      setState(() {
        output = 'No project opened';
        terminalController.write('No project opened\n');
      });
      return;
    }
    try {
      final shell = Shell(workingDirectory: projectPath);
      await shell.run('git add .');
      await shell.run('git commit -m "Auto-commit from IDE"');
      setState(() {
        output = 'Committed changes';
        terminalController.write('Committed changes\n');
      });
    } catch (e) {
      setState(() {
        output = 'Git commit failed: $e';
        terminalController.write('Git commit failed: $e\n');
      });
    }
  }

  Future<void> gitPush() async {
    if (projectPath.isEmpty) return;
    try {
      final shell = Shell(workingDirectory: projectPath);
      await shell.run('git push origin main');
      setState(() {
        output = 'Pushed to remote';
        terminalController.write('Pushed to remote\n');
      });
    } catch (e) {
      setState(() {
        output = 'Git push failed: $e';
        terminalController.write('Git push failed: $e\n');
      });
    }
  }

  Future<void> gitPull() async {
    if (projectPath.isEmpty) return;
    try {
      final shell = Shell(workingDirectory: projectPath);
      await shell.run('git pull origin main');
      setState(() {
        output = 'Pulled from remote';
        terminalController.write('Pulled from remote\n');
      });
    } catch (e) {
      setState(() {
        output = 'Git pull failed: $e';
        terminalController.write('Git pull failed: $e\n');
      });
    }
  }

  // Open project
  Future<void> openProject() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      setState(() {
        projectPath = result;
        output = 'Opened project: $projectPath';
        terminalController.write('Opened project: $projectPath\n');
      });
    }
  }

  // Lint code
  void lintCode(String code) {
    int depth = 0;
    for (var char in code.runes) {
      if (char == '['.codeUnitAt(0)) depth++;
      if (char == ']'.codeUnitAt(0)) depth--;
      if (depth < 0) {
        setState(() {
          output = 'Lint error: Unmatched ]';
          terminalController.write('Lint error: Unmatched ]\n');
        });
        return;
      }
    }
    if (depth != 0) {
      setState(() {
        output = 'Lint error: Unmatched [';
        terminalController.write('Lint error: Unmatched [\n');
      });
    } else {
      setState(() {
        output = 'Lint: No errors';
        terminalController.write('Lint: No errors\n');
      });
    }
  }

  // Get current line number from controller
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
      theme: isLightTheme ? ThemeData.light() : ThemeData.dark(),
      home: Scaffold(
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
            color: isDragging ? Colors.blue.withOpacity(0.2) : null,
            child: Column(
              children: [
                // Top Menu
                Row(
                  children: [
                    TextButton(
                      onPressed: createProject,
                      child: const Text('New Project'),
                    ),
                    TextButton(
                      onPressed: openProject,
                      child: const Text('Open Project'),
                    ),
                    TextButton(
                      onPressed: saveFile,
                      child: const Text('Save'),
                    ),
                    TextButton(
                      onPressed: runCode,
                      child: const Text('Run'),
                    ),
                    TextButton(
                      onPressed: startDebugging,
                      child: const Text('Debug'),
                    ),
                    TextButton(
                      onPressed: gitCommit,
                      child: const Text('Commit'),
                    ),
                    TextButton(
                      onPressed: gitPush,
                      child: const Text('Push'),
                    ),
                    TextButton(
                      onPressed: gitPull,
                      child: const Text('Pull'),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          isLightTheme = !isLightTheme;
                          saveSettings();
                        });
                      },
                      child: Text(isLightTheme ? 'Dark Theme' : 'Light Theme'),
                    ),
                  ],
                ),
                Expanded(
                  child: Row(
                    children: [
                      // Sidebar
                      Container(
                        width: 60,
                        color: Colors.grey[900],
                        child: Column(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.folder_open),
                              onPressed: openProject,
                              tooltip: 'Open Project',
                            ),
                            IconButton(
                              icon: const Icon(Icons.save),
                              onPressed: saveFile,
                              tooltip: 'Save',
                            ),
                            IconButton(
                              icon: const Icon(Icons.play_arrow),
                              onPressed: runCode,
                              tooltip: 'Run',
                            ),
                            IconButton(
                              icon: const Icon(Icons.bug_report),
                              onPressed: startDebugging,
                              tooltip: 'Debug',
                            ),
                            IconButton(
                              icon: const Icon(Icons.commit),
                              onPressed: gitCommit,
                              tooltip: 'Git Commit',
                            ),
                          ],
                        ),
                      ),
                      // Project Explorer
                      Container(
                        width: 200,
                        color: Colors.grey[850],
                        child: projectPath.isEmpty
                            ? const Center(child: Text('No project opened'))
                            : FileExplorer(
                                path: projectPath,
                                onFileSelected: (path) {
                                  openNewTab(
                                      path: path,
                                      content: File(path).readAsStringSync());
                                },
                              ),
                      ),
                      // Main Editor Area
                      Expanded(
                        child: Column(
                          children: [
                            // Tabs
                            if (tabs.isNotEmpty)
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: List.generate(tabs.length, (index) {
                                    return TabButton(
                                      title: tabs[index].path.isEmpty
                                          ? 'Untitled'
                                          : tabs[index].path.split('/').last,
                                      isActive: index == currentTabIndex,
                                      isSaved: tabs[index].isSaved,
                                      onTap: () {
                                        setState(() {
                                          currentTabIndex = index;
                                          lintCode(tabs[currentTabIndex]
                                              .controller
                                              .text);
                                        });
                                      },
                                      onClose: () {
                                        setState(() {
                                          tabs.removeAt(index);
                                          if (currentTabIndex >= tabs.length) {
                                            currentTabIndex = tabs.length - 1;
                                          }
                                        });
                                      },
                                    );
                                  }),
                                ),
                              ),
                            // Editor with Breakpoint Indicators
                            Expanded(
                              child: currentTabIndex == -1
                                  ? const Center(child: Text('No file opened'))
                                  : Stack(
                                      children: [
                                        CodeTheme(
                                          data: CodeThemeData(
                                              styles: monokaiTheme),
                                          child: CodeField(
                                            controller: tabs[currentTabIndex]
                                                .controller,
                                            gutterStyle: const GutterStyle(),
                                            textStyle: TextStyle(
                                                fontSize: settings['fontSize']),
                                          ),
                                        ),
                                        Positioned(
                                          left: 0,
                                          top: 0,
                                          bottom: 0,
                                          width: 10,
                                          child: CustomPaint(
                                            painter: BreakpointPainter(
                                              breakpoints: breakpoints,
                                              lineHeight:
                                                  settings['fontSize'] * 1.5,
                                              controller: tabs[currentTabIndex]
                                                  .controller,
                                            ),
                                          ),
                                        ),
                                        GestureDetector(
                                          onDoubleTap: () {
                                            final line = getCurrentLine(
                                                tabs[currentTabIndex]
                                                    .controller);
                                            setState(() {
                                              if (breakpoints.contains(line)) {
                                                breakpoints.remove(line);
                                              } else {
                                                breakpoints.add(line);
                                              }
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                            ),
                            // Terminal/Debug Panel
                            Container(
                              height: 200,
                              color: Colors.black87,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: xterm.TerminalView(
                                      terminalController,
                                      theme: isLightTheme
                                          ? lightTerminalTheme
                                          : darkTerminalTheme,
                                    ),
                                  ),
                                  if (isDebugging)
                                    Column(
                                      children: [
                                        Text('Pointer: $pointer'),
                                        Text(
                                            'Memory[$pointer]: ${memory[pointer]}'),
                                        Text('Stack: ${loopStack.join(', ')}'),
                                        TextField(
                                          onChanged: (value) =>
                                              debugInput = value,
                                          decoration: const InputDecoration(
                                              labelText: 'Debug Input'),
                                        ),
                                        ElevatedButton(
                                          onPressed: stepDebug,
                                          child: const Text('Step'),
                                        ),
                                        ElevatedButton(
                                          onPressed: () {
                                            setState(() {
                                              isDebugging = false;
                                              output = 'Debugging stopped';
                                              terminalController
                                                  .write('Debugging stopped\n');
                                            });
                                          },
                                          child: const Text('Stop'),
                                        ),
                                      ],
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
                // Status Bar
                Container(
                  color: Colors.grey[900],
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Editor tab model
class EditorTab {
  String path;
  CodeController controller;
  bool isSaved;

  EditorTab(
      {required this.path, required this.controller, required this.isSaved});
}

// File explorer widget
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
        if (!snapshot.hasData) return const CircularProgressIndicator();
        final files = snapshot.data!;
        return ListView.builder(
          itemCount: files.length,
          itemBuilder: (context, index) {
            return ListTile(
              title: Text(files[index].path.split('/').last),
              onTap: () => onFileSelected(files[index].path),
            );
          },
        );
      },
    );
  }
}

// Tab button widget
class TabButton extends StatelessWidget {
  final String title;
  final bool isActive;
  final bool isSaved;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const TabButton({
    super.key,
    required this.title,
    required this.isActive,
    required this.isSaved,
    required this.onTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isActive ? Colors.grey[800] : Colors.grey[900],
      child: Row(
        children: [
          GestureDetector(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(isSaved ? title : '$title *'),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

// Brainfuck language definition
final brainfuckMode = Mode(
  contains: [
    Mode(
      className: 'keyword',
      begin: r'[+\-<>[\].,]',
    ),
    Mode(
      className: 'comment',
      begin: r'[^+\-<>[\].,]',
    ),
  ],
);

// Monokai theme for editor
const monokaiTheme = {
  'keyword': TextStyle(color: Colors.purple),
  'comment': TextStyle(color: Colors.grey),
  'root': TextStyle(backgroundColor: Colors.black, color: Colors.white),
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
  magenta: magenta, // <-- use custom color here
  cyan: Colors.cyan,
  white: Colors.white,
  brightBlack: Colors.grey,
  brightRed: Colors.redAccent,
  brightGreen: Colors.greenAccent,
  brightYellow: Colors.yellowAccent,
  brightBlue: Colors.blueAccent,
  brightMagenta: Colors.pinkAccent, // No magentaAccent; use pinkAccent instead
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

// Custom painter for breakpoint indicators
class BreakpointPainter extends CustomPainter {
  final Set<int> breakpoints;
  final double lineHeight;
  final CodeController controller;

  BreakpointPainter({
    required this.breakpoints,
    required this.lineHeight,
    required this.controller,
  });

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
  bool shouldRepaint(BreakpointPainter oldDelegate) {
    return breakpoints != oldDelegate.breakpoints ||
        lineHeight != oldDelegate.lineHeight;
  }
}
