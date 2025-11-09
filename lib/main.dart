import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:universal_io/io.dart';

// Encryption service
class EncryptionService {
  static final iv = encrypt.IV.fromLength(16);

  static String encryptText(String text, String password) {
    final key = encrypt.Key.fromUtf8(password.padRight(32, '\0'));
    final encrypter = encrypt.Encrypter(encrypt.AES(key));
    final encrypted = encrypter.encrypt(text, iv: iv);
    return encrypted.base64;
  }

  static String decryptText(String encryptedText, String password) {
    final key = encrypt.Key.fromUtf8(password.padRight(32, '\0'));
    final encrypter = encrypt.Encrypter(encrypt.AES(key));
    final decrypted = encrypter.decrypt64(encryptedText, iv: iv);
    return decrypted;
  }
}

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
      theme: ThemeData.light(),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: Colors.black,
        scaffoldBackgroundColor: Colors.grey[850],
        appBarTheme: AppBarTheme(color: Colors.grey[900]),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: Colors.blueGrey),
        textTheme: const TextTheme(
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
        listTileTheme: const ListTileThemeData(textColor: Colors.white, iconColor: Colors.white),
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
        content: const Text(
            'The note will be deleted from this app but any files you exported will remain. Proceed with deletion of this note from this app?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('No')),
          TextButton(
            onPressed: () {
              setState(() => theBox.deleteAt(index));
              Navigator.of(context).pop();
            },
            child: Text('Yes'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Simple Notes', style: TextStyle(color: Colors.white70)),
        actions: [
          IconButton(
            icon: Icon(Icons.file_open),
            onPressed: () async {
              // Platform-aware file import
              if (Platform.isAndroid || Platform.isIOS) {
                // Mobile-specific import logic here
              } else {
                // Desktop-specific import logic here
              }
            },
          )
        ],
      ),
      body: ValueListenableBuilder(
        valueListenable: notesBox.listenable(),
        builder: (context, Box box, _) {
          if (box.values.isEmpty) {
            return Center(
              child: Text(
                'Add a new note using the icon below',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            );
          }
          final notes = box.values.toList().cast<String>();
          return ListView.builder(
            itemCount: notes.length,
            itemBuilder: (context, index) {
              final note = notes[index];
              return Card(
                child: ListTile(
                  title: Text(
                    note,
                    style: const TextStyle(color: Colors.white38),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => EditNoteScreen(index: index, note: note),
                    ),
                  ),
                  leading: IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () => _deleteNoteConfirmation(box, index),
                    color: Colors.red[900],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Visibility(
                        visible: index > 0,
                        child: IconButton(
                          icon: Icon(Icons.move_up, color: Colors.grey[700], size: 20),
                          onPressed: () {
                            setState(() {
                              final temp = notes[index];
                              notes[index] = notes[index - 1];
                              notes[index - 1] = temp;
                              box.putAt(index, notes[index]);
                              box.putAt(index - 1, notes[index - 1]);
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 0),
                      Visibility(
                        visible: index < notes.length - 1,
                        child: IconButton(
                          icon: Icon(Icons.move_down, color: Colors.grey[700], size: 20),
                          onPressed: () {
                            setState(() {
                              final temp = notes[index];
                              notes[index] = notes[index + 1];
                              notes[index + 1] = temp;
                              box.putAt(index, notes[index]);
                              box.putAt(index + 1, notes[index + 1]);
                            });
                          },
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
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add, color: Colors.white),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => EditNoteScreen()),
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

  void _saveNote() {
    final notesBox = Hive.box('notesBox');
    if (widget.index != null) {
      notesBox.putAt(widget.index!, _controller.text);
    } else {
      final tempList = [_controller.text];
      tempList.addAll(notesBox.values.cast<String>());
      for (int i = 0; i < tempList.length; i++) {
        if (i < notesBox.length) {
          notesBox.putAt(i, tempList[i]);
        } else {
          notesBox.add(tempList[i]);
        }
      }
    }
    Navigator.pop(context);
  }

  Future<void> _exportNote() async {
    final password = await _showPasswordDialog("Set a password for encryption:");
    if (password == null || password.isEmpty) return;

    final encryptedNote = EncryptionService.encryptText(_controller.text, password);

    if (Platform.isAndroid || Platform.isIOS) {
      var status = await Permission.storage.status;
      if (!status.isGranted) {
        status = await Permission.storage.request();
      }
      if (status.isGranted) {
        final directory = await getExternalStorageDirectory();
        if (directory != null) {
          final path = directory.path;
          final file = File('$path/${DateTime.now().toIso8601String()}.txt');
          await file.writeAsString(encryptedNote);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Saved at ${file.path}')),
          );
        }
      }
    } else {
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Your Note',
        fileName: '${DateTime.now().toIso8601String()}.txt',
      );
      if (outputFile != null) {
        final file = File(outputFile);
        await file.writeAsString(encryptedNote);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved at ${file.path}')),
        );
      }
    }
  }

  Future<String?> _showPasswordDialog(String title) async {
    final passwordController = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: passwordController,
          obscureText: true,
          decoration: InputDecoration(hintText: "Password"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(passwordController.text),
            child: Text("OK"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder textBorder = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(4)),
      borderSide: BorderSide(width: 1, color: Colors.black54),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Note', style: TextStyle(color: Colors.white24)),
        actions: [
          IconButton(
            icon: const Icon(Icons.sd_storage_outlined),
            onPressed: _exportNote,
          ),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveNote,
            color: Colors.yellow,
          ),
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
          style: const TextStyle(color: Colors.white70),
        ),
      ),
    );
  }
}