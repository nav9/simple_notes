//Flutter icons: https://api.flutter.dev/flutter/material/Icons-class.html and https://www.fluttericon.com/
//TODO: Inserting custom dictionary phrases. (//https://pub.dev/packages/flutter_typeahead/example and https://medium.com/saugo360/https-medium-com-saugo360-flutter-using-overlay-to-display-floating-widgets-2e6d0e8decb9)
//TODO: Multi search. 
//TODO: Encryption that's compatible with Python. 
//TODO: Ensuring that archived exported files also contain a Linux version and Android version of Simple Notes to be able to open encrypted files. 
//TODO: Ensure that the note name is a valid Android/Linux filename so have exception handling. 
//TODO: Undo/redo. 
//TODO: Scroll while cycling between search matches.
//TODO: Find and Replace option should not be available in read-only mode of encrypted text
//TODO: On clicking the search button the cursor focus needs to go to the "Find" textfield.
//TODO: The word typed in "Find" needs to persist even when the find bar is closed and reopened. 


// lib/main.dart
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'notes_list.dart';
//import 'session_manager.dart';

// Future<void> main() async {
//   WidgetsFlutterBinding.ensureInitialized();
//   final appDir = await getApplicationDocumentsDirectory();
//   await Hive.initFlutter(appDir.path);
//   await Hive.openBox<Map>('notesBox');
//   await Hive.openBox('settings');

//   runApp(SimpleNotesApp());
// }

// class SimpleNotesApp extends StatelessWidget {
//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(title: 'Simple Notes', theme: ThemeData.dark(), home: NotesListScreen(),);
//   }
// }

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();

  // 🔴 REQUIRED: open boxes BEFORE runApp
  await Hive.openBox<Map>('notesBox');
  await Hive.openBox('settings');

  runApp(const SimpleNotesApp());
}

class SimpleNotesApp extends StatelessWidget {
  const SimpleNotesApp({super.key});

  ThemeMode _themeFromSettings(Box settings) {
    final mode = settings.get('themeMode', defaultValue: 'system');
    switch (mode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsBox = Hive.box('settings');

    return ValueListenableBuilder(
      valueListenable: settingsBox.listenable(),
      builder: (context, Box box, _) {
        return MaterialApp(
          title: 'Simple Notes',
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: _themeFromSettings(box),
          home: NotesListScreen(),
        );
      },
    );
  }
}
