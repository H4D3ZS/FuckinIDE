import 'package:flutter/material.dart';
import 'package:highlight/highlight_core.dart' show highlight;
import 'pages/ide_home_page.dart';
import 'utils/highlight_modes.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  highlight.registerLanguage('brainfuck', brainfuckMode);
  runApp(const BrainfuckIDE());
}

class BrainfuckIDE extends StatelessWidget {
  const BrainfuckIDE({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fuckin`IDE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
          primary: Colors.indigo,
          secondary: Colors.amber,
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontFamily: 'JetBrainsMono'),
          bodyMedium: TextStyle(fontFamily: 'JetBrainsMono'),
          labelLarge: TextStyle(fontFamily: 'JetBrainsMono'),
        ),
        scaffoldBackgroundColor: Colors.grey[900],
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.indigo,
          foregroundColor: Colors.white,
          elevation: 4,
        ),
      ),
      home: IDEHomePage(),
    );
  }
}
