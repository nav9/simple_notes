import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appDocumentDir = await getApplicationDocumentsDirectory();
  Hive.init(appDocumentDir.path);
  await Hive.openBox('notesBox');
  runApp(SimpleNotesApp());
}

class SimpleNotesApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Simple Notes',
      theme: ThemeData.light(), // Define a light theme if you need it
      darkTheme: ThemeData(brightness: Brightness.dark,
                            primaryColor: Colors.black,
                            scaffoldBackgroundColor: Colors.grey[850], // Set the background to grey
                            appBarTheme: AppBarTheme(color: Colors.grey[900],),
                            floatingActionButtonTheme: FloatingActionButtonThemeData(backgroundColor: Colors.blueGrey,),
                            textTheme: TextTheme(bodyLarge: TextStyle(color: Colors.white), bodyMedium: TextStyle(color: Colors.white70), labelLarge: TextStyle(color: Colors.white),),
                            inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: Colors.grey[800], border: OutlineInputBorder(), labelStyle: TextStyle(color: Colors.white),),
                            listTileTheme: ListTileThemeData(textColor: Colors.white, iconColor: Colors.white,),
                          ),
      themeMode: ThemeMode.dark, // Always use the dark theme
      home: NotesListScreen(),
    );
  }
}

class NotesListScreen extends StatefulWidget {
  @override
  _NotesListScreenState createState() => _NotesListScreenState();
}

class _NotesListScreenState extends State<NotesListScreen> {
  late Box notesBox;

  @override
  void initState() {
    super.initState();
    notesBox = Hive.box('notesBox');
  }

  void _deleteNoteConfirmation(Box theBox, int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete confirmation'),
        content: Text('The note will be deleted from this app but any files you exported will remain. Proceed with deletion of this note from this app?'),
        actions: [TextButton(onPressed: () {Navigator.of(context).pop();}, child: Text('No'),),
                  TextButton(onPressed: () {setState(() {theBox.deleteAt(index);});Navigator.of(context).pop();}, child: Text('Yes'),),
                 ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Simple Notes', style: TextStyle(color: Colors.white70)),),
      body: ValueListenableBuilder(
        valueListenable: notesBox.listenable(),
        builder: (context, Box box, _) {
          if (box.values.isEmpty) {return Center(child: Text('Add a new note using the icon below', style: Theme.of(context).textTheme.bodyLarge,),);}

          return ListView.builder(
            itemCount: box.length,
            itemBuilder: (context, index) {
              final note = box.getAt(index);
              return Card(child: ListTile(
                title: Text(note, style: TextStyle(color: Colors.white38,), maxLines: 3, overflow: TextOverflow.ellipsis,),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => EditNoteScreen(index: index, note: note,),),),
                leading: IconButton(icon: Icon(Icons.delete), onPressed: () {_deleteNoteConfirmation(box, index);}, color: Colors.red[900]),
              ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(child: Icon(Icons.add, color: Colors.white, ),
                                                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => EditNoteScreen(),),),
                                                ),
    );
  }
}

class EditNoteScreen extends StatefulWidget {
  final int? index; // Make index nullable
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

  void _saveNote() {
    final notesBox = Hive.box('notesBox');
    if (widget.index != null) {notesBox.putAt(widget.index!, _controller.text);}
    else {//Add the new note at the top of the list of notes
      //Hive doesn't support inserting at a specific position, a better approach is to copy all existing notes into a new sequence with the new note at the beginning, then overwrite the box keys in sequence.
      final tempList = [_controller.text]; // Start with the new note
      tempList.addAll(notesBox.values.cast<String>()); // Add existing notes to the list

      // Update each item in the box in the new order
      for (int i = 0; i < tempList.length; i++) {
        if (i < notesBox.length) {
          notesBox.putAt(i, tempList[i]); // Update existing key
        } else {
          notesBox.add(tempList[i]); // Add new key if the box is shorter
        }
      }
    }
    Navigator.pop(context);
  }

  Future<void> _exportNote() async {
    var status = await Permission.storage.status;// Check if the permission is already granted
    if (!status.isGranted) {status = await Permission.storage.request();}

    // Proceed with exporting the note only if permission is granted
    if (status.isGranted) {
      final directory = await getExternalStorageDirectory();
      if (directory != null) {
        final path = directory.path;
        final file = File('$path/${DateTime.now().toIso8601String()}.txt');
        await file.writeAsString(_controller.text);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved at ${file.path}'), duration: Duration(milliseconds: 3000),),);
      } else {ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to access external storage')),);}
    } else {ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Storage permission is required to export notes')),);}
  }

  @override
  Widget build(BuildContext context) {
    //Border info: https://stackoverflow.com/a/56488988
    OutlineInputBorder textBorder = OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(4)), borderSide: BorderSide(width: 1,color: Colors.black54),);
    return Scaffold(
      appBar: AppBar(
        title: Text('Edit Note', style: TextStyle(color: Colors.white24)),
        actions: [IconButton(icon: Icon(Icons.sd_storage_outlined), onPressed: _exportNote,),
                  IconButton(icon: Icon(Icons.save), onPressed: _saveNote, color: Colors.yellow),],
      ),
      body: Padding(padding: const EdgeInsets.all(2.0),
                    child: TextField(controller: _controller,
                                     maxLines: null,
                                     decoration: InputDecoration(hintText: 'Enter your note', fillColor: Colors.black54, enabledBorder: textBorder, focusedBorder: textBorder),
                                     keyboardAppearance: Brightness.dark,
                                     style: TextStyle(color: Colors.white70),
                                    ),
                  ),
    );
  }
}
