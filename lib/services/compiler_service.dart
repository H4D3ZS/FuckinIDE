import 'dart:io';
import 'package:fuckin_ide/utils/extensions.dart';
import 'package:path_provider/path_provider.dart';
import '../models/editor_tab.dart';
import 'package:platform/platform.dart' show LocalPlatform;

class CompilerService {
  String? _gccPath;
  final Platform = const LocalPlatform();

  // Memory management
  int _memoryOffset = 0;
  Map<String, int> _symbolTable =
      {}; // Variable/class instance -> memory offset
  List<int> _freeCells =
      List.generate(30000, (i) => i); // Available memory cells
  Map<int, bool> _memoryUsage = {}; // Track used cells for garbage collection
  StringBuffer _outputBuffer = StringBuffer(); // For live output
  List<String> _errors = []; // Track errors with line numbers

  Future<void> setupGcc(Function(String?, String) callback) async {
    try {
      final result = await Process.run('which', ['gcc']);
      if (result.exitCode == 0 && result.stdout.isNotEmpty) {
        _gccPath = result.stdout.trim();
      } else {
        _gccPath = '/usr/bin/gcc';
      }
      if (_gccPath != null && await File(_gccPath!).exists()) {
        callback(
            _gccPath, '\x1b[32mGCC compiler initialized at $_gccPath\x1b[0m\n');
      } else {
        throw Exception(
            'GCC not found at $_gccPath. Install via Xcode Command Line Tools or Homebrew.');
      }
    } catch (e) {
      callback(null, '\x1b[31mFailed to initialize GCC: $e\x1b[0m\n');
    }
  }

  int _allocateMemory(String name, int size) {
    if (_freeCells.length < size) {
      _garbageCollect();
      if (_freeCells.length < size) throw Exception('Out of memory');
    }
    int offset = _freeCells[0];
    _freeCells.removeAt(0);
    _symbolTable[name] = offset;
    _memoryUsage[offset] = true;
    return offset;
  }

  void _freeMemory(String name) {
    if (_symbolTable.containsKey(name)) {
      int offset = _symbolTable[name]!;
      _freeCells.add(offset);
      _memoryUsage.remove(offset);
      _symbolTable.remove(name);
    }
  }

  void _garbageCollect() {
    List<int> activeOffsets = _symbolTable.values.toList();
    _memoryUsage.keys
        .where((offset) => !activeOffsets.contains(offset))
        .forEach((offset) {
      _freeCells.add(offset);
      _memoryUsage.remove(offset);
    });
    _freeCells.sort();
  }

  String compileEasyBFToBrainfuck(String code) {
    final lines = code.split('\n').map((line) => line.trim()).toList();
    StringBuffer bfCode = StringBuffer();
    _memoryOffset = 0;
    _symbolTable.clear();
    _freeCells = List.generate(30000, (i) => i);
    _memoryUsage.clear();
    _outputBuffer.clear();
    _errors.clear();

    Map<String, Map<String, int>> classDefinitions =
        {}; // class -> method -> offset
    Map<String, String> classInheritance = {}; // class -> parent
    Map<String, String> instanceToClass = {}; // instance -> class
    String? currentClass;
    String? currentMethod;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.isEmpty || line.startsWith('#')) continue;

      int lineNumber = i + 1;

