//Flutter icons: https://api.flutter.dev/flutter/material/Icons-class.html and https://www.fluttericon.com/
//TODO: Inserting custom dictionary phrases. 
//TODO: Multi search. 
//TODO: Encryption that's compatible with Python. 
//TODO: Ensuring that exported files also contain an Linux version and Android version of Simple Notes to be able to open encrypted files. 
//TODO: Ensure that the note name is a valid Android/Linux filename so have exception handling. 
//TODO: Undo/redo. 
//TODO: Cycle between search matches.
//TODO: Find and Replace option should not be available in read-only mode of encrypted text
//TODO: On clicking the search button the cursor focus needs to go to the "Find" textfield.
//TODO: The word typed in "Find" needs to persist even when the find bar is closed and reopened. 

// lib/main.dart
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'notes_list.dart';
//import 'session_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appDir = await getApplicationDocumentsDirectory();
  await Hive.initFlutter(appDir.path);
  await Hive.openBox<Map>('notesBox');
  runApp(SimpleNotesApp());
}

class SimpleNotesApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(title: 'Simple Notes', theme: ThemeData.dark(), home: NotesListScreen(),);
  }
}
