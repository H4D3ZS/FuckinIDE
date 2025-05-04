import '../models/editor_tab.dart';

class DebugService {
  List<int> memory = List.filled(30000, 0);
  int pointer = 0;
  int instructionPointer = 0;
  List<int> loopStack = [];
  String debugInput = '';

  void startDebugging(
      List<EditorTab> tabs, int currentTabIndex, Function(String) callback) {
    if (currentTabIndex == -1) return;
    callback(
        '\x1b[31mDebugging not supported for native executables. Use a C debugger like gdb on the generated executable.\x1b[0m\n');
  }

  void stepDebug(List<EditorTab> tabs, int currentTabIndex,
      Set<int> breakpoints, bool isDebugging, Function(String, bool) callback) {
    if (!isDebugging || currentTabIndex == -1) return;
    callback('\x1b[31mDebugging not supported for native executables.\x1b[0m\n',
        false);
  }
}
