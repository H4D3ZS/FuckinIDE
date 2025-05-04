import 'dart:io';
import 'dart:convert';
import 'package:fuckin_ide/utils/extensions.dart';
import 'package:path_provider/path_provider.dart';

class EasyBFCompiler {
  List<String> _errors = [];
  String _output = '';

  List<String> getErrors() => _errors;

  String getOutput() => _output;

  Future<void> compileToNative(String code, String outputPath) async {
    _errors.clear();
    _output = '';
    try {
      // Parse EasyBF into AST (simplified parser)
      final ast = _parseEasyBF(code);
      if (_errors.isNotEmpty) throw Exception('Parsing failed');

      // Generate C code
      final cCode = _generateCCode(ast, outputPath);
      final tempDir = await getTemporaryDirectory();
      final cFilePath = '${tempDir.path}/easybf_output.c';
      await File(cFilePath).writeAsString(cCode);

      // Compile to native executable
      await _compileCToExecutable(cFilePath, outputPath);
      _output = 'Compilation successful: $outputPath\n';
    } catch (e) {
      _errors.add('Compilation error: $e');
      _output = 'Compilation failed: $e\n';
    }
  }

  List<dynamic> _parseEasyBF(String code) {
    final lines = code
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    var ast = [];
    String? currentClass;
    Map<String, List<dynamic>> functions = {};

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lineNumber = i + 1;

      if (line.startsWith('+CLASS')) {
        currentClass = line.split(' ')[1];
        ast.add({'type': 'class', 'name': currentClass, 'body': []});
      } else if (line.startsWith('func')) {
        final match =
            RegExp(r'func\s+(\w+)\s*\(([^)]*)\)\s*\{').firstMatch(line);
        if (match != null) {
          final funcName = match.group(1)!;
          final params = match
              .group(2)!
              .split(',')
              .map((p) => p.trim())
              .where((p) => p.isNotEmpty)
              .toList();
          int braceCount = 1;
          int bodyEnd = i;
          for (int j = i + 1; j < lines.length && braceCount > 0; j++) {
            bodyEnd = j;
            braceCount += lines[j].split('').where((c) => c == '{').length;
            braceCount -= lines[j].split('').where((c) => c == '}').length;
          }
          final body = lines.sublist(i + 1, bodyEnd).join('\n');
          functions[funcName] = [
            {'type': 'params', 'params': params},
            {'type': 'body', 'body': body.split('\n')}
          ];
          i = bodyEnd;
        }
      } else if (line.startsWith('var')) {
        final match = RegExp(r'var\s+(\w+)\s*=\s*(.+)$').firstMatch(line);
        if (match != null) {
          final varName = match.group(1)!;
          final value = match.group(2)!;
          ast.last['body']
              .add({'type': 'var', 'name': varName, 'value': value});
        }
      } else if (line.startsWith('if') || line.startsWith('while')) {
        final isIf = line.startsWith('if');
        final match = RegExp(r'(if|while)\s*\((.+)\)\s*\{').firstMatch(line);
        if (match != null) {
          final condition = match.group(2)!;
          int braceCount = 1;
          int blockEnd = i;
          for (int j = i + 1; j < lines.length && braceCount > 0; j++) {
            blockEnd = j;
            braceCount += lines[j].split('').where((c) => c == '{').length;
            braceCount -= lines[j].split('').where((c) => c == '}').length;
          }
          final body = lines.sublist(i + 1, blockEnd).join('\n');
          ast.last['body'].add({
            'type': isIf ? 'if' : 'while',
            'condition': condition,
            'body': body.split('\n')
          });
          i = blockEnd;
        }
      } else if (line.startsWith('print') ||
          line.startsWith('writeFile') ||
          line.startsWith('readFile') ||
          line.startsWith('sendRequest') ||
          line.startsWith('runCommand')) {
        final command = line.split('(')[0].trim();
        final argsMatch = RegExp(r'\((.*?)\)').firstMatch(line);
        if (argsMatch != null) {
          final args =
              argsMatch.group(1)!.split(',').map((a) => a.trim()).toList();
          ast.last['body'].add({'type': command, 'args': args});
        } else {
          _errors.add('Line $lineNumber: Invalid syntax for $command');
        }
      } else if (line.startsWith('CALL')) {
        final match = RegExp(r'CALL\s+(\w+)\.(\w+)').firstMatch(line);
        if (match != null) {
          final instance = match.group(1)!;
          final method = match.group(2)!;
          ast.last['body']
              .add({'type': 'call', 'instance': instance, 'method': method});
        }
      }
    }
    return ast;
  }

  String _generateCCode(List<dynamic> ast, String outputPath) {
    final cCode = StringBuffer();
    cCode.write('#include <stdio.h>\n');
    cCode.write('#include <stdlib.h>\n');
    cCode.write('#include <string.h>\n');
    cCode.write('#ifdef _WIN32\n');
    cCode.write('#include <windows.h>\n');
    cCode.write('#else\n');
    cCode.write('#include <unistd.h>\n');
    cCode.write('#endif\n');
    cCode.write('int main() {\n');

    for (var node in ast) {
      if (node['type'] == 'class') {
        cCode.write('  // Class ${node['name']} definition\n');
        for (var stmt in node['body']) {
          _generateCStatement(stmt, cCode, outputPath);
        }
      }
    }

    cCode.write('  return 0;\n');
    cCode.write('}\n');
    return cCode.toString();
  }

  void _generateCStatement(
      Map<String, dynamic> stmt, StringBuffer cCode, String outputPath) {
    switch (stmt['type']) {
      case 'var':
        cCode.write('  char ${stmt['name']}[] = "${stmt['value']}";\n');
        break;
      case 'print':
        cCode.write('  printf("%s\\n", ${stmt['args'][0]});\n');
        break;
      case 'writeFile':
        cCode.write('  FILE *f = fopen("\${stmt[\'args\'][0]}", "w");\n');
        cCode.write(
            '  if (f) { fprintf(f, "\${stmt[\'args\'][1]}"); fclose(f); }\n');
        break;
      case 'readFile':
        cCode.write(
            '  char buffer[1024]; FILE *f = fopen("\${stmt[\'args\'][0]}", "r");\n');
        cCode.write(
            '  if (f) { fgets(buffer, sizeof(buffer), f); fclose(f); printf("%s\\n", buffer); }\n');
        break;
      case 'sendRequest':
        cCode.write(
            '  // Simulated network request (requires libcurl for real implementation)\n');
        cCode.write(
            '  printf("Sending to \${stmt[\'args\'][0]}: \${stmt[\'args\'][1]}\\n");\n');
        break;
      case 'runCommand':
        cCode.write('#ifdef _WIN32\n');
        cCode.write('  system("\${stmt[\'args\'][0]}");\n');
        cCode.write('#else\n');
        cCode.write('  system("\${stmt[\'args\'][0]}");\n');
        cCode.write('#endif\n');
        break;
      case 'call':
        cCode.write(
            '  // Function call ${stmt['instance']}.${stmt['method']} (placeholder)\n');
        break;
      case 'if':
        cCode.write('  if (${stmt['condition']}) {\n');
        for (var line in stmt['body']) {
          _generateCStatement({
            'type': 'print',
            'args': [line]
          }, cCode, outputPath);
        }
        cCode.write('  }\n');
        break;
      case 'while':
        cCode.write('  while (${stmt['condition']}) {\n');
        for (var line in stmt['body']) {
          _generateCStatement({
            'type': 'print',
            'args': [line]
          }, cCode, outputPath);
        }
        cCode.write('  }\n');
        break;
    }
  }

  Future<void> _compileCToExecutable(
      String cFilePath, String outputPath) async {
    final platform = Platform.operatingSystem;
    String compiler = 'gcc';
    List<String> args = ['-o', outputPath, cFilePath];

    if (platform == 'windows') {
      args.add('-lws2_32'); // For network support
    } else if (platform == 'macos') {
      // macOS requires additional flags for .app, but simplified to binary
    } else if (platform == 'linux') {
      // Standard GCC for Linux
    }

    try {
      final result = await Process.run(compiler, args);
      if (result.exitCode != 0) {
        throw Exception('Compilation failed: ${result.stderr}');
      }
      if (platform == 'macos') {
        // Simplified .app creation (requires more complex bundling in reality)
        await Process.run('mv', [outputPath, '$outputPath.app']);
      }
      await File(outputPath).setExecutable(true);
    } catch (e) {
      _errors.add('Compilation error: $e');
    }
  }
}
