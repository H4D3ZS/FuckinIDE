import 'package:flutter_code_editor/flutter_code_editor.dart';
import '../utils/highlight_modes.dart';

class EditorTab {
  String path;
  CodeController controller;
  bool isSaved;

  EditorTab(
      {required this.path,
      required CodeController? controller,
      required this.isSaved})
      : controller = controller ??
            CodeController(
                text: 'Brain Fuck Programming', language: brainfuckMode);
}

// import 'package:flutter_code_editor/flutter_code_editor.dart';

// class EditorTab {
//   late final String path;
//   final CodeController controller;
//   bool isSaved;

//   EditorTab({
//     required this.path,
//     required this.controller,
//     required this.isSaved,
//   });
// }