      if (line.startsWith('+CLASS')) {
        List<String> parts = line.split(' ');
        if (parts.length < 2) {
          _errors.add('Line $lineNumber: Invalid class definition');
          continue;
        }
        currentClass = parts[1];
        String parent = parts.length > 2 ? parts[2] : '';
        classDefinitions[currentClass] = {};
        if (parent.isNotEmpty) classInheritance[currentClass] = parent;
        int classOffset = _allocateMemory(currentClass, 1);
        bfCode.write('>' * classOffset + '[-]');
        _memoryOffset = classOffset + 1;
      } else if (line.startsWith('+METHOD')) {
        if (currentClass == null) {
          _errors.add('Line $lineNumber: No class context for method');
          continue;
        }
        List<String> parts = line.split(' ');
        if (parts.length < 2) {
          _errors.add('Line $lineNumber: Invalid method definition');
          continue;
        }
        currentMethod = parts[1];
        classDefinitions[currentClass]![currentMethod] = _memoryOffset;
        bfCode.write('['); // Method start
      } else if (line == '-END') {
        if (currentMethod != null) {
          bfCode.write(']'); // Method end
          currentMethod = null;
        } else if (currentClass != null) {
          currentClass = null;
        }
      } else if (line.startsWith('+VAR')) {
        if (currentClass == null) {
          _errors.add('Line $lineNumber: No class context for variable');
          continue;
        }
        List<String> parts = line.split(' ');
        if (parts.length < 2) {
          _errors.add('Line $lineNumber: Invalid variable definition');
          continue;
        }
        String varName = parts[1];
        String fullVarName = '$currentClass.$varName';
        int varOffset = _allocateMemory(fullVarName, 1);
        bfCode.write('>' * (varOffset - _memoryOffset) + '[-]');
        _memoryOffset = varOffset + 1;
      } else if (line.startsWith('SET')) {
        if (currentClass == null) {
          _errors.add('Line $lineNumber: No class context for SET');
          continue;
        }
        List<String> parts = line.split(' ');
        if (parts.length < 3) {
          _errors.add('Line $lineNumber: Invalid SET command');
          continue;
        }
        String varName = parts[1];
        int value;
        try {
          value = int.parse(parts[2]);
        } catch (e) {
          _errors.add('Line $lineNumber: Invalid number in SET');
          continue;
        }
        String fullVarName = '$currentClass.$varName';
        if (_symbolTable.containsKey(fullVarName)) {
          int varOffset = _symbolTable[fullVarName]!;
          bfCode.write('>' * (varOffset - _memoryOffset));
          bfCode.write('+'.padLeft(value, '+'));
          _memoryOffset = varOffset + 1;
        } else {
          _errors.add('Line $lineNumber: Variable $fullVarName not found');
        }
      } else if (line.startsWith('OUT ')) {
        List<String> parts = line.split(' ');
        if (parts.length < 2) {
          _errors.add('Line $lineNumber: Invalid OUT command');
          continue;
        }
        int value;
        try {
          value = int.parse(parts[1]);
        } catch (e) {
          _errors.add('Line $lineNumber: Invalid number in OUT');
          continue;
        }
        // Use a temporary cell for OUT
        int tempOffset = _allocateMemory('temp_out_$lineNumber', 1);
        bfCode.write('>' * (tempOffset - _memoryOffset));
        bfCode.write('+'.padLeft(value, '+') + '.');
        _outputBuffer.write(String.fromCharCode(value));
        _memoryOffset = tempOffset + 1;
        _freeMemory('temp_out_$lineNumber');
      } else if (line.startsWith('OUTVAR')) {
        if (currentClass == null) {
          _errors.add('Line $lineNumber: No class context for OUTVAR');
          continue;
        }
        List<String> parts = line.split(' ');
        if (parts.length < 2) {
          _errors.add('Line $lineNumber: Invalid OUTVAR command');
          continue;
        }
        String varName = parts[1];
        String fullVarName = '$currentClass.$varName';
        if (_symbolTable.containsKey(fullVarName)) {
          int varOffset = _symbolTable[fullVarName]!;
          bfCode.write('>' * (varOffset - _memoryOffset));
          bfCode.write('.');
          _outputBuffer.write('[$varName]');
          _memoryOffset = varOffset + 1;
        } else {
          _errors.add('Line $lineNumber: Variable $fullVarName not found');
        }
      } else if (line.startsWith('+OBJ')) {
        List<String> parts = line.split(' ');
        if (parts.length < 3) {
          _errors.add('Line $lineNumber: Invalid OBJ command');
          continue;
        }
        String className = parts[1];
        String instanceName = parts[2];
        int objOffset = _allocateMemory(instanceName, 1);
        bfCode.write('>' * (objOffset - _memoryOffset));
        instanceToClass[instanceName] = className; // Map instance to class
        _symbolTable['$instanceName.class'] = objOffset;
        _memoryOffset = objOffset + 1;
      } else if (line.startsWith('CALL')) {
        List<String> parts = line.split('.');
        if (parts.length < 2) {
          _errors.add('Line $lineNumber: Invalid CALL command');
          continue;
        }
        String instanceName =
            parts[0].split(' ').length > 1 ? parts[0].split(' ')[1] : '';
        String methodName = parts[1].trim();
        if (instanceName.isEmpty) {
          _errors
              .add('Line $lineNumber: Invalid instance name in CALL command');
          continue;
        }
        if (!instanceToClass.containsKey(instanceName)) {
          _errors.add('Line $lineNumber: Instance $instanceName not found');
          continue;
        }
        String className = instanceToClass[instanceName]!;
        String current = className;
        while (current.isNotEmpty) {
          if (classDefinitions.containsKey(current) &&
              classDefinitions[current]!.containsKey(methodName)) {
            int methodOffset = classDefinitions[current]![methodName]!;
            bfCode.write('>' * (methodOffset - _memoryOffset));
            _memoryOffset = methodOffset + 1;
            break;
          }
          current = classInheritance[current] ?? '';
        }
        if (!classDefinitions.containsKey(className) ||
            !classDefinitions[className]!.containsKey(methodName)) {
          _errors.add(
              'Line $lineNumber: Method $methodName not found in class $className or its parents');
        }
      }
    }
    return bfCode.toString();
  }

  Future<String> compileBrainfuckToC(String bfCode, String outputCPath) async {
    final cCode = StringBuffer();
    cCode.write('#include <stdio.h>\n#include <unistd.h>\n');
    cCode.write(
        'int main() {\n    char array[30000] = {0};\n    char *ptr = array;\n');
    int indent = 1;
    int i = 0;
    while (i < bfCode.length) {
      final char = bfCode[i];
      switch (char) {
        case '+':
          int count = 1;
          while (i + 1 < bfCode.length && bfCode[i + 1] == '+') {
            count++;
            i++;
          }
          cCode.write(' ' * indent * 4 + '*ptr += $count;\n');
          break;
        case '-':
          int count = 1;
          while (i + 1 < bfCode.length && bfCode[i + 1] == '-') {
            count++;
            i++;
          }
          cCode.write(' ' * indent * 4 + '*ptr -= $count;\n');
          break;
        case '>':
          int count = 1;
          while (i + 1 < bfCode.length && bfCode[i + 1] == '>') {
            count++;
            i++;
          }
          cCode.write(' ' * indent * 4 + 'ptr += $count;\n');
          break;
        case '<':
          int count = 1;
          while (i + 1 < bfCode.length && bfCode[i + 1] == '<') {
            count++;
            i++;
          }
          cCode.write(' ' * indent * 4 + 'ptr -= $count;\n');
          break;
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
      i++;
    }
    cCode.write('    return 0;\n}');
    final code = cCode.toString();
    await File(outputCPath).writeAsString(code);
    return outputCPath;
  }

  Future<void> compileToNative(
      String cPath, String outputPath, Function(String) callback) async {
    if (_gccPath == null) {
      callback('\x1b[31mGCC compiler not initialized\x1b[0m\n');
      return;
    }
    final args = ['-o', outputPath, cPath];
    try {
      final tempDir = await getTemporaryDirectory();
      final outputFile = File(outputPath);
      if (await outputFile.exists()) await outputFile.delete();
      String compiler = _gccPath!;
      String extension = '';
      if (Platform.isWindows) {
        extension = '.exe';
        compiler = 'g++';
      } else if (Platform.isMacOS) {
        extension = '.app';
      } else if (Platform.isLinux) {
        extension = '';
      }
      final fullOutputPath = '$outputPath$extension';
      final result =
          await Process.run(compiler, [...args, '-o', fullOutputPath]);
      if (result.exitCode != 0) {
        throw Exception('GCC compilation failed: ${result.stderr}');
      }
      await outputFile.setExecutable(true);
      callback(
          '\x1b[32mCompilation successful: $fullOutputPath\n${result.stdout}\x1b[0m');
    } catch (e) {
      callback('\x1b[31mCompilation failed: $e\x1b[0m\n');
    }
  }

  Future<void> runCode(List<EditorTab> tabs, int currentTabIndex,
      Function(String) callback) async {
    if (currentTabIndex < 0 || currentTabIndex >= tabs.length) {
      callback('\x1b[31mNo file selected\x1b[0m\n');
      return;
    }
    final tempDir = await getTemporaryDirectory();
    final cPath = '${tempDir.path}/temp.c';
    final exePath = '${tempDir.path}/temp';
    try {
      final bfCode =
          compileEasyBFToBrainfuck(tabs[currentTabIndex].controller.text);
      if (_errors.isNotEmpty) {
        callback('\x1b[31mCompilation errors:\n${_errors.join('\n')}\x1b[0m\n');
        return;
      }
      await compileBrainfuckToC(bfCode, cPath);
      await compileToNative(cPath, exePath, (compileOutput) {
        if (compileOutput.contains('failed')) {
          callback(compileOutput);
          return;
        }
        if (!File(
                '$exePath${Platform.isWindows ? '.exe' : Platform.isMacOS ? '.app' : ''}')
            .existsSync()) {
          callback(
              '\x1b[31mExecutable not found: $exePath${Platform.isWindows ? '.exe' : Platform.isMacOS ? '.app' : ''}\x1b[0m\n');
          return;
        }
        Process.run(exePath, []).then((result) {
          callback('\x1b[32mExecution output:\n${result.stdout}\x1b[0m');
        }).catchError((e) {
          callback('\x1b[31mExecution failed: $e\n${stderr ?? ''}\x1b[0m');
        });
      });
    } catch (e) {
      callback('\x1b[31mRun failed: $e\x1b[0m\n');
    }
  }

  String getLiveOutput() {
    return _outputBuffer.toString();
  }

  List<String> getErrors() {
    return _errors;
  }
}
