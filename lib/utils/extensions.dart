import 'dart:io';

extension FileExtension on File {
  Future<void> setExecutable(bool executable) async {
    final path = this.path;
    try {
      await Process.run('chmod', [executable ? '+x' : '-x', path]);
    } catch (e) {
      print('Failed to set executable: $e');
    }
  }
}
