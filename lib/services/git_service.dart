import 'package:process_run/shell.dart';

class GitService {
  Future<void> gitCommit(String projectPath, Function(String) callback) async {
    if (projectPath.isEmpty) {
      callback('\x1b[31mNo project opened\x1b[0m\n');
      return;
    }
    try {
      final shell = Shell(workingDirectory: projectPath);
      await shell.run('git add .');
      await shell.run('git commit -m "Auto-commit from IDE"');
      callback('\x1b[32mCommitted changes\x1b[0m\n');
    } catch (e) {
      callback('\x1b[31mGit commit failed: $e\x1b[0m\n');
    }
  }

  Future<void> gitPush(String projectPath, Function(String) callback) async {
    if (projectPath.isEmpty) return;
    try {
      final shell = Shell(workingDirectory: projectPath);
      await shell.run('git push origin main');
      callback('\x1b[32mPushed to remote\x1b[0m\n');
    } catch (e) {
      callback('\x1b[31mGit push failed: $e\x1b[0m\n');
    }
  }

  Future<void> gitPull(String projectPath, Function(String) callback) async {
    if (projectPath.isEmpty) return;
    try {
      final shell = Shell(workingDirectory: projectPath);
      await shell.run('git pull origin main');
      callback('\x1b[32mPulled from remote\x1b[0m\n');
    } catch (e) {
      callback('\x1b[31mGit pull failed: $e\x1b[0m\n');
    }
  }
}
