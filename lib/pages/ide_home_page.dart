import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart' as xterm;
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart'
    as highlightTheme;
import 'package:highlight/languages/plaintext.dart';
import '../models/editor_tab.dart';
import '../widgets/file_explorer.dart';
import '../widgets/tab_button.dart';
import '../services/compiler_service.dart';
import '../services/debug_service.dart';
import '../services/project_service.dart';
import '../services/git_service.dart';
import '../services/plugin_service.dart';
import '../services/settings_service.dart';
import '../utils/terminal_utils.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'dart:io';

class IDEHomePage extends StatefulWidget {
  const IDEHomePage({super.key});

  @override
  State<IDEHomePage> createState() => _IDEHomePageState();
}

class _IDEHomePageState extends State<IDEHomePage> {
  final List<EditorTab> tabs = [];
  int currentTabIndex = -1;
  String projectPath = '';
  String output = '';
  Map<String, dynamic> plugins = {};
  bool isDebugging = false;
  Set<int> breakpoints = {};
  bool isLightTheme = false;
  final xterm.Terminal terminal = xterm.Terminal();
  Map<String, dynamic> settings = {'fontSize': 14.0, 'keybindings': {}};
  bool isDragging = false;
  double terminalHeight = 200;
  final FocusNode _editorFocusNode = FocusNode();
  final TextEditingController _terminalInputController =
      TextEditingController();

