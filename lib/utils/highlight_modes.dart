import 'package:flutter/material.dart';
import 'package:highlight/highlight_core.dart' show Mode;

final brainfuckMode = Mode(
  contains: [
    Mode(className: 'keyword', begin: r'[+\-<>[\].,]'),
    Mode(className: 'comment', begin: r'[^+\-<>[\].,]'),
    Mode(className: 'class', begin: r'class\s+\w+'),
    Mode(className: 'method', begin: r'\w+\(\)'),
  ],
);

const monokaiTheme = {
  'keyword': TextStyle(color: Colors.purple),
  'comment': TextStyle(color: Colors.grey),
  'class': TextStyle(color: Colors.blue),
  'method': TextStyle(color: Colors.green),
  'root': TextStyle(backgroundColor: Colors.grey, color: Colors.white),
};
