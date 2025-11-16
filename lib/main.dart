//Flutter icons: https://api.flutter.dev/flutter/material/Icons-class.html
//Flutter icons: https://api.flutter.dev/flutter/material/Icons-class.html and https://www.fluttericon.com/

// lib/main.dart
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'notes_list.dart';
import 'session_manager.dart';

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
    return MaterialApp(
      title: 'Simple Notes',
      theme: ThemeData.dark(),
      home: NotesListScreen(),
    );
  }
}
