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
                            floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: Colors.blueGrey,),
                            textTheme: const TextTheme(bodyLarge: TextStyle(color: Colors.white), bodyMedium: TextStyle(color: Colors.white70), labelLarge: TextStyle(color: Colors.white),),
                            inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: Colors.grey[800], border: OutlineInputBorder(), labelStyle: TextStyle(color: Colors.white),),
                            listTileTheme: const ListTileThemeData(textColor: Colors.white, iconColor: Colors.white,),
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
        title: const Text('Delete confirmation'),
        content: const Text('The note will be deleted from this app but any files you exported will remain. Proceed with deletion of this note from this app?'),
        actions: [TextButton(onPressed: () {Navigator.of(context).pop();}, child: Text('No'),),
                  TextButton(onPressed: () {setState(() {theBox.deleteAt(index);});Navigator.of(context).pop();}, child: Text('Yes'),),
                 ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Simple Notes', style: TextStyle(color: Colors.white70)),),
      body: ValueListenableBuilder(
        valueListenable: notesBox.listenable(),
        builder: (context, Box box, _) {
          if (box.values.isEmpty) {return Center(child: Text('Add a new note using the icon below', style: Theme.of(context).textTheme.bodyLarge,),);}

          // Extract notes from the box
          final notes = box.values.toList().cast<String>();
          return ListView.builder(
            itemCount: notes.length,
            itemBuilder: (context, index) {
              final note = notes[index];
              return Card(
                child: ListTile(
                  title: Text(note, style: const TextStyle(color: Colors.white38), maxLines: 3, overflow: TextOverflow.ellipsis,),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => EditNoteScreen(index: index, note: note,),),),
                  leading: IconButton(icon: const Icon(Icons.delete), onPressed: () => _deleteNoteConfirmation(box, index), color: Colors.red[900],),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Visibility(
                      visible: index > 0, // Show only if it's not the first item
                      child: IconButton(
                          icon: Icon(Icons.move_up, color: Colors.grey[700], size: 20),
                          onPressed: index > 0 ? () {
                            setState(() {
                              // Swap notes in the list
                              final temp = notes[index];
                              notes[index] = notes[index - 1];
                              notes[index - 1] = temp;
                              // Update Hive box
                              box.putAt(index, notes[index]);
                              box.putAt(index - 1, notes[index - 1]);
                            });
                          } : null, // Disable if it's the first item
                        ),
                      ),
                      const SizedBox(width: 0),//space between the up and down icons
                      Visibility(
                        visible: index < notes.length - 1, // Show only if it's not the last item
                        child: IconButton(icon: Icon(Icons.move_down, color: Colors.grey[700], size: 20),
                            onPressed: index < notes.length - 1 ? () {
                              setState(() {
                                // Swap notes in the list
                                final temp = notes[index];
                                notes[index] = notes[index + 1];
                                notes[index + 1] = temp;
                                // Update Hive box
                                box.putAt(index, notes[index]);
                                box.putAt(index + 1, notes[index + 1]);
                              });
                            } : null, // Disable if it's the last item
                          ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(child: const Icon(Icons.add, color: Colors.white, ), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => EditNoteScreen(),),),),
    );
  }
}






class EditNoteScreen extends StatefulWidget {
  final int? index; // Make index nullable
  final String? note;

  EditNoteScreen({this.index, this.note}); // Add index here
  @override
  _EditNoteScreenState createState() => _EditNoteScreenState();
}


class _EditNoteScreenState extends State<EditNoteScreen> {
  late TextEditingController _controller;
  bool _isBold = false;
  bool _isItalic = false;
  bool _isUnderline = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.note);
  }

  TextStyle _getTextStyle() {
    return TextStyle(
      fontWeight: _isBold ? FontWeight.bold : FontWeight.normal,
      fontStyle: _isItalic ? FontStyle.italic : FontStyle.normal,
      decoration: _isUnderline ? TextDecoration.underline : TextDecoration.none,
    );
  }

  void _saveNote() {
    final notesBox = Hive.box('notesBox');
    if (widget.index != null) {
      // Update the existing note
      notesBox.putAt(widget.index!, _controller.text);
    } else {
      // Add a new note
      notesBox.add(_controller.text);
    }
    Navigator.pop(context);
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Note'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () {
              _saveNote();
              Navigator.pop(context, _controller.text);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(
                  Icons.format_bold,
                  color: _isBold ? Colors.blue : Colors.grey,
                ),
                onPressed: () => setState(() => _isBold = !_isBold),
              ),
              IconButton(
                icon: Icon(
                  Icons.format_italic,
                  color: _isItalic ? Colors.blue : Colors.grey,
                ),
                onPressed: () => setState(() => _isItalic = !_isItalic),
              ),
              IconButton(
                icon: Icon(
                  Icons.format_underline,
                  color: _isUnderline ? Colors.blue : Colors.grey,
                ),
                onPressed: () => setState(() => _isUnderline = !_isUnderline),
              ),
            ],
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              maxLines: null,
              decoration: const InputDecoration(
                hintText: 'Enter your note',
                border: OutlineInputBorder(),
              ),
              style: _getTextStyle(),
            ),
          ),
        ],
      ),
    );
  }
}

