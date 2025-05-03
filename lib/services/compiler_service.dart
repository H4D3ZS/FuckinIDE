import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/editor_tab.dart';
import '../utils/extensions.dart';

class CompilerService {
  String? _gccPath;

  Future<void> setupGcc(Function(String?, String) callback) async {
    try {
      final result = await Process.run('which', ['gcc']);
      if (result.exitCode == 0 && result.stdout.isNotEmpty) {
        _gccPath = result.stdout.trim();
        callback(_gccPath, '\x1b[32mGCC compiler initialized\x1b[0m\n');
      } else {
        throw Exception(
            'GCC not found. Install via Xcode Command Line Tools or Homebrew.');
      }
    } catch (e) {
      callback(null, '\x1b[31mFailed to initialize GCC: $e\x1b[0m\n');
    }
  }

  String compileOOPtoBrainfuck(String code) {
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

  Future<void> compileToNative(
      String cPath, String outputPath, Function(String) callback) async {
    if (_gccPath == null) {
      callback('\x1b[31mGCC compiler not initialized\x1b[0m\n');
      return;
    }
    final args = [cPath, '-o', outputPath];
    try {
      final tempDir = await getTemporaryDirectory();
      final outputFile = File(outputPath);
      if (await outputFile.exists()) await outputFile.delete();
      final result = await Process.run(_gccPath!, args);
      if (result.exitCode != 0)
        throw Exception('GCC compilation failed: ${result.stderr}');
      await outputFile.setExecutable(true);
      callback(
          '\x1b[32mCompilation successful: $outputPath\x1b[0m\n${result.stdout}');
    } catch (e) {
      callback('\x1b[31mCompilation failed: $e\x1b[0m\n');
    }
  }

  Future<void> runCode(List<EditorTab> tabs, int currentTabIndex,
      Function(String) callback) async {
    if (currentTabIndex == -1) return;
    final tempDir = await getTemporaryDirectory();
    final cPath = '${tempDir.path}/temp.c';
    final exePath = '${tempDir.path}/temp';
    await compileBrainfuckToC(
        compileOOPtoBrainfuck(tabs[currentTabIndex].controller.text), cPath);
    await compileToNative(cPath, exePath, (output) {
      if (output.contains('failed')) {
        callback(output);
        return;
      }
      if (!File(exePath).existsSync()) {
        callback('\x1b[31mExecutable not found: $exePath\x1b[0m\n');
        return;
      }
      Process.run(exePath, []).then((result) {
        callback(result.stdout);
      }).catchError((e) {
        callback('\x1b[31mExecution failed: $e\x1b[0m\n');
      });
    });
  }
}
