import '../models/editor_tab.dart';

class DebugService {
  List<int> memory = List.filled(30000, 0);
  int pointer = 0;
  int instructionPointer = 0;
  List<int> loopStack = [];
  String debugInput = '';

  void startDebugging(
      List<EditorTab> tabs,
      int currentTabIndex,
      Function(String) callback,
      String Function(String) compileOOPtoBrainfuck) {
    if (currentTabIndex == -1) return;
    memory = List.filled(30000, 0);
    pointer = 0;
    instructionPointer = 0;
    loopStack = [];
    debugInput = '';
    callback('\x1b[32mDebugging started\x1b[0m\n');
  }

  void stepDebug(
      List<EditorTab> tabs,
      int currentTabIndex,
      Set<int> breakpoints,
      bool isDebugging,
      Function(String, bool) callback,
      String Function(String) compileOOPtoBrainfuck) {
    if (!isDebugging || currentTabIndex == -1) return;
    final code = compileOOPtoBrainfuck(tabs[currentTabIndex].controller.text);
    if (instructionPointer >= code.length) {
      callback('\x1b[32mDebugging finished\x1b[0m\n', false);
      return;
    }
    if (breakpoints.contains(instructionPointer)) {
      callback(
          '\x1b[33mHit breakpoint at instruction $instructionPointer\x1b[0m\n',
          isDebugging);
      return;
    }
    final char = code[instructionPointer];
    String output = '';
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
        callback(output, isDebugging);
        break;
      case ',':
        if (debugInput.isEmpty) {
          callback('\x1b[33mWaiting for input\x1b[0m\n', isDebugging);
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
    callback(
        '\x1b[36mStepped: ptr=$pointer, mem[$pointer]=${memory[pointer]}\x1b[0m\n',
        isDebugging);
  }
}
