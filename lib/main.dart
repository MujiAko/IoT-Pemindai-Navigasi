import 'package:flutter/material.dart';
import 'state/app_state.dart';
import 'theme.dart';
import 'ui/shell.dart';

final appState = AppState();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await appState.load();
  runApp(const NavApp());
}

class NavApp extends StatelessWidget {
  const NavApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (_, _) => MaterialApp(
        title: 'ESP32 Maps',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: appState.themeMode,
        home: const Shell(),
      ),
    );
  }
}