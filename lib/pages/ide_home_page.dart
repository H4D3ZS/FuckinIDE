import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart' as xterm;
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/languages/plaintext.dart';
import 'package:highlight/languages/all.dart';
import 'package:highlight/highlight.dart' show Node, Mode, highlight;
import '../models/editor_tab.dart';
import '../widgets/file_explorer.dart';
import '../services/compiler_service.dart';
import '../services/debug_service.dart';
import '../services/project_service.dart';
import '../services/git_service.dart';
import '../services/plugin_service.dart';
import '../services/settings_service.dart';
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
  String liveOutput = '';
  List<String> errors = [];
  Map<String, dynamic> plugins = {};
  bool isDebugging = false;
  Set<int> breakpoints = {};
  bool isLightTheme = false;
  final xterm.Terminal terminal = xterm.Terminal(maxLines: 1000);
  Map<String, dynamic> settings = {'fontSize': 14.0, 'keybindings': {}};
  bool isDragging = false;
  double terminalHeight = 150.0;
  final FocusNode _editorFocusNode = FocusNode();
  final TextEditingController _terminalInputController =
      TextEditingController();
  String _currentTab = 'Terminal'; // Terminal, Problems, Output

  final ProjectService _projectService = ProjectService();
  final CompilerService _compilerService = CompilerService();
  final DebugService _debugService = DebugService();
  final GitService _gitService = GitService();
  final PluginService _pluginService = PluginService();
  final SettingsService _settingsService = SettingsService();

  // Define EasyBF language for syntax highlighting
  final Mode easybf = Mode(
    ref: 'easybf',
    aliases: ['easybf', 'eb'],
    contains: [
      Mode(
        className: 'keyword',
        begin: r'\+(CLASS|METHOD|VAR|OBJ|LOOP|-END)|CALL|SET|OUT|OUTVAR',
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
        className: 'comment',
        begin: r'#',
        end: r'$',
        relevance: 0,
      ),
    ],
  );

  @override
  void initState() {
    super.initState();
    highlight.registerLanguage('easybf', easybf);
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
            language: easybf,
          );
          controller.addListener(() {
            if (currentTabIndex >= 0 && currentTabIndex < tabs.length) {
              try {
                final bfCode = _compilerService.compileEasyBFToBrainfuck(
                    tabs[currentTabIndex].controller.text);
                setState(() {
                  liveOutput = _compilerService.getLiveOutput();
                  // Remove reliance on getErrors
                });
              } catch (e) {
                setState(() {
                  liveOutput = 'Error: $e';
                  errors.add('Error: $e');
                });
              }
            }
          });
          tabs.add(EditorTab(
              path: path ?? '', controller: controller, isSaved: path == null));
          currentTabIndex = tabs.length - 1;
          _editorFocusNode.requestFocus();
        });
      });
      terminal.write('Brainfuck IDE Terminal\n');
      await _compilerService.setupGcc((_, output) {
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
      terminal.eraseDisplay();
      terminal.write('Brainfuck IDE Terminal\n');
    } else if (command == 'help') {
      terminal.write(
          '\x1b[33mAvailable commands:\n- clear: Clear terminal\n- help: Show this message\x1b[0m\n');
    } else {
      terminal.write('\x1b[31mUnknown command: $command\x1b[0m\n');
    }
  }

  void _lintCode(String code) {
    int depth = 0;
    final lines = code.split('\n');
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (line.startsWith('+CLASS') ||
          line.startsWith('+METHOD') ||
          line.startsWith('+LOOP')) {
        depth++;
      } else if (line == '-END') {
        depth--;
      }
      if (depth < 0) {
        setState(() {
          output = '\x1b[31mLint error at line ${i + 1}: Unmatched -END\x1b[0m';
          terminal.write(
              '\x1b[31mLint error at line ${i + 1}: Unmatched -END\x1b[0m\n');
          errors.add('Lint error at line ${i + 1}: Unmatched -END');
        });
        return;
      }
    }
    if (depth != 0) {
      setState(() {
        output = '\x1b[31mLint error: Unmatched block start\x1b[0m';
        terminal.write('\x1b[31mLint error: Unmatched block start\x1b[0m\n');
        errors.add('Lint error: Unmatched block start');
      });
    } else {
      setState(() {
        output = '\x1b[32mLint: No errors\x1b[0m';
        terminal.write('\x1b[32mLint: No errors\x1b[0m\n');
      });
    }
  }

  String _prettify(String code) {
    final lines = code.split('\n');
    StringBuffer formattedCode = StringBuffer();
    int indentLevel = 0;
    const int indentSize = 2;

    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('#')) {
        formattedCode.writeln(line);
        continue;
      }

      if (line == '-END') {
        indentLevel = (indentLevel - 1).clamp(0, indentLevel);
      }

      formattedCode.write(' ' * (indentLevel * indentSize));
      formattedCode.writeln(line);

      if (line.startsWith('+CLASS') ||
          line.startsWith('+METHOD') ||
          line.startsWith('+LOOP')) {
        indentLevel++;
      }
    }

    return formattedCode.toString().trimRight();
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

  void _jumpToLine(int lineNumber) {
    if (currentTabIndex >= 0 && currentTabIndex < tabs.length) {
      final controller = tabs[currentTabIndex].controller;
      final lines = controller.text.split('\n');
      int charOffset = 0;
      for (int i = 0; i < lineNumber - 1 && i < lines.length; i++) {
        charOffset += lines[i].length + 1; // +1 for the newline
      }
      controller.selection =
          TextSelection.fromPosition(TextPosition(offset: charOffset));
      _editorFocusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 600;
    final sidebarWidth = isSmallScreen ? 50.0 : 60.0;
    final explorerWidth = isSmallScreen ? 150.0 : 200.0;
    final outputViewerWidth = isSmallScreen ? 150.0 : 200.0;

    return MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue[900]!,
          brightness: Brightness.dark,
          primary: Colors.blue[700],
          secondary: Colors.cyan[300],
          surface: Colors.grey[850],
          onSurface: Colors.white,
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 14),
          bodyMedium: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12),
          labelLarge: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12),
        ),
        scaffoldBackgroundColor: Colors.grey[900],
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.blue[900],
          foregroundColor: Colors.white,
          elevation: 2,
        ),
        iconTheme: const IconThemeData(color: Colors.white70),
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Brainfuck IDE',
              style: TextStyle(fontWeight: FontWeight.bold)),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () {
                setState(() {
                  isLightTheme = !isLightTheme;
                  _settingsService.saveSettings(isLightTheme, settings);
                });
              },
              tooltip: 'Toggle Theme',
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
                    language: easybf,
                  );
                  controller.addListener(() {
                    if (currentTabIndex >= 0 && currentTabIndex < tabs.length) {
                      try {
                        final bfCode =
                            _compilerService.compileEasyBFToBrainfuck(
                                tabs[currentTabIndex].controller.text);
                        setState(() {
                          liveOutput = _compilerService.getLiveOutput();
                          // Remove reliance on getErrors
                        });
                      } catch (e) {
                        setState(() {
                          liveOutput = 'Error: $e';
                          errors.add('Error: $e');
                        });
                      }
                    }
                  });
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
            color: isDragging ? Colors.blue[900]!.withOpacity(0.2) : null,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: sidebarWidth,
                  child: Container(
                    color: Colors.grey[800],
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.folder_open, size: 20),
                          onPressed: () =>
                              _projectService.openProject((path, newOutput) {
                            setState(() {
                              projectPath = path;
                              output = newOutput;
                              terminal.write(newOutput);
                            });
                          }),
                          tooltip: 'Open Project',
                          color: Colors.white70,
                          padding: const EdgeInsets.all(8),
                        ),
                        IconButton(
                          icon: const Icon(Icons.save, size: 20),
                          onPressed: () => _projectService
                              .saveFile(tabs, currentTabIndex, (newOutput) {
                            setState(() {
                              output = newOutput;
                              terminal.write(newOutput);
                            });
                          }, _compilerService.compileEasyBFToBrainfuck),
                          tooltip: 'Save',
                          color: Colors.white70,
                          padding: const EdgeInsets.all(8),
                        ),
                        IconButton(
                          icon: const Icon(Icons.play_arrow, size: 20),
                          onPressed: () => _compilerService
                              .runCode(tabs, currentTabIndex, (newOutput) {
                            setState(() {
                              output = newOutput;
                              terminal.write(newOutput);
                            });
                          }),
                          tooltip: 'Run',
                          color: Colors.white70,
                          padding: const EdgeInsets.all(8),
                        ),
                        IconButton(
                          icon: const Icon(Icons.bug_report, size: 20),
                          onPressed: () => _debugService.startDebugging(
                              tabs, currentTabIndex, (newOutput) {
                            setState(() {
                              isDebugging = true;
                              output = newOutput;
                              terminal.write(newOutput);
                            });
                          }, _compilerService.compileEasyBFToBrainfuck),
                          tooltip: 'Debug',
                          color: Colors.white70,
                          padding: const EdgeInsets.all(8),
                        ),
                        IconButton(
                          icon: const Icon(Icons.commit, size: 20),
                          onPressed: () =>
                              _gitService.gitCommit(projectPath, (newOutput) {
                            setState(() {
                              output = newOutput;
                              terminal.write(newOutput);
                            });
                          }),
                          tooltip: 'Git Commit',
                          color: Colors.white70,
                          padding: const EdgeInsets.all(8),
                        ),
                        const Spacer(),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        color: Colors.grey[700],
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _buildToolbarButton(
                                      'New Project',
                                      () => _projectService
                                              .createProject((path, newOutput) {
                                            setState(() {
                                              projectPath = path;
                                              output = newOutput;
                                              terminal.write(newOutput);
                                              _projectService.openNewTab(
                                                  (path, content) {
                                                setState(() {
                                                  final controller =
                                                      CodeController(
                                                    text:
                                                        '+CLASS Hello\n  +METHOD init\n    OUT 72  # H\n    OUT 101 # e\n    OUT 108 # l\n    OUT 108 # l\n    OUT 111 # o\n  -END\n-END\n+OBJ Hello hello\nCALL hello.init',
                                                    language: easybf,
                                                  );
                                                  controller.addListener(() {
                                                    if (currentTabIndex >= 0 &&
                                                        currentTabIndex <
                                                            tabs.length) {
                                                      try {
                                                        final bfCode = _compilerService
                                                            .compileEasyBFToBrainfuck(
                                                                tabs[currentTabIndex]
                                                                    .controller
                                                                    .text);
                                                        setState(() {
                                                          liveOutput =
                                                              _compilerService
                                                                  .getLiveOutput();
                                                          // Remove reliance on getErrors
                                                        });
                                                      } catch (e) {
                                                        setState(() {
                                                          liveOutput =
                                                              'Error: $e';
                                                          errors
                                                              .add('Error: $e');
                                                        });
                                                      }
                                                    }
                                                  });
                                                  tabs.add(EditorTab(
                                                      path: path ?? '',
                                                      controller: controller,
                                                      isSaved: path == null));
                                                  currentTabIndex =
                                                      tabs.length - 1;
                                                  _editorFocusNode
                                                      .requestFocus();
                                                });
                                              },
                                                  path: '$path/main.bf',
                                                  content:
                                                      '+CLASS Hello\n  +METHOD init\n    OUT 72  # H\n    OUT 101 # e\n    OUT 108 # l\n    OUT 108 # l\n    OUT 111 # o\n  -END\n-END\n+OBJ Hello hello\nCALL hello.init');
                                            });
                                          })),
                                  const SizedBox(width: 8),
                                  _buildToolbarButton(
                                      'Open Project',
                                      () => _projectService
                                              .openProject((path, newOutput) {
                                            setState(() {
                                              projectPath = path;
                                              output = newOutput;
                                              terminal.write(newOutput);
                                            });
                                          })),
                                  const SizedBox(width: 8),
                                  _buildToolbarButton(
                                      'Save',
                                      () => _projectService.saveFile(
                                              tabs, currentTabIndex,
                                              (newOutput) {
                                            setState(() {
                                              output = newOutput;
                                              terminal.write(newOutput);
                                            });
                                          },
                                              _compilerService
                                                  .compileEasyBFToBrainfuck)),
                                  const SizedBox(width: 8),
                                  _buildToolbarButton(
                                      'Run',
                                      () => _compilerService
                                              .runCode(tabs, currentTabIndex,
                                                  (newOutput) {
                                            setState(() {
                                              output = newOutput;
                                              terminal.write(newOutput);
                                            });
                                          })),
                                  const SizedBox(width: 8),
                                  _buildToolbarButton(
                                      'Debug',
                                      () => _debugService.startDebugging(
                                              tabs, currentTabIndex,
                                              (newOutput) {
                                            setState(() {
                                              isDebugging = true;
                                              output = newOutput;
                                              terminal.write(newOutput);
                                            });
                                          },
                                              _compilerService
                                                  .compileEasyBFToBrainfuck)),
                                  const SizedBox(width: 8),
                                  _buildToolbarButton(
                                      'Commit',
                                      () => _gitService.gitCommit(projectPath,
                                              (newOutput) {
                                            setState(() {
                                              output = newOutput;
                                              terminal.write(newOutput);
                                            });
                                          })),
                                  const SizedBox(width: 8),
                                  _buildToolbarButton(
                                      'Push',
                                      () => _gitService.gitPush(projectPath,
                                              (newOutput) {
                                            setState(() {
                                              output = newOutput;
                                              terminal.write(newOutput);
                                            });
                                          })),
                                  const SizedBox(width: 8),
                                  _buildToolbarButton(
                                      'Pull',
                                      () => _gitService.gitPull(projectPath,
                                              (newOutput) {
                                            setState(() {
                                              output = newOutput;
                                              terminal.write(newOutput);
                                            });
                                          })),
                                  const SizedBox(width: 8),
                                  _buildToolbarButton('Prettify', () {
                                    if (currentTabIndex >= 0 &&
                                        currentTabIndex < tabs.length) {
                                      final formattedCode = _prettify(
                                          tabs[currentTabIndex]
                                              .controller
                                              .text);
                                      setState(() {
                                        tabs[currentTabIndex].controller.text =
                                            formattedCode;
                                      });
                                    }
                                  }),
                                ],
                              ),
                            ),
                            if (tabs.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: Text(
                                  'Line ${_getCurrentLine(tabs[currentTabIndex])}',
                                  style: const TextStyle(
                                      color: Colors.white70,
                                      fontFamily: 'JetBrainsMono',
                                      fontSize: 12),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: explorerWidth,
                              child: Container(
                                color: Colors.grey[800],
                                child: projectPath.isEmpty
                                    ? const Center(
                                        child: Text('No project opened',
                                            style: TextStyle(
                                                color: Colors.white70)))
                                    : FileExplorer(
                                        path: projectPath,
                                        onFileSelected: (path) {
                                          _projectService.openNewTab(
                                              (path, content) {
                                            setState(() {
                                              final controller = CodeController(
                                                text: content?.text ?? '',
                                                language: easybf,
                                              );
                                              controller.addListener(() {
                                                if (currentTabIndex >= 0 &&
                                                    currentTabIndex <
                                                        tabs.length) {
                                                  try {
                                                    final bfCode = _compilerService
                                                        .compileEasyBFToBrainfuck(
                                                            tabs[currentTabIndex]
                                                                .controller
                                                                .text);
                                                    setState(() {
                                                      liveOutput =
                                                          _compilerService
                                                              .getLiveOutput();
                                                      // Remove reliance on getErrors
                                                    });
                                                  } catch (e) {
                                                    setState(() {
                                                      liveOutput = 'Error: $e';
                                                      errors.add('Error: $e');
                                                    });
                                                  }
                                                }
                                              });
                                              tabs.add(EditorTab(
                                                  path: path ?? '',
                                                  controller: controller,
                                                  isSaved: path == null));
                                              currentTabIndex = tabs.length - 1;
                                              _editorFocusNode.requestFocus();
                                            });
                                          },
                                              path: path,
                                              content: File(path)
                                                  .readAsStringSync());
                                        },
                                      ),
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (tabs.isNotEmpty)
                                    Container(
                                      color: Colors.grey[700],
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 4),
                                      child: SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: Row(
                                          children: List.generate(
                                            tabs.length,
                                            (index) => Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 4),
                                              child: GestureDetector(
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
                                                child: Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 12,
                                                      vertical: 6),
                                                  decoration: BoxDecoration(
                                                    color:
                                                        index == currentTabIndex
                                                            ? Colors.blue[700]
                                                            : Colors.grey[600],
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            4),
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      Text(
                                                        tabs[index].path.isEmpty
                                                            ? 'Untitled'
                                                            : tabs[index]
                                                                .path
                                                                .split('/')
                                                                .last,
                                                        style: const TextStyle(
                                                            color: Colors.white,
                                                            fontFamily:
                                                                'JetBrainsMono',
                                                            fontSize: 12),
                                                      ),
                                                      if (!tabs[index].isSaved)
                                                        const Text('*',
                                                            style: TextStyle(
                                                                color: Colors
                                                                    .red)),
                                                      const SizedBox(width: 8),
                                                      IconButton(
                                                        icon: const Icon(
                                                            Icons.close,
                                                            size: 16,
                                                            color:
                                                                Colors.white70),
                                                        onPressed: () {
                                                          setState(() {
                                                            tabs.removeAt(
                                                                index);
                                                            if (currentTabIndex >=
                                                                tabs.length)
                                                              currentTabIndex =
                                                                  tabs.length -
                                                                      1;
                                                          });
                                                        },
                                                        padding:
                                                            EdgeInsets.zero,
                                                        constraints:
                                                            const BoxConstraints(),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  Expanded(
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Expanded(
                                          child: currentTabIndex == -1
                                              ? const Center(
                                                  child: Text('No file opened',
                                                      style: TextStyle(
                                                          color:
                                                              Colors.white70)))
                                              : CodeTheme(
                                                  data: CodeThemeData(styles: {
                                                    'root': const TextStyle(
                                                        backgroundColor:
                                                            Colors.transparent),
                                                    'keyword': TextStyle(
                                                        color: Colors.blue[700],
                                                        fontWeight:
                                                            FontWeight.bold),
                                                    'variable': TextStyle(
                                                        color:
                                                            Colors.green[400]),
                                                    'number': TextStyle(
                                                        color:
                                                            Colors.orange[400]),
                                                    'comment': TextStyle(
                                                        color:
                                                            Colors.grey[500]),
                                                  }),
                                                  child: Focus(
                                                    focusNode: _editorFocusNode,
                                                    child: CodeField(
                                                      controller:
                                                          tabs[currentTabIndex]
                                                              .controller,
                                                      expands: true,
                                                      textStyle: const TextStyle(
                                                          fontFamily:
                                                              'JetBrainsMono',
                                                          fontSize: 14),
                                                      onChanged: (value) {
                                                        print(
                                                            'Text changed: $value');
                                                        _lintCode(value);
                                                        if (currentTabIndex >=
                                                                0 &&
                                                            currentTabIndex <
                                                                tabs.length) {
                                                          try {
                                                            final bfCode =
                                                                _compilerService
                                                                    .compileEasyBFToBrainfuck(
                                                                        value);
                                                            setState(() {
                                                              liveOutput =
                                                                  _compilerService
                                                                      .getLiveOutput();
                                                              // Remove reliance on getErrors
                                                            });
                                                          } catch (e) {
                                                            setState(() {
                                                              liveOutput =
                                                                  'Error: $e';
                                                              errors.add(
                                                                  'Error: $e');
                                                            });
                                                          }
                                                        }
                                                      },
                                                    ),
                                                  ),
                                                ),
                                        ),
                                        SizedBox(
                                          width: outputViewerWidth,
                                          child: Container(
                                            color: Colors.grey[850],
                                            padding: const EdgeInsets.all(12),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                const Text(
                                                  'Live Output',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontFamily: 'JetBrainsMono',
                                                    fontSize: 14,
                                                  ),
                                                ),
                                                const Divider(
                                                    color: Colors.white70,
                                                    height: 16),
                                                Expanded(
                                                  child: SingleChildScrollView(
                                                    child: Text(
                                                      liveOutput.isEmpty
                                                          ? 'No output'
                                                          : liveOutput,
                                                      style: TextStyle(
                                                        color: liveOutput
                                                                .startsWith(
                                                                    'Error:')
                                                            ? Colors.red
                                                            : Colors.white,
                                                        fontFamily:
                                                            'JetBrainsMono',
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  GestureDetector(
                                    onVerticalDragUpdate: (details) {
                                      setState(() {
                                        terminalHeight =
                                            (terminalHeight - details.delta.dy)
                                                .clamp(100.0, 400.0);
                                      });
                                    },
                                    child: Container(
                                      height: 5,
                                      color: Colors.grey[600],
                                      child: Center(
                                        child: Container(
                                          width: 40,
                                          height: 3,
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Container(
                                    height: terminalHeight,
                                    decoration: BoxDecoration(
                                      border: Border(
                                          top: BorderSide(
                                              color: Colors.grey[600]!,
                                              width: 1)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Container(
                                          color: Colors.grey[700],
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 6),
                                          child: Row(
                                            children: [
                                              _buildTab('Terminal'),
                                              const SizedBox(width: 12),
                                              _buildTab('Problems'),
                                              const SizedBox(width: 12),
                                              _buildTab('Output'),
                                            ],
                                          ),
                                        ),
                                        Expanded(
                                          child: _currentTab == 'Terminal'
                                              ? xterm.TerminalView(
                                                  terminal,
                                                  theme: xterm.TerminalTheme(
                                                    cursor: Colors.white,
                                                    foreground: Colors.white,
                                                    background: Colors.black,
                                                    selection: Colors.blue[700]!
                                                        .withOpacity(0.3),
                                                    black: Colors.black,
                                                    white: Colors.white,
                                                    red: Colors.red,
                                                    green: Colors.green,
                                                    yellow: Colors.yellow,
                                                    blue: Colors.blue,
                                                    magenta: Color(0xFFFF00FF),
                                                    cyan: Colors.cyan,
                                                    brightBlack: Colors.grey,
                                                    brightRed: Colors.redAccent,
                                                    brightGreen:
                                                        Colors.greenAccent,
                                                    brightYellow:
                                                        Colors.yellowAccent,
                                                    brightBlue:
                                                        Colors.blueAccent,
                                                    brightMagenta:
                                                        Colors.purpleAccent,
                                                    brightCyan:
                                                        Colors.cyanAccent,
                                                    brightWhite: Colors.white70,
                                                    searchHitBackground:
                                                        Colors.grey,
                                                    searchHitBackgroundCurrent:
                                                        Colors.grey,
                                                    searchHitForeground:
                                                        Colors.white,
                                                  ),
                                                  textStyle:
                                                      const xterm.TerminalStyle(
                                                    fontFamily: 'JetBrainsMono',
                                                    fontSize: 12,
                                                  ),
                                                )
                                              : _currentTab == 'Problems'
                                                  ? Container(
                                                      color: Colors.black,
                                                      padding:
                                                          const EdgeInsets.all(
                                                              12),
                                                      child:
                                                          SingleChildScrollView(
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: errors
                                                                  .isEmpty
                                                              ? [
                                                                  const Text(
                                                                    'No problems found',
                                                                    style:
                                                                        TextStyle(
                                                                      color: Colors
                                                                          .white70,
                                                                      fontFamily:
                                                                          'JetBrainsMono',
                                                                      fontSize:
                                                                          12,
                                                                    ),
                                                                  ),
                                                                ]
                                                              : errors
                                                                  .asMap()
                                                                  .entries
                                                                  .map((entry) {
                                                                  int idx =
                                                                      entry.key;
                                                                  String error =
                                                                      entry
                                                                          .value;
                                                                  RegExp
                                                                      lineRegExp =
                                                                      RegExp(
                                                                          r'Line (\d+):');
                                                                  var match = lineRegExp
                                                                      .firstMatch(
                                                                          error);
                                                                  int? lineNumber = match !=
                                                                          null
                                                                      ? int.tryParse(
                                                                          match.group(
                                                                              1)!)
                                                                      : null;
                                                                  return GestureDetector(
                                                                    onTap: lineNumber !=
                                                                            null
                                                                        ? () =>
                                                                            _jumpToLine(lineNumber)
                                                                        : null,
                                                                    child:
                                                                        Padding(
                                                                      padding: const EdgeInsets
                                                                          .symmetric(
                                                                          vertical:
                                                                              4),
                                                                      child:
                                                                          Text(
                                                                        error,
                                                                        style:
                                                                            TextStyle(
                                                                          color:
                                                                              Colors.red,
                                                                          fontFamily:
                                                                              'JetBrainsMono',
                                                                          fontSize:
                                                                              12,
                                                                          decoration: lineNumber != null
                                                                              ? TextDecoration.underline
                                                                              : null,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  );
                                                                }).toList(),
                                                        ),
                                                      ),
                                                    )
                                                  : Container(
                                                      color: Colors.black,
                                                      padding:
                                                          const EdgeInsets.all(
                                                              12),
                                                      child:
                                                          SingleChildScrollView(
                                                        child: Text(
                                                          output.isEmpty
                                                              ? 'No output'
                                                              : output,
                                                          style:
                                                              const TextStyle(
                                                            color: Colors.white,
                                                            fontFamily:
                                                                'JetBrainsMono',
                                                            fontSize: 12,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                        ),
                                        if (_currentTab == 'Terminal')
                                          Container(
                                            color: Colors.grey[800],
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 6),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: TextField(
                                                    controller:
                                                        _terminalInputController,
                                                    decoration: InputDecoration(
                                                      hintText:
                                                          'Enter command...',
                                                      hintStyle:
                                                          const TextStyle(
                                                        color: Colors.grey,
                                                        fontFamily:
                                                            'JetBrainsMono',
                                                        fontSize: 12,
                                                      ),
                                                      border:
                                                          OutlineInputBorder(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(4),
                                                        borderSide:
                                                            const BorderSide(
                                                                color: Colors
                                                                    .grey),
                                                      ),
                                                      filled: true,
                                                      fillColor:
                                                          Colors.grey[900],
                                                      contentPadding:
                                                          const EdgeInsets
                                                              .symmetric(
                                                              horizontal: 12,
                                                              vertical: 8),
                                                    ),
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontFamily:
                                                          'JetBrainsMono',
                                                      fontSize: 12,
                                                    ),
                                                    onSubmitted: (value) {
                                                      terminal.write(
                                                          '\r\n> $value\r\n');
                                                      _processTerminalCommand(
                                                          value);
                                                      _terminalInputController
                                                          .clear();
                                                    },
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                IconButton(
                                                  icon: const Icon(Icons.send,
                                                      color: Colors.white70,
                                                      size: 20),
                                                  onPressed: () {
                                                    terminal.write(
                                                        '\r\n> ${_terminalInputController.text}\r\n');
                                                    _processTerminalCommand(
                                                        _terminalInputController
                                                            .text);
                                                    _terminalInputController
                                                        .clear();
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
                      Container(
                        height: 22,
                        color: Colors.grey[700],
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              currentTabIndex == -1
                                  ? 'Line 1'
                                  : 'Line ${_getCurrentLine(tabs[currentTabIndex])}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontFamily: 'JetBrainsMono',
                                fontSize: 12,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                output.isEmpty ? 'No project' : output,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontFamily: 'JetBrainsMono',
                                  fontSize: 12,
                                ),
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
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
        ),
      ),
    );
  }

  Widget _buildToolbarButton(String label, VoidCallback onPressed) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        backgroundColor: Colors.grey[600],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontFamily: 'JetBrainsMono',
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildTab(String tabName) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _currentTab = tabName;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _currentTab == tabName ? Colors.blue[700] : Colors.grey[600],
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          tabName,
          style: const TextStyle(
            color: Colors.white,
            fontFamily: 'JetBrainsMono',
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
