import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(SimpleNotesApp());
}

class SimpleNotesApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Simple Notes',
      theme: ThemeData.light(),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: Colors.black,
        scaffoldBackgroundColor: Colors.grey[850],
        appBarTheme: AppBarTheme(color: Colors.grey[900]),
        floatingActionButtonTheme: FloatingActionButtonThemeData(backgroundColor: Colors.blueGrey),
        textTheme: TextTheme(
          bodyLarge: TextStyle(color: Colors.white),
          bodyMedium: TextStyle(color: Colors.white70),
          labelLarge: TextStyle(color: Colors.white),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey[800],
          border: OutlineInputBorder(),
          labelStyle: TextStyle(color: Colors.white),
        ),
        listTileTheme: ListTileThemeData(textColor: Colors.white, iconColor: Colors.white),
      ),
      themeMode: ThemeMode.dark,
      home: NotesListScreen(),
    );
  }
}

class NotesListScreen extends StatefulWidget {
  @override
  _NotesListScreenState createState() => _NotesListScreenState();
}

class _NotesListScreenState extends State<NotesListScreen> {
  late Database database;
  List<String> notes = [];

  @override
  void initState() {
    super.initState();
    _initDatabase();
  }

  Future<void> _initDatabase() async {
    final Directory documentsDirectory = await getApplicationDocumentsDirectory();
    final String path = join(documentsDirectory.path, 'notes.db');
    database = await openDatabase(path, version: 1, onCreate: (db, version) {
      return db.execute('CREATE TABLE notes(id INTEGER PRIMARY KEY AUTOINCREMENT, note TEXT)');
    });
    _fetchNotes();
  }

  Future<void> _fetchNotes() async {
    final List<Map<String, dynamic>> maps = await database.query('notes');
    setState(() {
      notes = List.generate(maps.length, (i) => maps[i]['note'] as String);
    });
  }

  void _deleteNoteConfirmation(int index, BuildContext context) {
    showDialog(
      context: context,  // This should be BuildContext
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('Delete confirmation'),
        content: Text('The note will be deleted from this app but any files you exported will remain. Proceed with deletion of this note from this app?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
            },
            child: Text('No'),
          ),
          TextButton(
            onPressed: () {
              _deleteNote(index);
              Navigator.of(dialogContext).pop();
            },
            child: Text('Yes'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteNote(int index) async {
    await database.delete('notes', where: 'id = ?', whereArgs: [index + 1]);
    _fetchNotes();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Simple Notes', style: TextStyle(color: Colors.white70)),
      ),
      body: notes.isEmpty
          ? Center(
        child: Text('Add a new note using the icon below', style: Theme.of(context).textTheme.bodyLarge),
      )
          : ListView.builder(
        itemCount: notes.length,
        itemBuilder: (BuildContext listContext, int index) {
          return Card(
            child: ListTile(
              title: Text(
                notes[index],
                style: TextStyle(color: Colors.white38),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (BuildContext detailContext) => EditNoteScreen(index: index, note: notes[index]),
                ),
              ),
              trailing: IconButton(
                icon: Icon(Icons.delete),
                onPressed: () {
                  _deleteNoteConfirmation(index, context);
                },
                color: Colors.red[900],
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        child: Icon(Icons.add, color: Colors.white),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (BuildContext addContext) => EditNoteScreen()),
        ),
      ),
    );
  }
}

class EditNoteScreen extends StatefulWidget {
  final int? index;
  final String? note;

  EditNoteScreen({this.index, this.note});

  @override
  _EditNoteScreenState createState() => _EditNoteScreenState();
}

class _EditNoteScreenState extends State<EditNoteScreen> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.note);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _saveNote(BuildContext context) async {
    final Database db = await _initDatabase();
    if (widget.index != null) {
      await db.update('notes', {'note': _controller.text},
                      where: 'id = ?',
                      whereArgs: [widget.index! + 1],
                    );
    } else {
      await db.insert('notes', {'note': _controller.text});
    }
    Navigator.pop(context);
  }

  Future<Database> _initDatabase() async {
    final Directory documentsDirectory = await getApplicationDocumentsDirectory();
    final String path = join(documentsDirectory.path, 'notes.db');
    return openDatabase(path);
  }

  Future<void> _exportNote(BuildContext context) async {
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      status = await Permission.storage.request();
    }

    if (status.isGranted) {
      final directory = await getExternalStorageDirectory();
      if (directory != null) {
        final path = directory.path;
        final file = File('$path/${DateTime.now().toIso8601String()}.txt');
        await file.writeAsString(_controller.text);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Note saved as text file at ${file.path}'),
          duration: Duration(milliseconds: 10000),
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to access external storage')));
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Storage permission is required to export notes')));
    }
  }

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder textBorder = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(4)),
      borderSide: BorderSide(width: 1, color: Colors.black54),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text('Edit Note', style: TextStyle(color: Colors.white24)),
        actions: [
          IconButton(icon: Icon(Icons.sd_storage_outlined), onPressed: () => _exportNote(context)),
          IconButton(icon: Icon(Icons.save), onPressed: () => _saveNote(context), color: Colors.yellow),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(2.0),
        child: TextField(
          controller: _controller,
          maxLines: null,
          decoration: InputDecoration(
            hintText: 'Enter your note',
            fillColor: Colors.black54,
            enabledBorder: textBorder,
            focusedBorder: textBorder,
          ),
          keyboardAppearance: Brightness.dark,
          style: TextStyle(color: Colors.white70),
        ),
      ),
    );
  }
}
