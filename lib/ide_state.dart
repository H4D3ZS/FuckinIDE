part of 'main.dart';

class IdeState {
  final List<EditorTab> tabs;
  final int currentTabIndex;
  final String projectPath;
  final String output;
  final Map<String, dynamic> plugins;
  final bool isDebugging;
  final Set<int> breakpoints;
  final List<int> memory;
  final int pointer;
  final int instructionPointer;
  final List<int> loopStack;
  final String debugInput;
  final bool isLightTheme;
  final xterm.Terminal terminalController;
  final Map<String, dynamic> settings;
  final bool isDragging;

  IdeState({
    required this.tabs,
    required this.currentTabIndex,
    required this.projectPath,
    required this.output,
    required this.plugins,
    required this.isDebugging,
    required this.breakpoints,
    required this.memory,
    required this.pointer,
    required this.instructionPointer,
    required this.loopStack,
    required this.debugInput,
    required this.isLightTheme,
    required this.terminalController,
    required this.settings,
    required this.isDragging,
  });

  factory IdeState.initial() {
    return IdeState(
      tabs: [],
      currentTabIndex: -1,
      projectPath: '',
      output: '',
      plugins: {},
      isDebugging: false,
      breakpoints: {},
      memory: List.filled(30000, 0),
      pointer: 0,
      instructionPointer: 0,
      loopStack: [],
      debugInput: '',
      isLightTheme: false,
      terminalController: xterm.Terminal(),
      settings: {},
      isDragging: false,
    );
  }

  IdeState copyWith({
    List<EditorTab>? tabs,
    int? currentTabIndex,
    String? projectPath,
    String? output,
    Map<String, dynamic>? plugins,
    bool? isDebugging,
    Set<int>? breakpoints,
    List<int>? memory,
    int? pointer,
    int? instructionPointer,
    List<int>? loopStack,
    String? debugInput,
    bool? isLightTheme,
    xterm.Terminal? terminalController,
    Map<String, dynamic>? settings,
    bool? isDragging,
  }) {
    return IdeState(
      tabs: tabs ?? this.tabs,
      currentTabIndex: currentTabIndex ?? this.currentTabIndex,
      projectPath: projectPath ?? this.projectPath,
      output: output ?? this.output,
      plugins: plugins ?? this.plugins,
      isDebugging: isDebugging ?? this.isDebugging,
      breakpoints: breakpoints ?? this.breakpoints,
      memory: memory ?? this.memory,
      pointer: pointer ?? this.pointer,
      instructionPointer: instructionPointer ?? this.instructionPointer,
      loopStack: loopStack ?? this.loopStack,
      debugInput: debugInput ?? this.debugInput,
      isLightTheme: isLightTheme ?? this.isLightTheme,
      terminalController: terminalController ?? this.terminalController,
      settings: settings ?? this.settings,
      isDragging: isDragging ?? this.isDragging,
    );
  }
}
