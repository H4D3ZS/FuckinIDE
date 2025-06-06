import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart' as xterm;

const Color magenta = Color(0xFFFF00FF);

final lightTerminalTheme = xterm.TerminalTheme(
  foreground: Colors.black,
  background: Colors.white,
  cursor: Colors.black,
  selection: Colors.grey.withOpacity(0.3),
  black: Colors.black,
  red: Colors.red,
  green: Colors.green,
  yellow: Colors.yellow,
  blue: Colors.blue,
  magenta: magenta,
  cyan: Colors.cyan,
  white: Colors.white,
  brightBlack: Colors.grey,
  brightRed: Colors.redAccent,
  brightGreen: Colors.greenAccent,
  brightYellow: Colors.yellowAccent,
  brightBlue: Colors.blueAccent,
  brightMagenta: Colors.pinkAccent,
  brightCyan: Colors.cyanAccent,
  brightWhite: Colors.white70,
  searchHitBackground: Colors.yellow.withOpacity(0.4),
  searchHitBackgroundCurrent: Colors.yellow.withOpacity(0.7),
  searchHitForeground: Colors.black,
);

final darkTerminalTheme = xterm.TerminalTheme(
  foreground: Colors.white,
  background: Colors.black,
  cursor: Colors.white,
  selection: Colors.white.withOpacity(0.3),
  black: Colors.black,
  red: Colors.red,
  green: Colors.green,
  yellow: Colors.yellow,
  blue: Colors.blue,
  magenta: magenta,
  cyan: Colors.cyan,
  white: Colors.white,
  brightBlack: Colors.grey,
  brightRed: Colors.redAccent,
  brightGreen: Colors.greenAccent,
  brightYellow: Colors.yellowAccent,
  brightBlue: Colors.blueAccent,
  brightMagenta: Colors.pinkAccent,
  brightCyan: Colors.cyanAccent,
  brightWhite: Colors.white70,
  searchHitBackground: Colors.yellow.withOpacity(0.4),
  searchHitBackgroundCurrent: Colors.yellow.withOpacity(0.7),
  searchHitForeground: Colors.black,
);