  final ProjectService _projectService = ProjectService();
  final CompilerService _compilerService = CompilerService();
  final DebugService _debugService = DebugService();
  final GitService _gitService = GitService();
  final PluginService _pluginService = PluginService();
  final SettingsService _settingsService = SettingsService();

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _settingsService.loadSettings((isLightTheme, newSettings) {
        setState(() {
          this.isLightTheme = isLightTheme;
          settings = newSettings;
        });
      });
      await _pluginService.loadPlugins((newPlugins) {
        setState(() {
          plugins = newPlugins;
        });
      });
      _projectService.openNewTab((path, content) {
        setState(() {
          final controller = CodeController(
            text: content?.text ?? '',
            language: plaintext,
          );
          tabs.add(EditorTab(
              path: path ?? '', controller: controller, isSaved: path == null));
          currentTabIndex = tabs.length - 1;
          _editorFocusNode.requestFocus();
        });
      });
      terminal.write('\x1b[32mBrainfuck IDE Terminal\x1b[0m\n');
      await _compilerService.setupGcc((gccPath, output) {
        setState(() {
          this.output = output;
          terminal.write(output);
        });
      });
    } catch (e) {
      print('Init error: $e');
      terminal.write('\x1b[31mInit error: $e\x1b[0m\n');
    }
  }

  void _processTerminalCommand(String command) {
    if (command == 'clear') {
      terminal.clearAltBuffer();
      terminal.write('\x1b[32mBrainfuck IDE Terminal\x1b[0m\n');
    } else if (command == 'help') {
      terminal.write(
          '\x1b[33mAvailable commands:\n- clear: Clear terminal\n- help: Show this message\x1b[0m\n');
    } else {
      terminal.write('\x1b[31mUnknown command: $command\x1b[0m\n');
    }
  }

  void _lintCode(String code) {
    int depth = 0;
    for (var char in code.runes) {
      if (char == '['.codeUnitAt(0)) depth++;
      if (char == ']'.codeUnitAt(0)) depth--;
      if (depth < 0) {
        setState(() {
          output = '\x1b[31mLint error: Unmatched ]\x1b[0m';
          terminal.write('\x1b[31mLint error: Unmatched ]\x1b[0m\n');
        });
        return;
      }
    }
    if (depth != 0) {
      setState(() {
        output = '\x1b[31mLint error: Unmatched [\x1b[0m';
        terminal.write('\x1b[31mLint error: Unmatched [\x1b[0m\n');
      });
    } else {
      setState(() {
        output = '\x1b[32mLint: No errors\x1b[0m';
        terminal.write('\x1b[32mLint: No errors\x1b[0m\n');
      });
    }
  }

  int _getCurrentLine(EditorTab tab) {
    final text = tab.controller.text;
    final offset = tab.controller.selection.baseOffset;
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
                  _settingsService.saveSettings(isLightTheme, settings);
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
              _projectService.openNewTab((path, content) {
                setState(() {
                  final controller = CodeController(
                    text: content?.text ?? '',
                    language: plaintext,
                  );
                  tabs.add(EditorTab(
                      path: file.path, controller: controller, isSaved: false));
                  currentTabIndex = tabs.length - 1;
                  _editorFocusNode.requestFocus();
                });
              }, path: file.path, content: file.readAsStringSync());
            } else if (file.path.endsWith('.json')) {
              _pluginService.installPlugin(file.path, (newOutput) {
                setState(() {
                  output = newOutput;
                  terminal.write(newOutput);
                });
              });
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
                            onPressed: () => _projectService
                                    .createProject((path, newOutput) {
                                  setState(() {
                                    projectPath = path;
                                    output = newOutput;
                                    terminal.write(newOutput);
                                    _projectService.openNewTab((path, content) {
                                      setState(() {
                                        final controller = CodeController(
                                          text:
                                              'class HelloWorld { init() { print("Hello, World!"); } }',
                                          language: plaintext,
                                        );
                                        tabs.add(EditorTab(
                                            path: path ?? '',
                                            controller: controller,
                                            isSaved: path == null));
                                        currentTabIndex = tabs.length - 1;
                                        _editorFocusNode.requestFocus();
                                      });
                                    },
                                        path: '$path/main.bf',
                                        content:
                                            'class HelloWorld { init() { print("Hello, World!"); } }');
                                  });
                                }),
                            child: const Text('New Project')),
                        TextButton(
                            onPressed: () =>
                                _projectService.openProject((path, newOutput) {
                                  setState(() {
                                    projectPath = path;
                                    output = newOutput;
                                    terminal.write(newOutput);
                                  });
                                }),
                            child: const Text('Open Project')),
                        TextButton(
                            onPressed: () => _projectService.saveFile(
                                    tabs, currentTabIndex, (newOutput) {
                                  setState(() {
                                    output = newOutput;
                                    terminal.write(newOutput);
                                  });
                                }, _compilerService.compileOOPtoBrainfuck),
                            child: const Text('Save')),
                        TextButton(
                            onPressed: () => _compilerService.runCode(
                                    tabs, currentTabIndex, (newOutput) {
                                  setState(() {
                                    output = newOutput;
                                    terminal.write(newOutput);
                                  });
                                }),
                            child: const Text('Run')),
                        TextButton(
                            onPressed: () => _debugService.startDebugging(
                                    tabs, currentTabIndex, (newOutput) {
                                  setState(() {
                                    isDebugging = true;
                                    output = newOutput;
                                    terminal.write(newOutput);
                                  });
                                }, _compilerService.compileOOPtoBrainfuck),
                            child: const Text('Debug')),
                        TextButton(
                            onPressed: () =>
                                _gitService.gitCommit(projectPath, (newOutput) {
                                  setState(() {
                                    output = newOutput;
                                    terminal.write(newOutput);
                                  });
                                }),
                            child: const Text('Commit')),
                        TextButton(
                            onPressed: () =>
                                _gitService.gitPush(projectPath, (newOutput) {
                                  setState(() {
                                    output = newOutput;
                                    terminal.write(newOutput);
                                  });
                                }),
                            child: const Text('Push')),
                        TextButton(
                            onPressed: () =>
                                _gitService.gitPull(projectPath, (newOutput) {
                                  setState(() {
                                    output = newOutput;
                                    terminal.write(newOutput);
                                  });
                                }),
                            child: const Text('Pull')),
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
                                  onPressed: () => _projectService
                                          .openProject((path, newOutput) {
                                        setState(() {
                                          projectPath = path;
                                          output = newOutput;
                                          terminal.write(newOutput);
                                        });
                                      }),
                                  tooltip: 'Open Project',
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                  hoverColor: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withOpacity(0.2)),
                              IconButton(
                                  icon: const Icon(Icons.save),
                                  onPressed: () => _projectService.saveFile(
                                          tabs, currentTabIndex, (newOutput) {
                                        setState(() {
                                          output = newOutput;
                                          terminal.write(newOutput);
                                        });
                                      },
                                          _compilerService
                                              .compileOOPtoBrainfuck),
                                  tooltip: 'Save',
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                  hoverColor: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withOpacity(0.2)),
                              IconButton(
                                  icon: const Icon(Icons.play_arrow),
                                  onPressed: () => _compilerService.runCode(
                                          tabs, currentTabIndex, (newOutput) {
                                        setState(() {
                                          output = newOutput;
                                          terminal.write(newOutput);
                                        });
                                      }),
                                  tooltip: 'Run',
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                  hoverColor: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withOpacity(0.2)),
                              IconButton(
                                  icon: const Icon(Icons.bug_report),
                                  onPressed: () => _debugService.startDebugging(
                                          tabs, currentTabIndex, (newOutput) {
                                        setState(() {
                                          isDebugging = true;
                                          output = newOutput;
                                          terminal.write(newOutput);
                                        });
                                      },
                                          _compilerService
                                              .compileOOPtoBrainfuck),
                                  tooltip: 'Debug',
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                  hoverColor: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withOpacity(0.2)),
                              IconButton(
                                  icon: const Icon(Icons.commit),
                                  onPressed: () => _gitService
                                          .gitCommit(projectPath, (newOutput) {
                                        setState(() {
                                          output = newOutput;
                                          terminal.write(newOutput);
                                        });
                                      }),
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
                                    _projectService.openNewTab((path, content) {
                                      setState(() {
                                        final controller = CodeController(
                                          text: content?.text ?? '',
                                          language: plaintext,
                                        );
                                        tabs.add(EditorTab(
                                            path: path ?? '',
                                            controller: controller,
                                            isSaved: path == null));
                                        currentTabIndex = tabs.length - 1;
                                        _editorFocusNode.requestFocus();
                                      });
                                    },
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
                                                    _lintCode(
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
                                  : CodeTheme(
                                      data: CodeThemeData(
                                          styles: highlightTheme
                                              .monokaiSublimeTheme),
                                      child: Focus(
                                        focusNode: _editorFocusNode,
                                        child: CodeField(
                                          controller:
                                              tabs[currentTabIndex].controller,
                                          expands: true,
                                          textStyle: const TextStyle(
                                              fontFamily: 'JetBrainsMono'),
                                          onChanged: (value) {
                                            print('Text changed: $value');
                                            _lintCode(value);
                                          },
                                        ),
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
                                      terminal,
                                      theme: isLightTheme
                                          ? lightTerminalTheme
                                          : darkTerminalTheme,
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
                                              terminal.write(
                                                  '\r\n\x1b[33m> \x1b[0m$value\r\n');
                                              _processTerminalCommand(value);
                                              _terminalInputController.clear();
                                            },
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.send),
                                          onPressed: () {
                                            terminal.write(
                                                '\r\n\x1b[33m> \x1b[0m${_terminalInputController.text}\r\n');
                                            _processTerminalCommand(
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
                            : 'Line ${_getCurrentLine(tabs[currentTabIndex])}'),
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
